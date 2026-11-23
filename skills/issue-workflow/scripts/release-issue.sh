#!/usr/bin/env bash
# Give up a claimed issue: remove the in-progress label, unassign yourself, and explain
# why in a comment, so someone else can pick it up.
#
# Usage: release-issue.sh <issue> <message>
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

n="${1:?Usage: release-issue.sh <issue> <message>}"
msg="${2:?message required: say why the issue is being released}"
owner_repo="$(repo_slug)" || exit 1
me="$(me_login)" || { echo "Error: can't read the signed-in GitHub user." >&2; exit 1; }

gh api -X DELETE "repos/$owner_repo/issues/$n/labels/$(uri_encode "$IW_LABEL")" >/dev/null 2>&1 \
  && echo "unlabeled: $IW_LABEL" || echo "label '$IW_LABEL' wasn't on #$n"
gh api -X DELETE "repos/$owner_repo/issues/$n/assignees" -f "assignees[]=$me" >/dev/null \
  && echo "unassigned: $me" || echo "Warning: couldn't unassign $me from #$n." >&2
gh api -X POST "repos/$owner_repo/issues/$n/comments" -f body="$msg" --jq '"commented: \(.html_url)"' \
  || { echo "Error: couldn't post the comment on #$n." >&2; exit 1; }
