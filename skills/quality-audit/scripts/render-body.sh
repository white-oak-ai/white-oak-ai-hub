#!/usr/bin/env bash
# Print the markdown ticket body for one finding (or validate the whole file).
# Use this to fill a ticket in any tracker, e.g. through a Linear/Jira/Asana connector.
#
# Usage:
#   render-body.sh <findings.json> <finding-id>   # body for one finding
#   render-body.sh <findings.json> --validate     # check the file, print nothing else
set -euo pipefail
# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

file="${1:-}"; id="${2:-}"
[[ -n "$file" && -n "$id" ]] || die "usage: $0 <findings.json> <finding-id | --validate>"

validate_findings "$file" || exit 1
if [[ "$id" == "--validate" ]]; then
  echo "✓ $(jq length "$file") finding(s) valid"
  exit 0
fi

finding="$(jq -c --arg id "$id" '.[] | select(.id == $id)' "$file")"
[[ -n "$finding" ]] || die "no finding with id '$id' in $file"
render_body <<<"$finding"
