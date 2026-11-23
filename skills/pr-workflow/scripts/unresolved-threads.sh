#!/usr/bin/env bash
# List unresolved review threads on a PR as a JSON array, one object per thread.
#
# Usage: unresolved-threads.sh <pr-number>
#
# Output fields: thread_id, comment_id (first comment; use it to reply), path, line,
# outdated, author, body, replies[], url, resolved.
# Includes threads from humans as well as the senior reviewer.
#
# Tries, in order:
#   1. GitHub GraphQL (normal gh on your own machine)
#   2. The /ccr/review_threads REST route (Claude Code cloud sessions, where GraphQL
#      is blocked)
#   3. Plain REST review comments. This can't tell resolved from unresolved, so every
#      thread comes back with "resolved": null; check the replies to judge.
set -uo pipefail

pr="${1:?Usage: unresolved-threads.sh <pr-number>}"
owner_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || exit 1
owner="${owner_repo%/*}"
repo="${owner_repo#*/}"

# 1. GraphQL
if out="$(gh api graphql -F owner="$owner" -F repo="$repo" -F pr="$pr" -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line
          comments(first: 50) { nodes { databaseId author { login } body url } }
        }
      }
    }
  }
}' --jq '
  [.data.repository.pullRequest.reviewThreads.nodes[]
   | select(.isResolved | not)
   | {thread_id: .id, comment_id: .comments.nodes[0].databaseId,
      path, line, outdated: .isOutdated,
      author: .comments.nodes[0].author.login,
      body: .comments.nodes[0].body,
      replies: [.comments.nodes[1:][] | {author: .author.login, body}],
      url: .comments.nodes[0].url, resolved: false}]' 2>/dev/null)"; then
  echo "$out"; exit 0
fi

# 2. Claude Code cloud route
if raw="$(gh api "repos/$owner_repo/pulls/$pr/ccr/review_threads" 2>/dev/null)"; then
  mapped="$(jq '
    (if type == "array" then . else (.threads // .review_threads // .data // []) end)
    | map(select((.is_resolved // .isResolved // .resolved // false) | not)
      | (.comments // []) as $c
      | {thread_id: (.id // .thread_id // .node_id),
         comment_id: ($c[0].id // $c[0].database_id // .comment_id),
         path: (.path // $c[0].path), line: (.line // $c[0].line),
         outdated: (.is_outdated // .isOutdated // null),
         author: ($c[0].user.login // $c[0].author.login // null),
         body: ($c[0].body // null),
         replies: [$c[1:][] | {author: (.user.login // .author.login), body}],
         url: ($c[0].html_url // $c[0].url // null), resolved: false})' <<<"$raw" 2>/dev/null)"
  if [[ -n "$mapped" && "$mapped" != "[]" ]] || jq -e 'length == 0' <<<"$raw" >/dev/null 2>&1; then
    echo "${mapped:-[]}"
  else
    echo "Note: unexpected shape from ccr/review_threads; raw response follows." >&2
    echo "$raw"
  fi
  exit 0
fi

# 3. Plain REST (no resolution info)
echo "Note: couldn't read thread resolution; listing all review threads with resolved=null." >&2
gh api --paginate "repos/$owner_repo/pulls/$pr/comments" | jq -s '
  add // [] | . as $all
  | [.[] | select(.in_reply_to_id == null) | . as $top
     | {thread_id: null, comment_id: .id, path, line, outdated: (.line == null),
        author: .user.login, body, url: .html_url, resolved: null,
        replies: [$all[] | select(.in_reply_to_id == $top.id) | {author: .user.login, body}]}]'
