#!/usr/bin/env bash
# Mark an issue as in progress: assign it to you, add the in-progress label, and
# optionally post a comment. Checks again first that nobody else has claimed it.
#
# Usage: claim-issue.sh <issue> [--comment-file <file>]
#
# Exit codes: 0 claimed (or already yours), 1 error, 2 not claimable (closed, assigned to
# someone else, labeled in progress by someone else, or an open PR already references it).
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

n="${1:?Usage: claim-issue.sh <issue> [--comment-file <file>]}"; shift
comment_file=""
while (( $# )); do
  case "$1" in
    --comment-file) comment_file="${2:?--comment-file needs a path}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$comment_file" || -f "$comment_file" ]] || { echo "Error: $comment_file not found." >&2; exit 1; }

owner_repo="$(repo_slug)" || exit 1
me="$(me_login)" || { echo "Error: can't read the signed-in GitHub user." >&2; exit 1; }

issue="$(gh api "repos/$owner_repo/issues/$n")" || { echo "Error: couldn't read issue #$n." >&2; exit 1; }

state="$(jq -r .state <<<"$issue")"
[[ "$state" == "open" ]] || { echo "Not claimable: #$n is $state." >&2; exit 2; }

others="$(jq -r --arg me "$me" '[.assignees[].login | select(. != $me)] | join(", ")' <<<"$issue")"
[[ -z "$others" ]] || { echo "Not claimable: #$n is assigned to $others." >&2; exit 2; }

mine="$(jq -r --arg me "$me" '[.assignees[].login] | index($me) != null' <<<"$issue")"
labeled="$(jq -r --arg l "$IW_LABEL" '[.labels[].name | ascii_downcase] | index($l | ascii_downcase) != null' <<<"$issue")"
if [[ "$labeled" == "true" && "$mine" != "true" ]]; then
  echo "Not claimable: #$n already has the '$IW_LABEL' label." >&2; exit 2
fi

prs="$(open_linked_prs "$owner_repo" "$n")" || { echo "Error: couldn't read #$n's timeline." >&2; exit 1; }
if [[ "$(jq length <<<"$prs")" -gt 0 ]]; then
  echo "Not claimable: open PR(s) already reference #$n: $(jq -r 'map("#\(.number)") | join(", ")' <<<"$prs")" >&2
  exit 2
fi

# Make sure the label exists.
if ! gh api "repos/$owner_repo/labels/$(uri_encode "$IW_LABEL")" >/dev/null 2>&1; then
  gh api -X POST "repos/$owner_repo/labels" -f name="$IW_LABEL" -f color="fbca04" \
    -f description="Someone is actively working on this" >/dev/null \
    || { echo "Error: couldn't create the '$IW_LABEL' label." >&2; exit 1; }
  echo "created label: $IW_LABEL"
fi

# Assign. GitHub silently drops assignees who lack access, so check the result.
if [[ "$mine" != "true" ]]; then
  assigned="$(gh api -X POST "repos/$owner_repo/issues/$n/assignees" -f "assignees[]=$me" \
    | jq -r --arg me "$me" '[.assignees[].login] | index($me) != null')"
  if [[ "$assigned" == "true" ]]; then
    echo "assigned: $me"
  else
    echo "Warning: couldn't assign #$n to $me (no write access?). The label still marks it." >&2
  fi
fi

if [[ "$labeled" != "true" ]]; then
  gh api -X POST "repos/$owner_repo/issues/$n/labels" -f "labels[]=$IW_LABEL" >/dev/null \
    || { echo "Error: couldn't add the '$IW_LABEL' label to #$n." >&2; exit 1; }
  echo "labeled: $IW_LABEL"
fi

if [[ -n "$comment_file" ]]; then
  gh api -X POST "repos/$owner_repo/issues/$n/comments" -F body=@"$comment_file" \
    --jq '"commented: \(.html_url)"' || echo "Warning: claimed, but the comment failed to post." >&2
fi
echo "claimed: #$n"
