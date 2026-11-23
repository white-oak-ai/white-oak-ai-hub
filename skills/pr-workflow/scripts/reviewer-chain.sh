#!/usr/bin/env bash
# Print the reviewers to try, in order, and whether each one looks ready to run.
#
# Usage: reviewer-chain.sh
#
# Output: one line per reviewer, tab-separated: <reviewer> <ready|unavailable> <note>
#   1. the saved reviewer (if any)
#   2. the saved fallbacks (default: claude-opus, claude-sonnet), without repeats
#   3. "self": the last resort, a self-review by the session that wrote the code
#
# "ready" only means the tool is installed. A reviewer can still fail when it runs
# (not signed in, network, timeout); then the skill moves on to the next line.
set -uo pipefail

dir="$(dirname "$0")"
primary="$("$dir/reviewer-config.sh" get)"
# (A read loop rather than mapfile: macOS ships bash 3.2, which has no mapfile.)
fallbacks=()
while IFS= read -r line; do [[ -n "$line" ]] && fallbacks+=("$line"); done < <("$dir/reviewer-config.sh" get-fallbacks)

seen=" "
for r in $primary "${fallbacks[@]}" self; do
  [[ -z "$r" || "$seen" == *" $r "* ]] && continue
  seen+="$r "
  case "$r" in
    claude-opus|claude-sonnet)
      printf '%s\tready\truns as a subagent (needs the Agent/Task tool in this session)\n' "$r" ;;
    codex|gemini)
      if command -v "$r" >/dev/null 2>&1; then
        printf '%s\tready\t%s CLI installed\n' "$r" "$r"
      else
        printf '%s\tunavailable\t%s CLI not installed\n' "$r" "$r"
      fi ;;
    copilot)
      if command -v gh >/dev/null 2>&1; then
        printf '%s\tready\tgh installed (needs Copilot code review on the GitHub plan)\n' "$r"
      else
        printf '%s\tunavailable\tgh not installed\n' "$r"
      fi ;;
    self)
      printf '%s\tready\tlast resort: self-review, clearly labeled on the PR\n' "$r" ;;
    *)
      printf '%s\tunavailable\tunknown reviewer name\n' "$r" ;;
  esac
done
