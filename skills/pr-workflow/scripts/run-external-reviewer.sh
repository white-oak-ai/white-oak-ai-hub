#!/usr/bin/env bash
# Run the senior review with OpenAI Codex CLI or Google Gemini CLI, in read-only mode,
# and save the findings JSON.
#
# Usage: run-external-reviewer.sh <codex|gemini> <pr> <base-branch> <round> <out.json> [previous-round.json]
#
# Uses the same instructions as the Claude reviewer (agents/senior-code-reviewer.md), so
# the output format matches and post-review.sh works unchanged.
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
trap 'rc=$?; if (( rc )); then echo "Raw CLI output kept at $raw" >&2; else rm -f "$raw"; fi' EXIT

case "$tool" in
  codex)
    command -v codex >/dev/null || { echo "Error: codex CLI not installed (npm i -g @openai/codex)." >&2; exit 1; }
    codex exec --sandbox read-only "$prompt" > "$raw"
    ;;
  gemini)
    command -v gemini >/dev/null || { echo "Error: gemini CLI not installed (npm i -g @google/gemini-cli)." >&2; exit 1; }
    gemini --approval-mode plan -p "$prompt" > "$raw"
    ;;
  *) echo "Error: tool must be codex or gemini." >&2; exit 1 ;;
esac

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
    sys.exit("Error: no reviewer JSON found in the CLI output.")
found.setdefault("comments", [])
json.dump(found, open(sys.argv[2], "w"), indent=2)
print(f"Saved {sys.argv[2]}: verdict={found['verdict']}, {len(found['comments'])} comment(s)")
PY
