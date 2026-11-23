#!/usr/bin/env bash
# Request (or re-request) a GitHub Copilot code review and wait for it to finish.
#
# Usage: request-copilot-review.sh <pr> [timeout-minutes, default 15]
#
# Copilot posts its review straight on the PR, so there's no findings JSON. After this
# returns, go to the "fix the comments" step. Needs gh v2.88+ and a GitHub plan that
# includes Copilot code review.
set -euo pipefail

pr="${1:?Usage: request-copilot-review.sh <pr> [timeout-minutes]}"
timeout_min="${2:-15}"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

count_reviews() {
  gh api --paginate "repos/$repo/pulls/$pr/reviews" \
    --jq '[.[] | select(.user.login | test("copilot"; "i"))] | length' | jq -s 'add // 0'
}

before="$(count_reviews)"
gh pr edit "$pr" --add-reviewer @copilot >/dev/null
echo "Requested Copilot review on PR #$pr. Waiting up to $timeout_min min..."

deadline=$(( $(date +%s) + timeout_min * 60 ))
while (( $(date +%s) < deadline )); do
  sleep 30
  if (( $(count_reviews) > before )); then
    echo "Copilot review posted."
    exit 0
  fi
done
echo "Error: Copilot hadn't posted a review after $timeout_min min. Check the PR on GitHub." >&2
exit 1
