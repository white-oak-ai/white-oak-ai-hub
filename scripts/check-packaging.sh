#!/usr/bin/env bash
# Build every skill's zip and check its layout: the Claude apps only accept
# <name>.zip -> <name>/SKILL.md, and ignore a zip with SKILL.md at its root.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/package-skill.sh" --all >/dev/null || { echo "✗ package-skill.sh --all failed"; exit 1; }

fail=0
for dir in "$root"/skills/*/; do
  name="$(basename "$dir")"
  zip="$root/dist/$name.zip"
  if [[ ! -f "$zip" ]]; then
    echo "✗ $name: dist/$name.zip wasn't built"; fail=1; continue
  fi
  entries="$(unzip -Z1 "$zip")"
  if ! grep -qx "$name/SKILL.md" <<<"$entries"; then
    echo "✗ $name: zip has no $name/SKILL.md"; fail=1; continue
  fi
  if grep -qx "SKILL.md" <<<"$entries"; then
    echo "✗ $name: zip has SKILL.md at its root"; fail=1; continue
  fi
  if grep -v "^$name/" <<<"$entries" | grep -q .; then
    echo "✗ $name: zip has files outside $name/"; fail=1; continue
  fi
  echo "✓ $name"
done
exit $fail
