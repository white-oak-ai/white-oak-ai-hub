#!/usr/bin/env bash
# Turn a findings file into files you can hand over when no tracker connector is available:
#   tasks.md   readable report, grouped by priority
#   tasks.csv  one row per task; imports into Jira, Linear, Asana, ClickUp, Trello,
#              GitLab, Azure Boards and spreadsheets (map columns on import)
#
# Usage: export-findings.sh <findings.json> <out-dir>
set -euo pipefail
# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

file="${1:-}"; out="${2:-}"
[[ -n "$file" && -n "$out" ]] || die "usage: $0 <findings.json> <out-dir>"
validate_findings "$file" || exit 1
mkdir -p "$out"

# CSV: Title, Description, Priority, Effort, Category, Labels, Id. Description is the full body.
jq -r --arg label "$QA_LABEL" '
  def bullets(a): (a // []) | map("- " + .) | join("\n");
  def checks(a):  (a // []) | map("- [ ] " + .) | join("\n");
  def body:
    "Why it matters:\n\(.why)\n\nEvidence:\n\(bullets(.evidence))\n\n"
    + (if (.approach // [] | length) > 0 then "Suggested approach:\n\(bullets(.approach))\n\n" else "" end)
    + "Acceptance criteria:\n\(checks(.acceptance))\n\n[quality-audit:\(.id)]";
  def pri: {"P1":"High","P2":"Medium","P3":"Low"}[.];
  ["Title","Description","Priority","Effort","Category","Labels","Id"],
  (sort_by(.priority, .effort)[]
    | [.title, body, (.priority | pri), .effort, .category, "\($label),\($label)/\(.category)", .id])
  | @csv' "$file" > "$out/tasks.csv"

# Markdown report.
{
  echo "# Quality audit tasks"
  echo
  echo "$(jq length "$file") task(s). P1 = fix soon, P2 = plan it, P3 = nice to have. Effort: S under half a day, M a day or two, L longer."
  for p in P1 P2 P3; do
    n="$(jq --arg p "$p" '[.[] | select(.priority == $p)] | length' "$file")"
    (( n > 0 )) || continue
    echo
    echo "## $p ($n)"
    jq -c --arg p "$p" '.[] | select(.priority == $p)' "$file" | while IFS= read -r f; do
      echo
      echo "### $(jq -r '.title' <<<"$f")"
      render_body <<<"$f"
    done
  done
} > "$out/tasks.md"

echo "wrote $out/tasks.md and $out/tasks.csv ($(jq length "$file") tasks)"
