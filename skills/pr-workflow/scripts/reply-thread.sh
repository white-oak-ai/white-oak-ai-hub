#!/usr/bin/env bash
# Reply to a review thread and optionally resolve it.
#
# Usage: reply-thread.sh <pr> <comment_id> <thread_id|-> <message> [--resolve]
#
# comment_id and thread_id come from unresolved-threads.sh. Pass "-" for thread_id if
# you don't have one. Use --resolve when the comment was fixed; leave it off when you
# disagree and are explaining why, so a human can decide.
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

pr="${1:?Usage: reply-thread.sh <pr> <comment_id> <thread_id|-> <message> [--resolve]}"
comment="${2:?comment_id required}"
thread="${3:?thread_id required (or -)}"
msg="${4:?message required}"
resolve="${5:-}"
owner_repo="$(repo_slug)" || exit 1

# Reply over plain REST, which works everywhere.
gh api -X POST "repos/$owner_repo/pulls/$pr/comments/$comment/replies" -f body="$msg" \
  --jq '"replied: \(.html_url)"' || { echo "Error: reply failed." >&2; exit 1; }

[[ "$resolve" == "--resolve" ]] || exit 0

# Resolve: GraphQL first, then the Claude Code cloud route.
if [[ "$thread" != "-" ]] && gh api graphql -F thread="$thread" -f query='
  mutation($thread: ID!) {
    resolveReviewThread(input: {threadId: $thread}) { thread { isResolved } }
  }' --jq '"resolved: \(.data.resolveReviewThread.thread.isResolved)"' 2>/dev/null; then
  exit 0
fi
if gh api -X POST "repos/$owner_repo/pulls/$pr/ccr/comments/$comment/resolve" >/dev/null 2>&1; then
  echo "resolved: true"
  exit 0
fi
echo "Warning: reply posted, but the thread couldn't be resolved automatically. Resolve it on GitHub." >&2
