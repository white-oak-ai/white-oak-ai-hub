#!/usr/bin/env bash
# Zip one skill (or all of them) for upload to Claude.
# Usage: ./scripts/package-skill.sh <skill-name>   -> dist/<skill-name>.zip
#        ./scripts/package-skill.sh --all          -> one zip per skill in dist/
#
# Claude expects the skill folder itself at the top of the zip
# (my-skill.zip -> my-skill/SKILL.md), not SKILL.md at the root.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/dist"

package() {
  local name="$1"
  [[ -f "$root/skills/$name/SKILL.md" ]] || { echo "Error: skills/$name/SKILL.md not found." >&2; return 1; }
  rm -f "$root/dist/$name.zip"
  (cd "$root/skills" && zip -qr "$root/dist/$name.zip" "$name" -x '*/.gitkeep' '*/.DS_Store')
  echo "Built dist/$name.zip"
}

case "${1:-}" in
  "") echo "Usage: $0 <skill-name> | --all" >&2; exit 1 ;;
  --all) for d in "$root"/skills/*/; do package "$(basename "$d")"; done ;;
  *) package "$1" ;;
esac
