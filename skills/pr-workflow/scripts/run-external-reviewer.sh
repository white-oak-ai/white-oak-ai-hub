#!/usr/bin/env bash
# Run the senior review with OpenAI Codex CLI or Google Gemini CLI, in read-only mode,
# and save the findings JSON.
#
# Usage: run-external-reviewer.sh <codex|gemini> <pr> <base-branch> <round> <out.json> [previous-round.json]
#
# Uses the same instructions as the Claude reviewer (agents/senior-code-reviewer.md), so
# the output format matches and post-review.sh works unchanged.
#
# Exit codes, so the skill knows to fall back to the next reviewer:
#   0  findings saved
#   3  CLI not installed
#   4  timed out (default 10 min; set PR_REVIEW_TIMEOUT in seconds)
#   5  CLI failed (often not signed in) or returned no findings JSON
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

tool="${1:?Usage: run-external-reviewer.sh <codex|gemini> <pr> <base> <round> <out.json> [prev.json]}"
pr="${2:?pr required}"; base="${3:?base branch required}"; round="${4:?round required}"
out="${5:?output path required}"; prev="${6:-}"
skill_dir="$(cd "$(dirname "$0")/.." && pwd)"

# Reviewer instructions = the agent file without its frontmatter.
instructions="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm' \
  "$skill_dir/agents/senior-code-reviewer.md")"

prompt="$instructions

## This review

- Repository: $(pwd)
- PR number: $pr
- Base branch: $base
- Round: $round
- See the changes with: git diff origin/$base...HEAD"

if [[ -n "$prev" && -f "$prev" ]]; then
  # Replies newer than the previous round's findings file (all pages).
  since="$(python3 -c 'import os,sys,datetime as d; print(d.datetime.fromtimestamp(os.path.getmtime(sys.argv[1]), d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$prev")"
  replies="$(gh api --paginate "repos/$(repo_slug)/pulls/$pr/comments" 2>/dev/null \
    | jq -s --arg since "$since" 'add // [] | [.[] | select(.in_reply_to_id != null and .created_at > $since) | {path, line, body}]' \
    || echo "[]")"
  prompt="$prompt

## Previous round's findings

$(cat "$prev")

## Replies posted on the PR since then

$replies"
fi

prompt="$prompt

Return only the JSON object described above."

# Create the output folder before the (slow, possibly paid) review runs.
mkdir -p "$(dirname "$out")"

# Keep the raw CLI output if anything fails, so it can be inspected.
raw="$(mktemp)"
trap 'rc=$?; if (( rc )) && [[ -s "$raw" || -s "$raw.err" ]]; then echo "Raw CLI output kept at $raw (errors: $raw.err)" >&2; else rm -f "$raw" "$raw.err"; fi; rm -f "$raw.timedout"' EXIT

# Run a command with stdin closed (so a sign-in prompt can't hang it) and a time limit.
# Portable: macOS has no `timeout` command by default.
run_with_timeout() {
  local secs="$1"; shift
  # Own process group, so a timeout stops the CLI and every process it launched.
  set -m
  "$@" </dev/null &
  local pid=$! rc=0
  set +m
  # Watcher: if the time limit passes, record it and stop the whole group. If it's
  # cancelled first, it stops its own sleep so nothing is left running.
  ( trap 'kill "$s" 2>/dev/null; exit 0' TERM
    sleep "$secs" & s=$!; wait "$s"
    : > "$raw.timedout"
    kill -TERM -- -"$pid" 2>/dev/null
    sleep 5; kill -KILL -- -"$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid" || rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null || true
  return "$rc"
}

limit="${PR_REVIEW_TIMEOUT:-600}"
case "$tool" in
  codex)  cmd=(codex exec --sandbox read-only "$prompt");          install="npm i -g @openai/codex" ;;
  gemini) cmd=(gemini --approval-mode plan -p "$prompt");          install="npm i -g @google/gemini-cli" ;;
  *) echo "Error: tool must be codex or gemini." >&2; exit 1 ;;
esac
command -v "$tool" >/dev/null || { echo "Unavailable: $tool CLI not installed ($install)." >&2; exit 3; }

rc=0
run_with_timeout "$limit" "${cmd[@]}" > "$raw" 2> "$raw.err" || rc=$?
if [[ -e "$raw.timedout" ]] || (( rc == 143 )); then
  echo "Unavailable: $tool timed out after ${limit}s." >&2; exit 4
elif (( rc != 0 )); then
  echo "Unavailable: $tool exited with code $rc (often means it isn't signed in). Last error lines:" >&2
  tail -n 5 "$raw.err" >&2; exit 5
fi

# Pull the last valid JSON object with a "verdict" out of the CLI's output.
python3 - "$raw" "$out" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
dec, found, i = json.JSONDecoder(), None, 0
while (i := text.find("{", i)) != -1:
    try:
        obj, end = dec.raw_decode(text, i)
        if isinstance(obj, dict) and "verdict" in obj:
            found = obj
        i = end
    except json.JSONDecodeError:
        i += 1
if not found:
    print("Unavailable: no reviewer JSON found in the CLI output.", file=sys.stderr)
    sys.exit(5)
found.setdefault("comments", [])
json.dump(found, open(sys.argv[2], "w"), indent=2)
print(f"Saved {sys.argv[2]}: verdict={found['verdict']}, {len(found['comments'])} comment(s)")
PY
