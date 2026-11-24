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

  # Include setup-environment.sh in standalone package if not already present
  local cleanup_setup=0
  if [[ ! -f "$root/skills/$name/scripts/setup-environment.sh" && -f "$root/scripts/setup-environment.sh" ]]; then
    mkdir -p "$root/skills/$name/scripts"
    cp "$root/scripts/setup-environment.sh" "$root/skills/$name/scripts/setup-environment.sh"
    chmod 755 "$root/skills/$name/scripts/setup-environment.sh"
    cleanup_setup=1
  fi

  (cd "$root/skills" && zip -qr "$root/dist/$name.zip" "$name" -x '*/.gitkeep' '*/.DS_Store' '*/*.local.*')

  if [[ $cleanup_setup -eq 1 ]]; then
    rm -f "$root/skills/$name/scripts/setup-environment.sh"
  fi

  echo "Built dist/$name.zip"
}

case "${1:-}" in
  "") echo "Usage: $0 <skill-name> | --all" >&2; exit 1 ;;
  --all) for d in "$root"/skills/*/; do package "$(basename "$d")"; done ;;
  *) package "$1" ;;
esac
