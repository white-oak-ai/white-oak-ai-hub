#!/usr/bin/env bash
# Collect the raw data behind the five SDLC KPIs and write <out>/raw.json.
#
#   collect.sh [--repo owner/repo] [--days 30] [--out DIR] [--branch NAME]
#              [--mode auto|github|git] [--max-prs 100] [--env-regex REGEX] [--bug-regex REGEX]
#
# github mode (preferred): PRs, reviews, deployments/releases and bug issues via `gh api` (REST only).
# git mode (fallback, no network needed): merge/revert/tag history from the local clone.
# Reads data for TWO windows (this period and the one before) so the report can show trends.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$here/_lib.sh"

repo="" days=30 out="sdlc-kpi-report" branch="" mode=auto max_prs=100
env_regex='^(prod|production|live)$'
bug_regex='bug|incident|outage|regression|sev[ -]?[0-9]|p0|p1|critical|hotfix'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --days) days="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --max-prs) max_prs="$2"; shift 2 ;;
    --env-regex) env_regex="$2"; shift 2 ;;
    --bug-regex) bug_regex="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ "$days" =~ ^[0-9]+$ ]] && (( days >= 7 && days <= 180 )) || die "--days must be 7-180"
command -v jq >/dev/null || die "jq is required"
mkdir -p "$out"

[[ -n "$repo" ]] || repo="$(repo_slug)"
now_epoch="$(date -u +%s)"
since="$(iso_days_ago $(( days * 2 )))"   # two windows back
notes=()

if [[ "$mode" == auto ]]; then
  if github_ok "$repo"; then mode=github; else mode=git; fi
fi
[[ "$mode" == github ]] && { github_ok "$repo" || die "GitHub API not reachable for '$repo' (gh installed and signed in? try --mode git)"; }

