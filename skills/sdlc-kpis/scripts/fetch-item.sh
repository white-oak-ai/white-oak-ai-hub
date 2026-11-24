#!/usr/bin/env bash
# Fetch one pull request or deployment from GitHub and print one JSON line.
# Called by collect.sh through xargs; not meant to be run by hand.
#   fetch-item.sh pr     <owner/repo> <number>
#   fetch-item.sh deploy <owner/repo> <id>
set -uo pipefail

kind="${1:-}" slug="${2:-}" id="${3:-}"
[[ -n "$kind" && -n "$slug" && -n "$id" ]] || { echo "usage: $0 pr|deploy <owner/repo> <id>" >&2; exit 2; }

case "$kind" in
  pr)
    detail="$(gh api "repos/$slug/pulls/$id" 2>/dev/null)" || { echo "{\"number\":$id,\"error\":true}"; exit 0; }
    # Oldest commit date on the PR, and the first review by a human other than the author.
    first_commit="$(gh api -X GET "repos/$slug/pulls/$id/commits" -f per_page=100 \
      --jq '[.[].commit.author.date] | min // empty' 2>/dev/null || true)"
    author="$(jq -r '.user.login // ""' <<<"$detail")"
    first_review="$(gh api -X GET "repos/$slug/pulls/$id/reviews" -f per_page=100 2>/dev/null \
      | jq -r --arg a "$author" '[.[] | select(.user.type != "Bot" and .user.login != $a and .submitted_at != null) | .submitted_at] | min // empty' 2>/dev/null || true)"
    jq -c --arg fc "$first_commit" --arg fr "$first_review" '{
        number, title, url: .html_url, author: .user.login, state, draft,
        created_at, merged_at, base: .base.ref,
        first_commit_at: (if $fc == "" then null else $fc end),
        first_review_at: (if $fr == "" then null else $fr end),
        additions, deletions, changed_files,
        labels: [.labels[].name]
      }' <<<"$detail"
    ;;
  deploy)
    gh api -X GET "repos/$slug/deployments/$id/statuses" -f per_page=1 2>/dev/null \
      | jq -c --argjson id "$id" '{id: $id, state: (.[0].state // "unknown")}' 2>/dev/null \
      || echo "{\"id\":$id,\"state\":\"unknown\"}"
    ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac
