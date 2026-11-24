#!/usr/bin/env bash
# One command: collect -> compute -> render. Prints where the report is.
#   run.sh [--demo] [--out DIR] [--targets FILE] [--narrative FILE] [collect.sh options…]
# --demo uses bundled sample data instead of reading a repo.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

out="sdlc-kpi-report" demo=0 targets=() narrative=() pass=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo) demo=1; shift ;;
    --out) out="$2"; pass+=(--out "$2"); shift 2 ;;
    --targets) targets=(--targets "$2"); shift 2 ;;
    --narrative) narrative=(--narrative "$2"); shift 2 ;;
    *) pass+=("$1"); shift ;;
  esac
done

if (( demo )); then
  mkdir -p "$out"; cp "$here/../assets/sample-raw.json" "$out/raw.json"
else
  "$here/collect.sh" "${pass[@]+"${pass[@]}"}" --out "$out"
fi
"$here/compute.sh" "$out" "${targets[@]+"${targets[@]}"}"
"$here/render-report.sh" "$out" "${narrative[@]+"${narrative[@]}"}"
echo "Report: $out/sdlc-kpi-report.html (summary: $out/sdlc-kpi-report.md)" >&2
