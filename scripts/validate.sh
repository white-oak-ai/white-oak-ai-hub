#!/usr/bin/env bash
# Check every skills/*/SKILL.md for required frontmatter.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
count=0

for dir in "$root"/skills/*/; do
  [[ -d "$dir" ]] || continue
  count=$((count + 1))
  folder="$(basename "$dir")"
  file="$dir/SKILL.md"
  before=$fail; fail=0

  if [[ ! -f "$file" ]]; then
    echo "✗ $folder: missing SKILL.md"; fail=1; continue
  fi
  if [[ "$(head -n1 "$file")" != "---" ]]; then
    echo "✗ $folder: SKILL.md must start with '---' frontmatter"; fail=1; continue
  fi

  front="$(awk 'NR==1{next} /^---$/{exit} {print}' "$file")"
  name="$(echo "$front" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  desc="$(echo "$front" | sed -n 's/^description:[[:space:]]*//p' | head -n1)"

  if [[ -z "$name" ]]; then echo "✗ $folder: missing name"; fail=1; fi
  if [[ -n "$name" && "$name" != "$folder" ]]; then echo "✗ $folder: name '$name' doesn't match folder"; fail=1; fi
  if [[ -n "$name" ]] && ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then echo "✗ $folder: invalid name format"; fail=1; fi
  if (( ${#name} > 64 )); then echo "✗ $folder: name over 64 chars"; fail=1; fi
  if [[ -z "$desc" ]]; then echo "✗ $folder: missing description"; fail=1; fi
  if (( ${#desc} > 1024 )); then echo "✗ $folder: description over 1024 chars"; fail=1; fi

  [[ $fail -eq 0 ]] && echo "✓ $folder"
  (( before )) && fail=1
done

echo "Checked $count skill(s)."
exit $fail