# ---------------------------------------------------------------- github mode
collect_github() {
  local slug="$1" tmp page items
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN

  [[ -n "$branch" ]] || branch="$(gh api "repos/$slug" --jq .default_branch)"

  # Closed PRs, newest-updated first, stop once we are past the two-window horizon.
  : > "$tmp/pr-list.jsonl"
  for page in 1 2 3 4 5 6 7 8 9 10; do
    items="$(gh api -X GET "repos/$slug/pulls" -f state=closed -f sort=updated -f direction=desc \
      -f per_page=100 -f page="$page")"
    jq -c --arg since "$since" --arg b "$branch" \
      '.[] | select(.merged_at != null and .merged_at >= $since and .base.ref == $b) | .number' <<<"$items" >> "$tmp/pr-list.jsonl"
    [[ "$(jq 'length' <<<"$items")" -lt 100 ]] && break
    [[ "$(jq -r '.[-1].updated_at' <<<"$items")" < "$since" ]] && break
  done
  local total; total="$(wc -l < "$tmp/pr-list.jsonl" | tr -d ' ')"
  if (( total > max_prs )); then
    notes+=("$total PRs merged in the last $((days*2)) days; analysed the newest $max_prs (raise with --max-prs).")
  fi

  # Open PRs (for "waiting on review right now").
  gh api -X GET "repos/$slug/pulls" -f state=open -f per_page=30 --jq '.[] | select(.draft|not) | .number' >> "$tmp/open-list.jsonl" || true
  touch "$tmp/open-list.jsonl"

  note "fetching $(( $(head -n "$max_prs" "$tmp/pr-list.jsonl" | wc -l) + $(wc -l < "$tmp/open-list.jsonl") )) pull requests…"
  { head -n "$max_prs" "$tmp/pr-list.jsonl"; cat "$tmp/open-list.jsonl"; } | sort -un \
    | xargs -P 6 -I{} "$here/fetch-item.sh" pr "$slug" {} > "$tmp/prs.jsonl"
  local failed; failed="$(jq -s '[.[] | select(.error)] | length' "$tmp/prs.jsonl")"
  (( failed == 0 )) || notes+=("$failed PR(s) could not be read and were skipped.")

  # Deployments: production deployments -> releases -> merges (proxy).
  deploy_source=merges
  : > "$tmp/deploys.json"; echo '[]' > "$tmp/deploys.json"
  : > "$tmp/dep-ids.txt"
  for page in 1 2 3 4 5; do
    items="$(gh api -X GET "repos/$slug/deployments" -f per_page=100 -f page="$page" 2>/dev/null)" || items='[]'
    jq -r --arg since "$since" --arg re "$env_regex" \
      '.[] | select(.created_at >= $since and (.environment|test($re;"i"))) | "\(.id)\t\(.created_at)\t\(.ref)"' <<<"$items" >> "$tmp/dep-ids.txt"
    [[ "$(jq 'length' <<<"$items")" -lt 100 ]] && break
    [[ "$(jq -r '.[-1].created_at' <<<"$items")" < "$since" ]] && break
  done
  if [[ -s "$tmp/dep-ids.txt" ]]; then
    deploy_source=deployments
    note "reading status of $(wc -l < "$tmp/dep-ids.txt" | tr -d ' ') production deployments…"
    cut -f1 "$tmp/dep-ids.txt" | head -n 150 | xargs -P 6 -I{} "$here/fetch-item.sh" deploy "$slug" {} > "$tmp/dep-status.jsonl"
    jq -Rn --slurpfile st "$tmp/dep-status.jsonl" '
      ($st | map({key: (.id|tostring), value: .state}) | from_entries) as $s
      | [inputs | split("\t") | {id: (.[0]|tonumber), at: .[1], ref: .[2],
          status: (if ($s[.[0]] // "unknown") == "success" then "success"
                   elif ($s[.[0]] // "") | IN("failure","error") then "failure"
                   else "other" end)}]' < "$tmp/dep-ids.txt" > "$tmp/deploys.json"
  else
    items="$(gh api -X GET "repos/$slug/releases" -f per_page=100 2>/dev/null)" || items='[]'
    jq --arg since "$since" '[.[] | select(.draft|not) | select(.prerelease|not) | select(.published_at != null and .published_at >= $since)
        | {id, at: .published_at, ref: .tag_name, status: "success"}]' <<<"$items" > "$tmp/deploys.json"
    if [[ "$(jq length "$tmp/deploys.json")" -gt 0 ]]; then
      deploy_source=releases
    else
      notes+=("No production deployments or releases found, so deployment frequency counts merges to '$branch' as a stand-in. Publish GitHub Releases or deployment events for a true number.")
    fi
  fi

  # Bug / incident issues (not PRs): changed in the window, plus everything still open.
  : > "$tmp/issues.jsonl"
  for page in 1 2 3 4 5; do
    items="$(gh api -X GET "repos/$slug/issues" -f state=all -f since="$since" -f sort=updated -f direction=desc -f per_page=100 -f page="$page" 2>/dev/null)" || items='[]'
    jq -c '.[]' <<<"$items" >> "$tmp/issues.jsonl"
    [[ "$(jq 'length' <<<"$items")" -lt 100 ]] && break
  done
  for page in 1 2 3; do
    items="$(gh api -X GET "repos/$slug/issues" -f state=open -f per_page=100 -f page="$page" 2>/dev/null)" || items='[]'
    jq -c '.[]' <<<"$items" >> "$tmp/issues.jsonl"
    [[ "$(jq 'length' <<<"$items")" -lt 100 ]] && break
  done
  jq -s --arg re "$bug_regex" '
    map(select(.pull_request == null) | {number, title, url: .html_url, created_at, closed_at, state, labels: [.labels[].name]})
    | unique_by(.number)
    | map(select(.labels | any(test($re; "i"))))' "$tmp/issues.jsonl" > "$tmp/bugs.json"

  jq -n --slurpfile prs "$tmp/prs.jsonl" --slurpfile dep "$tmp/deploys.json" --slurpfile bugs "$tmp/bugs.json" \
        --arg slug "$slug" --arg branch "$branch" --arg src "$deploy_source" '
    ($prs | map(select(.error | not))) as $all
    | {
        prs: ($all | map(select(.merged_at != null)) | map(. + {is_revert: ((.title | test("^revert"; "i")) or (.labels | any(test("revert|rollback|hotfix"; "i"))))})),
        open_prs: ($all | map(select(.state == "open")) | map({number, title, url, author, created_at, first_review_at})),
        deploys: (if $src == "merges"
                  then ($all | map(select(.merged_at != null) | {id: .number, at: .merged_at, ref: .title, status: "success"}))
                  else $dep[0] end),
        bugs: $bugs[0]
      }' > "$tmp/data.json"
  cp "$tmp/data.json" "$out/.data.json"
}

# ------------------------------------------------------------------- git mode
collect_git() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
  if [[ -z "$branch" ]]; then
    branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
    if [[ -z "$branch" ]]; then
      for b in main master trunk; do
        git rev-parse --verify --quiet "$b" >/dev/null && { branch="$b"; break; }
      done
    fi
    [[ -n "$branch" ]] || branch="$(git rev-parse --abbrev-ref HEAD)"
  fi
  local ref="$branch"
  git rev-parse --verify --quiet "origin/$branch" >/dev/null && ref="origin/$branch"
  [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == true ]] && notes+=("This clone is shallow, so older history is missing. Run 'git fetch --unshallow' for complete numbers.")
  notes+=("Collected from local git history only. Review wait and bug fix time need GitHub data (use --mode github with gh signed in).")

  local since_epoch=$(( now_epoch - days * 2 * 86400 ))
  local tmp; tmp="$(mktemp)"; : > "$tmp"
  local sha ct parents subject first
  while IFS='|' read -r sha ct parents subject; do
    first=""
    if [[ "$parents" == *" "* ]]; then   # a merge commit: oldest commit on the merged branch
      first="$(git log --format=%at --reverse "${parents%% *}..${parents##* }" 2>/dev/null | head -n1)"
    fi
    jq -cn --arg sha "$sha" --argjson ct "$ct" --arg first "$first" --arg s "$subject" '{
        number: null, title: $s, url: null, author: null,
        created_at: ($ct|todate), merged_at: ($ct|todate),
        first_commit_at: (if $first == "" then null else ($first|tonumber|todate) end),
        first_review_at: null, additions: null, deletions: null, changed_files: null, labels: [],
        is_revert: ($s | test("^revert"; "i"))}' >> "$tmp"
  done < <(git log "$ref" --first-parent --since="@$since_epoch" --format='%H|%ct|%P|%s')

  local tags; tags="$(mktemp)"
  git for-each-ref --format='%(creatordate:unix)%09%(refname:short)' refs/tags \
    | awk -F'\t' -v s="$since_epoch" '$1 >= s' > "$tags"
  deploy_source=merges
  if [[ -s "$tags" ]]; then
    deploy_source=tags
    jq -Rn '[inputs | split("\t") | {id: .[1], at: (.[0]|tonumber|todate), ref: .[1], status: "success"}]' < "$tags" > "$tmp.dep"
  else
    notes+=("No tags found, so deployment frequency counts commits landing on '$branch' as a stand-in. Tag your releases for a true number.")
    jq -s '[.[] | {id: .title, at: .merged_at, ref: .title, status: "success"}]' "$tmp" > "$tmp.dep"
  fi
  jq -s --slurpfile dep "$tmp.dep" '{prs: ., open_prs: [], deploys: $dep[0], bugs: []}' "$tmp" > "$out/.data.json"
  rm -f "$tmp" "$tmp.dep" "$tags"
}

if [[ "$mode" == github ]]; then collect_github "$repo"; else collect_git; fi

notes_json="$(printf '%s\n' "${notes[@]+"${notes[@]}"}" | jq -R . | jq -s 'map(select(length>0))')"
jq -n --slurpfile d "$out/.data.json" --argjson notes "$notes_json" \
  --arg repo "${repo:-$(basename "$PWD")}" --arg branch "$branch" --arg mode "$mode" --arg src "$deploy_source" \
  --argjson days "$days" --argjson now "$now_epoch" '
  $d[0] + {repo: $repo, branch: $branch, mode: $mode, deploy_source: $src, days: $days, now: $now, notes: $notes}' > "$out/raw.json"
rm -f "$out/.data.json"
echo "wrote $out/raw.json ($mode mode, $(jq '.prs|length' "$out/raw.json") merged PRs/changes, $(jq '.deploys|length' "$out/raw.json") deploys, $(jq '.bugs|length' "$out/raw.json") bug issues)" >&2
