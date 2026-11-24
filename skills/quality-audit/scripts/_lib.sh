#!/usr/bin/env bash
# Shared helpers for quality-audit scripts. Source it; don't run it.
#
# Everything here uses git or GitHub REST. `gh issue ...` and `gh repo view` use GraphQL,
# which is blocked in Claude Code cloud sessions.

# Label put on every issue this skill files. Override with QUALITY_AUDIT_LABEL.
# shellcheck disable=SC2034  # used by the scripts that source this file
QA_LABEL="${QUALITY_AUDIT_LABEL:-quality}"

# Allowed values for finding fields (see references/finding-format.md).
QA_CATEGORIES="unit-tests integration-tests ui-tests e2e-tests test-infra static-analysis types ci-cd security dependencies observability docs performance accessibility reliability config dx architecture"
QA_PRIORITIES="P1 P2 P3"
QA_EFFORTS="S M L"

die() { echo "error: $*" >&2; exit 1; }

# owner/repo from the origin remote, falling back to gh.
repo_slug() {
  local url slug
  url="$(git remote get-url origin 2>/dev/null || true)"
  slug="$(sed -E 's#\.git/?$##; s#/$##; s#.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")"
  if [[ "$slug" =~ ^[^/]+/[^/]+$ ]]; then
    echo "$slug"
  else
    gh repo view --json nameWithOwner -q .nameWithOwner
  fi
}

# URL-encode one path segment (label names can contain slashes and colons).
uri_encode() { jq -rn --arg s "$1" '$s|@uri'; }

# Check a findings file is valid JSON, an array, and every finding has what we need.
# Prints problems to stderr and returns 1 if any.
validate_findings() {
  local file="$1" problems
  [[ -f "$file" ]] || { echo "findings file not found: $file" >&2; return 1; }
  jq -e 'type == "array"' "$file" >/dev/null 2>&1 || { echo "$file must be a JSON array of findings" >&2; return 1; }
  problems="$(jq -r \
    --arg cats "$QA_CATEGORIES" --arg pris "$QA_PRIORITIES" --arg effs "$QA_EFFORTS" '
    ($cats | split(" ")) as $C | ($pris | split(" ")) as $P | ($effs | split(" ")) as $E
    | . as $all
    | ( [ to_entries[] | .key as $i | .value as $f
        | (if ($f.id // "" | test("^[a-z0-9][a-z0-9._-]{2,80}$")) | not then "finding \($i): id must be a lowercase slug (a-z 0-9 . _ -), 3-81 chars" else empty end),
          (if ($f.title // "" | length) < 8 or ($f.title | length) > 120 then "finding \($i) (\($f.id // "?")): title must be 8-120 chars" else empty end),
          (if ($C | index($f.category // "")) == null then "finding \($i) (\($f.id // "?")): category must be one of \($cats)" else empty end),
          (if ($P | index($f.priority // "")) == null then "finding \($i) (\($f.id // "?")): priority must be P1, P2 or P3" else empty end),
          (if ($E | index($f.effort // "")) == null then "finding \($i) (\($f.id // "?")): effort must be S, M or L" else empty end),
          (if ($f.why // "" | length) == 0 then "finding \($i) (\($f.id // "?")): why is required" else empty end),
          (if ($f.evidence // [] | length) == 0 then "finding \($i) (\($f.id // "?")): evidence needs at least one entry (file path, command output, or measured fact)" else empty end),
          (if ($f.acceptance // [] | length) == 0 then "finding \($i) (\($f.id // "?")): acceptance needs at least one checkable criterion" else empty end)
      ] )
      + ( [ $all[].id ] | group_by(.) | map(select(length > 1) | "duplicate id: \(.[0])") )
    | .[]
  ' "$file")"
  if [[ -n "$problems" ]]; then
    echo "$problems" >&2
    return 1
  fi
}

# Markdown body for one finding, read as a JSON object on stdin. Ends with a hidden marker
# so re-running the audit can find (and skip) issues it already filed.
render_body() {
  jq -r '
    def bullets(a): (a // []) | map("- " + .) | join("\n");
    def checks(a):  (a // []) | map("- [ ] " + .) | join("\n");
    "**Category:** \(.category)  ·  **Priority:** \(.priority)  ·  **Effort:** \(.effort)\n\n"
    + "## Why it matters\n\(.why)\n\n"
    + "## Evidence\n\(bullets(.evidence))\n\n"
    + (if (.approach // [] | length) > 0 then "## Suggested approach\n\(bullets(.approach))\n\n" else "" end)
    + "## Acceptance criteria\n\(checks(.acceptance))\n\n"
    + "---\n<sub>Filed by the quality-audit skill · finding `\(.id)`</sub>\n"
    + "<!-- quality-audit:\(.id) -->"
  '
}
