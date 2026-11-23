#!/usr/bin/env bash
# Remember which AI reviews PRs, so the skill asks only once.
#
# Usage: reviewer-config.sh get            -> prints the saved reviewer, or nothing
#        reviewer-config.sh set <reviewer> -> saves it
#        reviewer-config.sh clear          -> forgets it (the skill will ask again)
#
# Reviewers: claude-opus | claude-sonnet | codex | gemini | copilot
# Saved per user (not per repo) at:
#   ${XDG_CONFIG_HOME:-~/.config}/white-oak-ai-hub/pr-workflow.json
set -euo pipefail

valid="claude-opus claude-sonnet codex gemini copilot"
dir="${XDG_CONFIG_HOME:-$HOME/.config}/white-oak-ai-hub"
file="$dir/pr-workflow.json"

case "${1:-}" in
  get)
    [[ -f "$file" ]] && jq -r '.reviewer // empty' "$file" || true
    ;;
  set)
    r="${2:?Usage: reviewer-config.sh set <$valid>}"
    [[ " $valid " == *" $r "* ]] || { echo "Error: reviewer must be one of: $valid" >&2; exit 1; }
    mkdir -p "$dir"
    # Start fresh if the file is missing or isn't valid JSON.
    existing="{}"
    if [[ -f "$file" ]] && jq -e . "$file" >/dev/null 2>&1; then existing="$(cat "$file")"; fi
    jq --arg r "$r" '.reviewer = $r' <<<"$existing" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "Saved PR reviewer: $r ($file)"
    ;;
  clear)
    if [[ -f "$file" ]]; then
      if jq -e . "$file" >/dev/null 2>&1; then
        jq 'del(.reviewer)' "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
      else
        rm -f "$file"
      fi
    fi
    echo "Cleared saved PR reviewer."
    ;;
  *)
    echo "Usage: $0 get | set <reviewer> | clear" >&2; exit 1
    ;;
esac
