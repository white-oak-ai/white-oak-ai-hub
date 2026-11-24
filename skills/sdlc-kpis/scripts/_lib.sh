#!/usr/bin/env bash
# Shared helpers for sdlc-kpis scripts. Source it; don't run it.
#
# Everything here uses git or GitHub REST. `gh issue ...` and `gh repo view` use GraphQL,
# which is blocked in Claude Code cloud sessions.

die() { echo "error: $*" >&2; exit 1; }
note() { echo "• $*" >&2; }

# owner/repo from the origin remote, empty if there isn't one.
repo_slug() {
  local url slug
  url="$(git remote get-url origin 2>/dev/null || true)"
  slug="$(sed -E 's#\.git/?$##; s#/$##; s#.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")"
  [[ "$slug" =~ ^[^/]+/[^/]+$ ]] && echo "$slug" || true
}

# ISO-8601 UTC timestamp N days before now. Works with GNU and BSD date.
iso_days_ago() {
  date -u -d "-$1 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ
}

# True when the GitHub REST API answers for this repo (gh installed, signed in, network ok).
github_ok() {
  command -v gh >/dev/null 2>&1 && [[ -n "${1:-}" ]] \
    && gh api "repos/$1" --jq .full_name >/dev/null 2>&1
}
