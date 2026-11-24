#!/usr/bin/env bash
# File audit findings as GitHub issues (REST only). Safe to re-run: findings already filed
# (open OR closed) are skipped, matched by the hidden marker in the issue body.
#
# Usage: create-github-issues.sh <findings.json> [options]
#   --create          actually create issues. Without it, nothing is written (dry run).
#   --repo OWNER/REPO default: from the origin remote
#   --max N           file at most N issues, highest priority first (default 25)
#   --summary         also create one tracking issue that checklists all filed tasks
#   --assignee LOGIN  assign each new issue
#
# Output: one JSON object per line: {id, status, number, url}
#   status = would-create | created | exists-open | exists-closed | failed
set -euo pipefail
# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

file="${1:-}"; shift || true
create=0; repo=""; max=25; summary=0; assignee=""
while (( $# )); do
  case "$1" in
    --create)   create=1 ;;
    --repo)     repo="${2:?--repo needs a value}"; shift ;;
    --max)      max="${2:?--max needs a value}"; shift ;;
    --summary)  summary=1 ;;
    --assignee) assignee="${2:?--assignee needs a value}"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[[ -n "$file" ]] || die "usage: $0 <findings.json> [--create] [--repo o/r] [--max N] [--summary] [--assignee login]"
[[ "$max" =~ ^[0-9]+$ ]] || die "--max must be a number"
command -v gh >/dev/null || die "gh is not installed"
validate_findings "$file" || exit 1
[[ -n "$repo" ]] || repo="$(repo_slug)"

# Highest priority first, then smallest effort (quick wins), then stable by id.
ordered="$(jq -c 'sort_by(.priority, ({"S":0,"M":1,"L":2}[.effort]), .id) | .[]' "$file")"

# Existing quality issues (open and closed) -> {id: {number,state,url}}.
existing='{}'
if (( create )) || gh auth status >/dev/null 2>&1; then
  # shellcheck disable=SC2016  # jq program, must not expand
  existing="$(gh api -X GET "repos/$repo/issues" -f state=all -f labels="$QA_LABEL" -f per_page=100 --paginate \
      --jq '.[] | select(.pull_request == null)
            | {number, state, url: .html_url, ids: [(.body // "") | scan("quality-audit:([a-z0-9._-]+)") | .[0]]}
            | . as $i | $i.ids[] | {key: ., value: {number: $i.number, state: $i.state, url: $i.url}}' \
    | jq -s 'from_entries' 2>/dev/null || echo '{}')"
fi

ensure_label() { # ensure_label <name> <color> <description>
  local name="$1" color="$2" desc="$3"
  gh api "repos/$repo/labels/$(uri_encode "$name")" >/dev/null 2>&1 && return 0
  gh api -X POST "repos/$repo/labels" -f name="$name" -f color="$color" -f description="$desc" >/dev/null 2>&1 || true
}

declare -A seen_labels=()
prep_labels() { # prep_labels <category> <priority>
  local cat="$1" pri="$2" plabel
  if [[ -z "${seen_labels[base]:-}" ]]; then
    ensure_label "$QA_LABEL" "0e8a16" "Quality improvement found by an audit"; seen_labels[base]=1
  fi
  if [[ -z "${seen_labels[c:$cat]:-}" ]]; then
    ensure_label "$QA_LABEL/$cat" "c5def5" "Quality audit: $cat"; seen_labels["c:$cat"]=1
  fi
  case "$pri" in P1) plabel="priority: high" ;; P2) plabel="priority: medium" ;; *) plabel="priority: low" ;; esac
  if [[ -z "${seen_labels[p:$plabel]:-}" ]]; then
    case "$pri" in P1) ensure_label "$plabel" "b60205" "Fix soon" ;; P2) ensure_label "$plabel" "fbca04" "Plan it" ;; *) ensure_label "$plabel" "0e8a16" "Nice to have" ;; esac
    seen_labels["p:$plabel"]=1
  fi
  echo "$plabel"
}

emit() { jq -nc --arg id "$1" --arg status "$2" --arg number "${3:-}" --arg url "${4:-}" \
  '{id:$id, status:$status, number:(if $number == "" then null else ($number|tonumber) end), url:(if $url == "" then null else $url end)}'; }

filed=0
created_lines=()   # "number|title" for the summary issue
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  id="$(jq -r .id <<<"$f")"; title="$(jq -r .title <<<"$f")"
  cat="$(jq -r .category <<<"$f")"; pri="$(jq -r .priority <<<"$f")"

  hit="$(jq -c --arg id "$id" '.[$id] // empty' <<<"$existing")"
  if [[ -n "$hit" ]]; then
    st="$(jq -r .state <<<"$hit")"
    emit "$id" "exists-$st" "$(jq -r .number <<<"$hit")" "$(jq -r .url <<<"$hit")"
    continue
  fi
  if (( filed >= max )); then
    emit "$id" "skipped-over-max"
    continue
  fi

  if (( ! create )); then
    emit "$id" "would-create"
    filed=$((filed + 1))
    continue
  fi

  plabel="$(prep_labels "$cat" "$pri")"
  body="$(render_body <<<"$f")"
  payload="$(jq -nc --arg t "$title" --arg b "$body" --arg l1 "$QA_LABEL" --arg l2 "$QA_LABEL/$cat" --arg l3 "$plabel" --arg a "$assignee" \
    '{title:$t, body:$b, labels:[$l1,$l2,$l3]} + (if $a == "" then {} else {assignees:[$a]} end)')"
  if resp="$(gh api -X POST "repos/$repo/issues" --input - <<<"$payload" 2>&1)"; then
    num="$(jq -r .number <<<"$resp")"; url="$(jq -r .html_url <<<"$resp")"
    emit "$id" "created" "$num" "$url"
    created_lines+=("$num|$title")
    filed=$((filed + 1))
  else
    echo "failed to create '$id': $resp" >&2
    emit "$id" "failed"
  fi
done <<<"$ordered"

# One tracking issue that lists everything filed in this run.
if (( summary && create && ${#created_lines[@]} > 0 )); then
  ensure_label "$QA_LABEL" "0e8a16" "Quality improvement found by an audit"
  list=""
  for l in "${created_lines[@]}"; do list+="- [ ] #${l%%|*} ${l#*|}"$'\n'; done
  sbody="Tasks from a quality audit on $(date -u +%F). Tick them off as they land.

$list
<sub>Filed by the quality-audit skill</sub>"
  spayload="$(jq -nc --arg t "Quality audit $(date -u +%F): ${#created_lines[@]} improvement tasks" --arg b "$sbody" --arg l "$QA_LABEL" '{title:$t, body:$b, labels:[$l]}')"
  if sresp="$(gh api -X POST "repos/$repo/issues" --input - <<<"$spayload" 2>&1)"; then
    emit "summary" "created" "$(jq -r .number <<<"$sresp")" "$(jq -r .html_url <<<"$sresp")"
  else
    echo "failed to create summary issue: $sresp" >&2
  fi
fi
