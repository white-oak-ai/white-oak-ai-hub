#!/usr/bin/env bash
# Merge a PR, but only if it's safe to. Refuses (exit 1) and says why otherwise.
#
# Usage: merge-pr.sh <pr> [--method merge|squash|rebase] [--dry-run]
#
# Refuses when the PR:
#   - is closed, a draft, or targets a branch other than the repo's default
#     (a stacked PR: merge the PR below it first, then retarget this one)
#   - has unresolved review threads (including ones pushed back for a human to decide)
#   - isn't "clean" on GitHub: conflicts, out of date, failing checks, or blocked by
#     branch protection such as a required human approval
# It never bypasses branch protection. The merge is pinned to the head commit that was
# checked, so a push in the meantime makes it fail instead of merging unreviewed code.
#
# Method: --method if given, else the first the repo allows of merge, squash, rebase.
# A merge commit is preferred because it keeps the "Fixed in <sha>" replies pointing at
# real commits.
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

pr=""; method=""; dry_run=false
while (( $# )); do
  case "$1" in
    --method) method="${2:?--method needs merge, squash or rebase}"; shift ;;
    --dry-run) dry_run=true ;;
    *) pr="$1" ;;
  esac
  shift
done
[[ -n "$pr" ]] || { echo "Usage: merge-pr.sh <pr> [--method merge|squash|rebase] [--dry-run]" >&2; exit 1; }

repo="$(repo_slug)" || exit 1
refuse() { echo "Not merging PR #$pr: $*" >&2; exit 1; }

repo_json="$(gh api "repos/$repo")" || refuse "couldn't read the repo settings."
default_branch="$(jq -r .default_branch <<<"$repo_json")"

# mergeable_state can be "unknown" for a few seconds while GitHub computes it.
for _ in 1 2 3 4 5 6; do
  pr_json="$(gh api "repos/$repo/pulls/$pr")" || refuse "couldn't read the PR."
  state="$(jq -r .mergeable_state <<<"$pr_json")"
  [[ "$state" != "unknown" ]] && break
  sleep 5
done

[[ "$(jq -r .state <<<"$pr_json")" == "open" ]] || refuse "it isn't open."
[[ "$(jq -r .draft <<<"$pr_json")" == "false" ]] || refuse "it's a draft."
base="$(jq -r .base.ref <<<"$pr_json")"
[[ "$base" == "$default_branch" ]] \
  || refuse "it targets '$base', not '$default_branch'. Merge the PR for '$base' first, then retarget this one."

threads="$("$(dirname "$0")/unresolved-threads.sh" "$pr" 2>/dev/null)" \
  || refuse "couldn't check review threads."
open_threads="$(jq 'length' <<<"$threads" 2>/dev/null || echo "?")"
[[ "$open_threads" == "0" ]] || refuse "$open_threads review thread(s) are still unresolved."

case "$state" in
  clean|has_hooks) ;;
  blocked)  refuse "branch protection is blocking it (for example, a required human approval or check)." ;;
  dirty)    refuse "it has merge conflicts." ;;
  behind)   refuse "it's behind '$base'; update the branch first." ;;
  unstable) refuse "some checks are failing." ;;
  *)        refuse "GitHub reports merge state '$state'." ;;
esac

if [[ -z "$method" ]]; then
  for m in merge squash rebase; do
    key="allow_${m}_merge"; [[ "$m" == "merge" ]] && key="allow_merge_commit"
    if [[ "$(jq -r ".$key" <<<"$repo_json")" == "true" ]]; then method="$m"; break; fi
  done
  [[ -n "$method" ]] || refuse "the repo allows no merge method."
fi

head_sha="$(jq -r .head.sha <<<"$pr_json")"
if $dry_run; then
  echo "Would merge PR #$pr into $base with method '$method' at ${head_sha:0:7}."
  exit 0
fi

out="$(gh api -X PUT "repos/$repo/pulls/$pr/merge" -f merge_method="$method" -f sha="$head_sha" 2>&1)" \
  || refuse "GitHub rejected the merge: $(head -c 300 <<<"$out")"
echo "Merged PR #$pr into $base ($method): $(jq -r '.sha[0:7]' <<<"$out")"
