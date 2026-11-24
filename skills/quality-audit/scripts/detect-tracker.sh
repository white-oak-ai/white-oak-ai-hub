#!/usr/bin/env bash
# Work out where this project tracks its tasks, so audit findings can be filed there.
# Prints one JSON object with ranked candidates. Read-only; makes no network calls.
#
# Usage: detect-tracker.sh [repo-dir]
#
# This only sees repo-side evidence (git remote, config files, commit messages, env vars).
# The caller must also check which tracker connectors/MCP tools its session has, and ask
# the user when the evidence is ambiguous. See references/trackers.md.
set -euo pipefail

cd "${1:-.}"
command -v jq >/dev/null || { echo "detect-tracker.sh needs jq" >&2; exit 1; }

url="$(git remote get-url origin 2>/dev/null || true)"
host=""
slug=""
if [[ -n "$url" ]]; then
  host="$(sed -E 's#^[a-z+]+://([^@/]+@)?([^/:]+).*#\2#; t; s#^[^@]+@([^:]+):.*#\1#' <<<"$url")"
  slug="$(sed -E 's#\.git/?$##; s#/$##; s#.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")"
fi

cands='[]'
add() { # add <tracker> <confidence 1-3> <reason> [extra-json]
  cands="$(jq -c --arg t "$1" --argjson c "$2" --arg r "$3" --argjson x "${4:-{\}}" \
    '. + [({tracker:$t, confidence:$c, reason:$r} + $x)]' <<<"$cands")"
}

# Code host's own issue tracker.
case "$host" in
  github.com|*github*) add github-issues 2 "git remote is on GitHub ($slug)" "$(jq -nc --arg s "$slug" '{repo:$s}')" ;;
  gitlab.com|*gitlab*) add gitlab-issues 2 "git remote is on GitLab ($slug)" "$(jq -nc --arg s "$slug" '{project:$s}')" ;;
  bitbucket.org)       add bitbucket-issues 1 "git remote is on Bitbucket ($slug)" ;;
  dev.azure.com|*visualstudio.com) add azure-boards 2 "git remote is on Azure DevOps" ;;
  "") ;;
  *) # Local proxies (Claude Code cloud) use hosts like 127.0.0.1; fall back to the path.
     [[ -n "$slug" ]] && add github-issues 1 "git remote host '$host' is unrecognised; path looks like owner/repo ($slug), which may be GitHub" "$(jq -nc --arg s "$slug" '{repo:$s}')" ;;
esac

# Issue-key style references in recent commits / branch names (PROJ-123) mean Jira or Linear.
keys="$(git log -n 200 --format='%s %b' 2>/dev/null | grep -Eo '\b[A-Z][A-Z0-9]{1,9}-[0-9]{1,6}\b' | grep -Ev '^(UTF|ISO|SHA|CVE|RFC|HTTP|TLS|SSL|PEP|ES|MD|X|UTC|GPT)-' | sort | uniq -c | sort -rn | head -3 || true)"
if [[ -n "$keys" ]]; then
  top="$(awk 'NR==1{print $2}' <<<"$keys")"
  prefix="${top%-*}"
  add jira-or-linear 2 "commit messages reference issue keys like $top" "$(jq -nc --arg p "$prefix" '{key_prefix:$p}')"
fi

# Config files that give the tracker away.
[[ -d .linear || -f linear.toml ]]                        && add linear 3 "linear config in repo"
[[ -f .atlassian || -f jira.yml || -f .jira.d/config.yml ]] && add jira 3 "jira config in repo"
[[ -f .clickup.json ]]                                    && add clickup 3 "clickup config in repo"
[[ -f .asana ]]                                           && add asana 3 "asana config in repo"
grep -rEqi 'atlassian\.net|jira' README.md CONTRIBUTING.md .github 2>/dev/null \
  && add jira 2 "docs or workflows mention Jira / atlassian.net"
grep -rEqi 'linear\.app' README.md CONTRIBUTING.md .github 2>/dev/null \
  && add linear 2 "docs or workflows mention linear.app"
grep -rEqi 'app\.asana\.com' README.md CONTRIBUTING.md .github 2>/dev/null \
  && add asana 2 "docs or workflows mention Asana"
grep -rEqi 'app\.clickup\.com' README.md CONTRIBUTING.md .github 2>/dev/null \
  && add clickup 2 "docs or workflows mention ClickUp"
grep -rEqi 'notion\.(so|site)' README.md CONTRIBUTING.md 2>/dev/null \
  && add notion 1 "docs mention Notion"
grep -rEqi 'trello\.com' README.md CONTRIBUTING.md 2>/dev/null \
  && add trello 1 "docs mention Trello"
grep -rEqi 'youtrack|shortcut\.com|app\.shortcut|monday\.com|height\.app' README.md CONTRIBUTING.md 2>/dev/null \
  && add other 1 "docs mention another tracker (YouTrack/Shortcut/monday/Height)"

# Environment hints (names only; never print values).
[[ -n "${LINEAR_API_KEY:-}" ]]                 && add linear 2 "LINEAR_API_KEY is set"
[[ -n "${JIRA_API_TOKEN:-}${JIRA_URL:-}${ATLASSIAN_API_TOKEN:-}" ]] && add jira 2 "Jira environment variables are set"
[[ -n "${ASANA_ACCESS_TOKEN:-}" ]]             && add asana 2 "ASANA_ACCESS_TOKEN is set"
[[ -n "${CLICKUP_API_TOKEN:-}" ]]              && add clickup 2 "CLICKUP_API_TOKEN is set"

# Is GitHub issues actually switched on / used? Hint from templates.
if [[ -d .github/ISSUE_TEMPLATE ]]; then
  if [[ -f .github/ISSUE_TEMPLATE/config.yml ]] && grep -Eq 'blank_issues_enabled:[[:space:]]*false' .github/ISSUE_TEMPLATE/config.yml; then
    add github-issues 1 "issue templates exist (blank issues disabled; templates may be required)"
  else
    add github-issues 2 "issue templates exist in .github/ISSUE_TEMPLATE"
  fi
fi

# Merge duplicates: keep the highest confidence per tracker, joining reasons; sort best first.
jq -n --argjson c "$cands" --arg remote_host "$host" --arg slug "$slug" '
  ($c | group_by(.tracker)
      | map({tracker: .[0].tracker,
             confidence: (map(.confidence) | max),
             reasons: (map(.reason) | unique)}
            + (reduce .[] as $x ({}; . + ($x | del(.tracker, .confidence, .reason))))))
  | sort_by(-.confidence) as $ranked
  | {
      remote_host: $remote_host,
      repo_slug: $slug,
      candidates: $ranked,
      best: ($ranked[0].tracker // null),
      ambiguous: (($ranked | length) > 1 and ($ranked[0].confidence == ($ranked[1].confidence // -1))),
      note: "Repo-side evidence only. Also check which tracker connectors your session has, and ask the user if unsure."
    }'
