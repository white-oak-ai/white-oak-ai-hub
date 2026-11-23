#!/usr/bin/env bash
# List unresolved review threads on a PR as a JSON array, one object per thread.
#
# Usage: unresolved-threads.sh <pr-number> [--strict]
#
# --strict (used by merge-pr.sh): exit 3 instead of answering when the list might be
# incomplete: more than 100 threads or comments, or resolution can't be read at all.
#
# Output fields: thread_id, comment_id (first comment; use it to reply), path, line,
# outdated, author, body, replies[], url, resolved.
# Includes threads from humans as well as the senior reviewer.
#
# Tries, in order:
#   1. GitHub GraphQL (normal gh on your own machine)
#   2. The /ccr/review_threads REST route (Claude Code cloud sessions, where GraphQL
#      is blocked), joined with the REST review comments for text and authors
#   3. Plain REST review comments. This can't tell resolved from unresolved, so every
#      thread comes back with "resolved": null; check the replies to judge.
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

pr="${1:?Usage: unresolved-threads.sh <pr-number> [--strict]}"
strict=false; [[ "${2:-}" == "--strict" ]] && strict=true
owner_repo="$(repo_slug)" || exit 1
owner="${owner_repo%/*}"
repo="${owner_repo#*/}"

# All review comments over REST (paginated), as one array.
rest_comments() {
  gh api --paginate "repos/$owner_repo/pulls/$pr/comments" | jq -s 'add // []'
}

# 1. GraphQL
if out="$(gh api graphql -F owner="$owner" -F repo="$repo" -F pr="$pr" -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          id isResolved isOutdated path line
          comments(first: 100) {
            pageInfo { hasNextPage }
            nodes { databaseId author { login } body url }
          }
        }
      }
    }
  }
}' 2>/dev/null)"; then
  threads="$(jq '.data.repository.pullRequest.reviewThreads' <<<"$out")"
  if jq -e '.pageInfo.hasNextPage or any(.nodes[]; .comments.pageInfo.hasNextPage)' <<<"$threads" >/dev/null; then
    echo "Warning: this PR has more than 100 threads or comments; some aren't listed. Check the PR on GitHub too." >&2
    $strict && exit 3
  fi
  jq '[.nodes[]
       | select(.isResolved | not)
       | {thread_id: .id, comment_id: .comments.nodes[0].databaseId,
          path, line, outdated: .isOutdated,
          author: .comments.nodes[0].author.login,
          body: .comments.nodes[0].body,
          replies: [.comments.nodes[1:][] | {author: .author.login, body}],
          url: .comments.nodes[0].url, resolved: false}]' <<<"$threads"
  exit 0
fi

# 2. Claude Code cloud route: [{resolved, outdated, path, line, comment_ids: [...]}, ...]
if raw="$(gh api --paginate "repos/$owner_repo/pulls/$pr/ccr/review_threads" 2>/dev/null | jq -s 'add // []')"; then
  # Pass data through files, not argv: comment lists easily pass the 128 KB arg limit.
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  printf '%s' "$raw" > "$tmp/threads.json"
  rest_comments > "$tmp/comments.json" 2>/dev/null || echo "[]" > "$tmp/comments.json"
  if mapped="$(jq -n --slurpfile threads "$tmp/threads.json" --slurpfile comments "$tmp/comments.json" '
      ($comments[0] | map({key: (.id | tostring), value: .}) | from_entries) as $byid
      | $threads[0]
      | map(select(.resolved | not)
        | (.comment_ids // []) as $ids
        | ($byid[($ids[0] | tostring)] // {}) as $first
        | {thread_id: null, comment_id: $ids[0], path, line, outdated,
           author: $first.user.login, body: $first.body,
           replies: [$ids[1:][] | $byid[tostring] // empty | {author: .user.login, body}],
           url: $first.html_url, resolved: false})' 2>/dev/null)" && [[ -n "$mapped" ]]; then
    echo "$mapped"
    exit 0
  fi
  # Exit non-zero so callers don't treat raw (possibly resolved) threads as work.
  echo "Error: couldn't parse ccr/review_threads; raw response follows." >&2
  echo "$raw"
  exit 2
fi

# 3. Plain REST (no resolution info)
echo "Note: couldn't read thread resolution; listing all review threads with resolved=null." >&2
$strict && exit 3
rest_comments | jq '
  . as $all
  | [.[] | select(.in_reply_to_id == null) | . as $top
     | {thread_id: null, comment_id: .id, path, line, outdated: (.line == null),
        author: .user.login, body, url: .html_url, resolved: null,
        replies: [$all[] | select(.in_reply_to_id == $top.id) | {author: .user.login, body}]}]'
