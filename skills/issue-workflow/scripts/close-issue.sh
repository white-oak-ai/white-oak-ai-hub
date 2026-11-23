#!/usr/bin/env bash
# Close an issue out after its PR merged: comment with the PR and merge commit, remove the
# in-progress label, and close the issue as completed if the merge didn't already.
#
# Usage: close-issue.sh <issue> <pr> [--summary-file <file>]
#
# Refuses (exit 2) unless the PR is merged. Exit 1 on errors.
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

n="${1:?Usage: close-issue.sh <issue> <pr> [--summary-file <file>]}"
pr="${2:?PR number required}"; shift 2
summary_file=""
while (( $# )); do
  case "$1" in
    --summary-file) summary_file="${2:?--summary-file needs a path}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$summary_file" || -f "$summary_file" ]] || { echo "Error: $summary_file not found." >&2; exit 1; }

owner_repo="$(repo_slug)" || exit 1

pr_json="$(gh api "repos/$owner_repo/pulls/$pr")" || { echo "Error: couldn't read PR #$pr." >&2; exit 1; }
if [[ "$(jq -r .merged <<<"$pr_json")" != "true" ]]; then
  echo "Not closing #$n: PR #$pr isn't merged (state: $(jq -r .state <<<"$pr_json"))." >&2
  exit 2
fi
sha="$(jq -r '.merge_commit_sha // "" | .[0:7]' <<<"$pr_json")"
base="$(jq -r .base.ref <<<"$pr_json")"

body_file="$(mktemp)"; trap 'rm -f "$body_file"' EXIT
{
  echo "Resolved by #$pr${sha:+ (merged as $sha into \`$base\`)}."
  if [[ -n "$summary_file" ]]; then echo; cat "$summary_file"; fi
} >"$body_file"
gh api -X POST "repos/$owner_repo/issues/$n/comments" -F body=@"$body_file" --jq '"commented: \(.html_url)"' \
  || echo "Warning: couldn't post the closing comment on #$n." >&2

gh api -X DELETE "repos/$owner_repo/issues/$n/labels/$(uri_encode "$IW_LABEL")" >/dev/null 2>&1 \
  && echo "unlabeled: $IW_LABEL"

state="$(gh api "repos/$owner_repo/issues/$n" --jq .state)" || { echo "Error: couldn't read #$n." >&2; exit 1; }
if [[ "$state" == "open" ]]; then
  gh api -X PATCH "repos/$owner_repo/issues/$n" -f state=closed -f state_reason=completed >/dev/null \
    || { echo "Error: couldn't close #$n." >&2; exit 1; }
  echo "closed: #$n (completed)"
else
  echo "already closed: #$n (the merge closed it)"
fi
