#!/usr/bin/env bash
# Post the senior reviewer's findings to a PR as a GitHub review with inline comments.
#
# Usage: post-review.sh <pr-number> <findings.json> [round] [--dry-run]
#
# Always posts with event=COMMENT: GitHub doesn't let you APPROVE or REQUEST_CHANGES
# on your own PR, and the review runs under the author's gh login.
# If GitHub rejects the inline comments (422, usually a line not in the diff), it
# re-posts everything in the review body so nothing is lost.
set -euo pipefail

pr="${1:?Usage: post-review.sh <pr-number> <findings.json> [round] [--dry-run]}"
findings="${2:?findings.json path required}"
round="${3:-1}"
dry_run=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && dry_run=true; done
[[ "$round" == "--dry-run" ]] && round=1

jq -e '.verdict and (.comments | type == "array")' "$findings" >/dev/null \
  || { echo "Error: $findings is not valid reviewer JSON (needs verdict and comments[])." >&2; exit 1; }

if $dry_run; then
  repo="OWNER/REPO"; head_sha="HEAD_SHA"
else
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  head_sha="$(gh pr view "$pr" --json headRefOid -q .headRefOid)"
fi

# Markdown for one comment (shared by inline and fallback modes).
comment_md='"**[\(.severity)] \(.title)**\n\n\(.body)"
  + (if (.suggestion // "") != "" then "\n\n```suggestion\n\(.suggestion)\n```" else "" end)'

header="$(jq -r --arg round "$round" '
  def count(s): [.comments[] | select(.severity == s)] | length;
  "## Senior review — round \($round)\n\n"
  + "**Verdict:** \(if .verdict == "approve" then "✅ approve" else "🔁 changes requested" end)"
  + "  ·  \(count("blocker")) blocker, \(count("major")) major, \(count("minor")) minor, \(count("nit")) nit\n\n"
  + .summary' "$findings")"
marker=$'\n\n<!-- pr-workflow:senior-review -->'

inline_payload="$(jq --arg sha "$head_sha" --arg body "$header$marker" "
  {commit_id: \$sha, event: \"COMMENT\", body: \$body,
   comments: [.comments[] | {path, line, side: \"RIGHT\", body: ($comment_md)}]}" "$findings")"

fallback_payload="$(jq --arg sha "$head_sha" --arg header "$header" --arg marker "$marker" "
  {commit_id: \$sha, event: \"COMMENT\",
   body: (\$header + \"\n\n---\n\n\"
          + ([.comments[] | \"\`\(.path):\(.line)\`  \" + ($comment_md)] | join(\"\n\n---\n\n\"))
          + \$marker)}" "$findings")"

if $dry_run; then
  echo "== inline payload =="; echo "$inline_payload"
  echo "== fallback payload =="; echo "$fallback_payload"
  exit 0
fi

if out="$(gh api -X POST "repos/$repo/pulls/$pr/reviews" --input - <<<"$inline_payload" 2>&1)"; then
  echo "Posted review with $(jq '.comments | length' "$findings") inline comment(s): $(jq -r .html_url <<<"$out")"
else
  echo "Inline comments rejected ($(head -c 300 <<<"$out")). Posting all findings in the review body instead." >&2
  out="$(gh api -X POST "repos/$repo/pulls/$pr/reviews" --input - <<<"$fallback_payload")"
  echo "Posted review (body only): $(jq -r .html_url <<<"$out")"
fi
