#!/usr/bin/env bash
# Render <out-dir>/kpis.json into a self-contained HTML report and a Markdown summary.
#   render-report.sh <out-dir> [--narrative FILE]
# Writes <out-dir>/sdlc-kpi-report.html and <out-dir>/sdlc-kpi-report.md.
# --narrative: optional JSON with any of {headline, summary_text, top_actions:[{kpi,status,action}]}
# that replaces the generated text (use it to add context only a person or Claude knows).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$here/_lib.sh"

out="${1:-}"; shift || true
[[ -n "$out" && -f "$out/kpis.json" ]] || die "usage: render-report.sh <out-dir> [--narrative FILE]  (needs <out-dir>/kpis.json from compute.sh)"
narrative=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --narrative) narrative="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

data="$(mktemp)"; trap 'rm -f "$data"' EXIT
if [[ -n "$narrative" ]]; then
  jq -e . "$narrative" >/dev/null || die "narrative file is not valid JSON: $narrative"
  jq -s '.[0] * (.[1] | with_entries(select(.key | IN("headline","summary_text","top_actions"))))' "$out/kpis.json" "$narrative" > "$data"
else
  cp "$out/kpis.json" "$data"
fi

# HTML: embed the data. "</" is escaped so the JSON can never close the script tag early.
json="$(jq -c . "$data" | sed 's#</#<\\/#g')"
# (ENVIRON, not awk -v, because -v would interpret backslash escapes inside the JSON.)
KPI_JSON="$json" awk '{
  i = index($0, "__KPI_DATA__")
  if (i) { print substr($0, 1, i - 1) ENVIRON["KPI_JSON"] substr($0, i + 12) } else print
}' "$here/../assets/report-template.html" > "$out/sdlc-kpi-report.html"

# Markdown: a table plus the actions, short enough to paste into Slack, a PR or a wiki.
jq -r '
  def icon: if . == "green" then "🟢" elif . == "amber" then "🟡" elif . == "red" then "🔴" else "⚪" end;
  def stext: if . == "green" then "On track" elif . == "amber" then "Watch" elif . == "red" then "Act now" else "No data" end;
  def arrow: if .dir == "better" then "better" elif .dir == "worse" then "worse" elif .dir == "flat" then "about the same" else "–" end;
  "# SDLC KPI report: \(.repo)\n",
  "_\(.period.start) to \(.period.end) (last \(.days) days vs the \(.days) before)_\n",
  "**\(.headline)**\n",
  (if .summary_text then "\(.summary_text)\n" else empty end),
  "| KPI | Now | Status | vs previous |",
  "|---|---|---|---|",
  (.kpis[] | "| \(.name) | **\(.display)** | \(.status | icon) \(.status | stext) | \(.trend | arrow) (was \(.prev_display)) |"),
  "",
  (if (.top_actions | length) > 0 then "## Do this next\n" else empty end),
  (.top_actions | to_entries[] | "\(.key + 1). **\(.value.kpi):** \(.value.action)"),
  "",
  "## Details",
  (.kpis[] | "\n### \(.name): \(.display) \(.status | icon)\n_\(.meaning)_\n\n" +
     (if (.drivers | length) > 0 then "What is driving it:\n" + ([.drivers[] | "- " + (if .url then "[\(.label)](\(.url))" else .label end) + (if .detail then " — \(.detail)" else "" end)] | join("\n")) + "\n\n" else "" end) +
     "What to do:\n" + ([.actions[] | "- [ ] \(.)"] | join("\n"))),
  (if (.notes | length) > 0 then "\n---\n" + ([.notes[] | "_Note: \(.)_"] | join("\n")) else empty end)
' "$data" > "$out/sdlc-kpi-report.md"

echo "wrote $out/sdlc-kpi-report.html" >&2
echo "wrote $out/sdlc-kpi-report.md" >&2
