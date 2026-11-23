#!/usr/bin/env bash
# Scaffold a new skill from templates/skill-template.
# Usage: ./scripts/new-skill.sh my-skill-name
set -euo pipefail

name="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "$name" ]]; then
  echo "Usage: $0 <skill-name>" >&2
  exit 1
fi
if ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || (( ${#name} > 64 )); then
  echo "Error: name must be lowercase letters/numbers/hyphens, max 64 chars." >&2
  exit 1
fi

dest="$root/skills/$name"
if [[ -e "$dest" ]]; then
  echo "Error: $dest already exists." >&2
  exit 1
fi

mkdir -p "$dest"/{scripts,references,assets}
touch "$dest"/{scripts,references,assets}/.gitkeep

title="$(echo "$name" | sed -E 's/-/ /g; s/\b(.)/\u\1/g')"
sed -e "s/SKILL_NAME/$name/" -e "s/SKILL_TITLE/$title/" \
  "$root/templates/skill-template/SKILL.md" > "$dest/SKILL.md"

echo "Created skills/$name — edit skills/$name/SKILL.md"
