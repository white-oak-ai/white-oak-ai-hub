#!/usr/bin/env bash
# Post the senior reviewer's findings to a PR as a GitHub review with inline comments.
#
# Usage: post-review.sh <pr-number> <findings.json> [round] [--reviewer "<label>"] [--sha <commit>] [--dry-run]
#
# --sha is the commit that was reviewed; the comments attach to it. Defaults to the
# PR's current head.
#
# --reviewer names who did the review in the header, e.g. "Claude Opus" or
# "Claude Opus (fallback: Gemini CLI not signed in)", so the PR shows when a fallback ran.
#
# Always posts with event=COMMENT: GitHub doesn't let you APPROVE or REQUEST_CHANGES
# on your own PR, and the review runs under the author's gh login.
# If GitHub rejects the inline comments (422, usually a line not in the diff), it
# re-posts everything in the review body so nothing is lost.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

dry_run=false; reviewer=""; reviewed_sha=""; pos=()
while (( $# )); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --reviewer) reviewer="${2:?--reviewer needs a label}"; shift ;;
    --sha) reviewed_sha="${2:?--sha needs a commit}"; shift ;;
    *) pos+=("$1") ;;
  esac
  shift
done
pr="${pos[0]:?Usage: post-review.sh <pr-number> <findings.json> [round] [--reviewer label] [--dry-run]}"
findings="${pos[1]:?findings.json path required}"
round="${pos[2]:-1}"
if [[ -n "$reviewed_sha" && ! "$reviewed_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Error: --sha must be the full 40-character commit SHA." >&2; exit 1
fi

jq -e '.verdict and (.comments | type == "array")' "$findings" >/dev/null \
  || { echo "Error: $findings is not valid reviewer JSON (needs verdict and comments[])." >&2; exit 1; }

if $dry_run; then
  repo="OWNER/REPO"; head_sha="HEAD_SHA"
else
  repo="$(repo_slug)"
  head_sha="${reviewed_sha:-$(pr_head_sha "$pr")}"
fi

# Markdown for one comment (shared by inline and fallback modes).
# shellcheck disable=SC2016  # jq program: \( ) must reach jq unexpanded
comment_md='"**[\(.severity)] \(.title)**\n\n\(.body)"
  + (if (.suggestion // "") != "" then "\n\n```suggestion\n\(.suggestion)\n```" else "" end)'

header="$(jq -r --arg round "$round" --arg reviewer "$reviewer" '
  def count(s): [.comments[] | select(.severity == s)] | length;
  "## Senior review — round \($round)\n\n"
  + "**Verdict:** \(if .verdict == "approve" then "✅ approve" else "🔁 changes requested" end)"
  + "  ·  \(count("blocker")) blocker, \(count("major")) major, \(count("minor")) minor, \(count("nit")) nit\n\n"
  + (if $reviewer != "" then "**Reviewer:** \($reviewer)\n\n" else "" end)
  + .summary' "$findings")"
marker=$'\n\n<!-- pr-workflow:senior-review -->'

inline_payload="$(jq --arg sha "$head_sha" --arg body "$header$marker" "
  {commit_id: \$sha, event: \"COMMENT\", body: \$body,
   comments: [.comments[] | {path, line, side: \"RIGHT\", body: ($comment_md)}
              + (if (.start_line // null) != null and .start_line < .line
                 then {start_line, start_side: \"RIGHT\"} else {} end)]}" "$findings")"

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
elif ! grep -q "HTTP 422" <<<"$out"; then
  # Auth, 404, 5xx or a timeout: don't retry, since a timed-out review may already exist.
  echo "Error posting review: $(head -c 500 <<<"$out")" >&2
  exit 1
else
  echo "Inline comments rejected ($(head -c 300 <<<"$out")). Posting all findings in the review body instead." >&2
  out="$(gh api -X POST "repos/$repo/pulls/$pr/reviews" --input - <<<"$fallback_payload")"
  echo "Posted review (body only): $(jq -r .html_url <<<"$out")"
fi
