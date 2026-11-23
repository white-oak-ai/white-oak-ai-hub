#!/usr/bin/env bash
# Everything needed to judge whether an issue is ready to work on.
#
# Usage: issue-context.sh <issue>
#
# Prints JSON: the issue, its comments, open PRs that reference it, and the state of any
# issue it says it depends on ("blocked by #12", "depends on #12", ...).
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

n="${1:?Usage: issue-context.sh <issue>}"
owner_repo="$(repo_slug)" || exit 1

issue="$(gh api "repos/$owner_repo/issues/$n")" || { echo "Error: couldn't read issue #$n." >&2; exit 1; }
if jq -e '.pull_request != null' <<<"$issue" >/dev/null; then
  echo "Error: #$n is a pull request, not an issue." >&2; exit 1
fi

comments="$(gh api "repos/$owner_repo/issues/$n/comments?per_page=100" --paginate \
  --jq '.[] | {author: .user.login, association: .author_association, created_at, body}' | jq -s .)" \
  || comments='[]'
prs="$(open_linked_prs "$owner_repo" "$n")" || prs='null'

# Dependencies named in the body or comments.
deps_ids="$(jq -r --argjson c "$comments" '
  [((.body // ""), ($c[].body // "")) | scan("(?i)(?:blocked by|depends on|requires|after)\\s+#(\\d+)") | .[0]]
  | unique | .[]' <<<"$issue")"
deps='[]'
for d in $deps_ids; do
  [[ "$d" == "$n" ]] && continue
  one="$(gh api "repos/$owner_repo/issues/$d" --jq '{number, title, state, is_pr: (.pull_request != null)}' 2>/dev/null)" \
    || one="{\"number\": $d, \"state\": \"unknown\"}"
  deps="$(jq --argjson one "$one" '. + [$one]' <<<"$deps")"
done

jq -n --argjson i "$issue" --argjson c "$comments" --argjson p "$prs" --argjson d "$deps" '{
  number: $i.number, title: $i.title, url: $i.html_url, state: $i.state,
  author: $i.user.login,
  labels: [$i.labels[].name],
  assignees: [$i.assignees[].login],
  milestone: ($i.milestone.title // null),
  created_at: $i.created_at, updated_at: $i.updated_at,
  body: ($i.body // ""),
  comments: $c,
  open_linked_prs: $p,
  dependencies: $d
}'
