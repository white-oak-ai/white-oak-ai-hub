#!/usr/bin/env bash
# List open issues that could be picked up, with the signals used to score them.
#
# Usage: list-candidates.sh [--limit N] [--all]
#
# Leaves out pull requests, issues assigned to someone else, issues already carrying the
# in-progress label (unless assigned to you), and issues with a skip label (see _lib.sh).
# --all keeps the excluded ones too, each with an "excluded" reason, for debugging.
#
# Prints a JSON array, most-upvoted then oldest first, capped at --limit (default 40).
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

limit=40; all=false
while (( $# )); do
  case "$1" in
    --limit) limit="${2:?--limit needs a number}"; shift 2 ;;
    --all) all=true; shift ;;
    *) echo "Usage: list-candidates.sh [--limit N] [--all]" >&2; exit 1 ;;
  esac
done

owner_repo="$(repo_slug)" || exit 1
me="$(me_login)" || { echo "Error: can't read the signed-in GitHub user. Run 'gh auth login'." >&2; exit 1; }

raw="$(gh api "repos/$owner_repo/issues?state=open&per_page=100" --paginate --jq '.[]')" \
  || { echo "Error: couldn't list issues for $owner_repo." >&2; exit 1; }

jq -s --arg me "$me" --arg label "$IW_LABEL" --arg skip "$IW_SKIP_LABELS" \
      --argjson limit "$limit" --argjson all "$all" '
  ($skip | ascii_downcase | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $skips
  | map(select(.pull_request == null))
  | map(
      ([.labels[].name]) as $labels
      | ([.assignees[].login]) as $assignees
      | {
          number, title, url: .html_url,
          labels: $labels,
          assignees: $assignees,
          milestone: (.milestone.title // null),
          created_at, updated_at,
          comments,
          upvotes: ((.reactions["+1"] // 0) + (.reactions.heart // 0) + (.reactions.rocket // 0)),
          body_chars: ((.body // "") | length),
          has_checklist: ((.body // "") | test("(?m)^\\s*[-*] \\[[ xX]\\]")),
          has_acceptance_criteria: ((.body // "") | test("(?i)acceptance criteria|expected (behaviou?r|result)|definition of done|steps to reproduce")),
          depends_on: ([(.body // "") | scan("(?i)(?:blocked by|depends on|requires|after)\\s+#(\\d+)") | .[0] | tonumber] | unique),
          excluded: (
            if ($assignees | length) > 0 and ($assignees | index($me) | not) then "assigned to \($assignees | join(", "))"
            elif ($labels | map(ascii_downcase) | index($label | ascii_downcase)) and ($assignees | index($me) | not) then "already labeled \($label)"
            elif ([$labels[] | ascii_downcase] - ($skips - [""]) | length) < ($labels | length) then "skip label: \([$labels[] | select(ascii_downcase as $l | $skips | index($l))] | join(", "))"
            else null end)
        })
  | if $all then . else map(select(.excluded == null) | del(.excluded)) end
  | sort_by(-.upvotes, .created_at)
  | .[:$limit]
' <<<"$raw"
