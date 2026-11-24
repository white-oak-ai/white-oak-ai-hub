#!/usr/bin/env bash
# Turn raw.json into kpis.json: the five KPIs with status, trend, drivers and actions.
#   compute.sh <out-dir> [--targets FILE]
# Targets: --targets FILE, else ./.sdlc-kpis.json, else assets/targets.json.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$here/_lib.sh"

out="${1:-}"; shift || true
[[ -n "$out" && -f "$out/raw.json" ]] || die "usage: compute.sh <out-dir> [--targets FILE]  (needs <out-dir>/raw.json from collect.sh)"
targets=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets) targets="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n "$targets" ]] || { [[ -f .sdlc-kpis.json ]] && targets=.sdlc-kpis.json || targets="$here/../assets/targets.json"; }
jq -e . "$targets" >/dev/null || die "targets file is not valid JSON: $targets"
# Missing keys in a custom file fall back to the defaults.
merged="$(jq -s '.[0] * .[1]' "$here/../assets/targets.json" "$targets")"

jq --argjson targets "$merged" --argjson now "$(jq .now "$out/raw.json")" -f "$here/kpis.jq" "$out/raw.json" > "$out/kpis.json"
echo "wrote $out/kpis.json" >&2
jq -r '.headline, (.kpis[] | "  \(.status | ascii_upcase | .[0:5])\t\(.name)\t\(.display)\t(\(.trend.dir))")' "$out/kpis.json" >&2
