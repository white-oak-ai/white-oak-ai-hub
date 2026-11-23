#!/usr/bin/env bash
# Wait for a PR's CI checks (GitHub Actions check runs and commit statuses) to finish.
#
# Usage: wait-for-checks.sh <pr> --sha <approved-commit> [--timeout <minutes, default 30>]
#
# Exit codes:
#   0  all checks passed, or nothing will run (prints "No CI checks configured" or
#      "No checks ran for this commit"; say which in the report)
#   1  at least one check failed (prints which)
#   2  still running at the timeout, or GitHub couldn't be read reliably
#   3  the PR head isn't the approved commit (something was pushed after review)
#
# It never treats a failed API call as "no CI": unreadable checks mean exit 2.
# Set CHECKS_GRACE (seconds, default 180) to change how long it waits for CI to show up
# before deciding none is coming; success is never reported before then either.
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

pr=""; expected_sha=""; timeout_min=30
while (( $# )); do
  case "$1" in
    --sha) expected_sha="${2:?--sha needs the approved commit}"; shift ;;
    --timeout) timeout_min="${2:?--timeout needs minutes}"; shift ;;
    *) pr="$1" ;;
  esac
  shift
done
[[ -n "$pr" && -n "$expected_sha" ]] \
  || { echo "Usage: wait-for-checks.sh <pr> --sha <approved-commit> [--timeout minutes]" >&2; exit 2; }

repo="$(repo_slug)" || exit 2
sha="$(pr_head_sha "$pr")" || { echo "Couldn't read the PR head." >&2; exit 2; }
if [[ ! "$expected_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--sha must be the full 40-character commit SHA." >&2
  exit 2
fi
if [[ "$sha" != "$expected_sha" ]]; then
  echo "The PR head is ${sha:0:7}, not the approved ${expected_sha:0:7}. New commits need a review first." >&2
  exit 3
fi

grace="${CHECKS_GRACE:-180}"
start=$(date +%s)
deadline=$(( start + timeout_min * 60 ))
grace_until=$(( start + grace ))
api_trouble=""

echo "Waiting for checks on PR #$pr at ${sha:0:7} (up to $timeout_min min)..."
while :; do
  now=$(date +%s)
  ok=true
  runs="$(gh api --paginate "repos/$repo/commits/$sha/check-runs?per_page=100" \
           --jq '.check_runs[] | {name, status, conclusion}' 2>/dev/null)" || ok=false
  statuses="$(gh api --paginate "repos/$repo/commits/$sha/status?per_page=100" \
               --jq '.statuses[] | {name: .context, state}' 2>/dev/null)" || ok=false

  if ! $ok; then
    api_trouble="GitHub's checks API couldn't be read"
  else
    api_trouble=""
    runs="$(jq -s '.' <<<"$runs")"; statuses="$(jq -s '.' <<<"$statuses")"
    total=$(( $(jq length <<<"$runs") + $(jq length <<<"$statuses") ))

    if (( total > 0 )); then
      failed="$(jq -r --argjson st "$statuses" '
        ([.[] | select(.status == "completed" and
           (.conclusion | IN("success", "neutral", "skipped") | not)) | "\(.name): \(.conclusion)"]
         + [$st[] | select(.state == "failure" or .state == "error") | "\(.name): \(.state)"])
        | .[]' <<<"$runs")"
      if [[ -n "$failed" ]]; then
        echo "Checks failed:"
        while IFS= read -r line; do echo "  - $line"; done <<<"$failed"
        exit 1
      fi
      pending="$(jq --argjson st "$statuses" \
        '([.[] | select(.status != "completed")] + [$st[] | select(.state == "pending")]) | length' <<<"$runs")"
      # Don't report success before the grace period: slower CI may not have registered.
      if (( pending == 0 && now >= grace_until )); then
        echo "All $total check(s) passed."
        exit 0
      fi
    elif (( now >= grace_until )); then
      # Only needed when nothing has reported. A failed call means "unknown": keep polling.
      if ! workflows="$(gh api "repos/$repo/actions/workflows" --jq .total_count 2>/dev/null)"; then
        api_trouble="GitHub's Actions API couldn't be read"
      elif (( workflows == 0 )); then
        # No Actions workflows and no commit statuses (external CI) after the grace period.
        echo "No CI checks configured for this repo."
        exit 0
      elif (( now >= start + 2 * grace )); then
        # Workflows exist but none ran for this commit (path filters, push-only triggers).
        echo "No checks ran for this commit ($workflows workflow(s) exist, but none were triggered)."
        exit 0
      fi
    fi
  fi

  if (( now >= deadline )); then
    echo "${api_trouble:-Checks still running} after $timeout_min min." >&2
    exit 2
  fi
  sleep 20
done
