#!/usr/bin/env bash
# Remember which AI reviews PRs, so the skill asks only once.
#
# Usage: reviewer-config.sh get                     -> prints the saved reviewer, or nothing
#        reviewer-config.sh set <reviewer>          -> saves it
#        reviewer-config.sh clear                   -> forgets it (the skill will ask again)
#        reviewer-config.sh get-fallbacks           -> fallback order, one per line
#        reviewer-config.sh set-fallbacks <a,b,...> -> saves the fallback order
#        reviewer-config.sh get-auto-merge          -> "on" (default) or "off"
#        reviewer-config.sh set-auto-merge <on|off> -> merge automatically when it's safe?
#
# Fallbacks are tried, in order, when the main reviewer can't run. The default is
# claude-opus, then claude-sonnet.
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
  get-fallbacks)
    if [[ -f "$file" ]] && jq -e '.fallbacks | type == "array" and length > 0' "$file" >/dev/null 2>&1; then
      jq -r '.fallbacks[]' "$file"
    else
      printf '%s\n' claude-opus claude-sonnet
    fi
    ;;
  set-fallbacks)
    list="${2:?Usage: reviewer-config.sh set-fallbacks <reviewer,reviewer,...>}"
    IFS=',' read -r -a items <<<"$list"
    for r in "${items[@]}"; do
      [[ " $valid " == *" $r "* ]] || { echo "Error: '$r' isn't a reviewer. Use: $valid" >&2; exit 1; }
    done
    mkdir -p "$dir"
    existing="{}"
    if [[ -f "$file" ]] && jq -e . "$file" >/dev/null 2>&1; then existing="$(cat "$file")"; fi
    jq --arg l "$list" '.fallbacks = ($l | split(","))' <<<"$existing" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "Saved fallback order: ${list//,/ → }"
    ;;
  get-auto-merge)
    if [[ -f "$file" ]] && [[ "$(jq -r '.auto_merge' "$file" 2>/dev/null)" == "false" ]]; then
      echo off
    else
      echo on
    fi
    ;;
  set-auto-merge)
    v="${2:?Usage: reviewer-config.sh set-auto-merge <on|off>}"
    case "$v" in on) b=true ;; off) b=false ;; *) echo "Error: use on or off." >&2; exit 1 ;; esac
    mkdir -p "$dir"
    existing="{}"
    if [[ -f "$file" ]] && jq -e . "$file" >/dev/null 2>&1; then existing="$(cat "$file")"; fi
    jq --argjson b "$b" '.auto_merge = $b' <<<"$existing" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "Auto-merge: $v"
    ;;
  *)
    echo "Usage: $0 get | set <reviewer> | clear | get-fallbacks | set-fallbacks <a,b,...> | get-auto-merge | set-auto-merge <on|off>" >&2; exit 1
    ;;
esac
