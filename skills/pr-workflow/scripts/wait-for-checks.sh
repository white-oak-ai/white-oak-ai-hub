#!/usr/bin/env bash
# Wait for a PR's CI checks (GitHub Actions check runs and commit statuses) to finish.
#
# Usage: wait-for-checks.sh <pr> [timeout-minutes, default 30]
#
# Exit codes:
#   0  all checks passed, or the repo has no CI at all (prints "No CI checks configured")
#   1  at least one check failed (prints which)
#   2  checks still running at the timeout
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

pr="${1:?Usage: wait-for-checks.sh <pr> [timeout-minutes]}"
timeout_min="${2:-30}"
repo="$(repo_slug)" || exit 1
sha="$(pr_head_sha "$pr")" || exit 1
deadline=$(( $(date +%s) + timeout_min * 60 ))
grace_until=$(( $(date +%s) + 90 ))   # give CI time to start before deciding there is none

echo "Waiting for checks on PR #$pr at ${sha:0:7} (up to $timeout_min min)..."
while :; do
  runs="$(gh api --paginate "repos/$repo/commits/$sha/check-runs" \
           --jq '.check_runs[] | {name, status, conclusion}' 2>/dev/null | jq -s '.')" || runs="[]"
  statuses="$(gh api "repos/$repo/commits/$sha/status" \
               --jq '[.statuses[] | {name: .context, state}]' 2>/dev/null)" || statuses="[]"

  total=$(( $(jq length <<<"$runs") + $(jq length <<<"$statuses") ))
  if (( total == 0 )); then
    workflows="$(gh api "repos/$repo/actions/workflows" --jq .total_count 2>/dev/null || echo 0)"
    if (( workflows == 0 )) && (( $(date +%s) >= grace_until )); then
      echo "No CI checks configured for this repo."
      exit 0
    fi
  else
    failed="$(jq -r --argjson st "$statuses" '
      ([.[] | select(.status == "completed" and
         (.conclusion | IN("success", "neutral", "skipped") | not)) | "\(.name): \(.conclusion)"]
       + [$st[] | select(.state == "failure" or .state == "error") | "\(.name): \(.state)"])
      | .[]' <<<"$runs")"
    if [[ -n "$failed" ]]; then
      echo "Checks failed:"; echo "$failed" | sed 's/^/  - /'
      exit 1
    fi
    pending="$(jq --argjson st "$statuses" \
      '([.[] | select(.status != "completed")] + [$st[] | select(.state == "pending")]) | length' <<<"$runs")"
    if (( pending == 0 )); then
      echo "All $total check(s) passed."
      exit 0
    fi
  fi

  if (( $(date +%s) >= deadline )); then
    echo "Checks still running after $timeout_min min." >&2
    exit 2
  fi
  sleep 20
done
