#!/usr/bin/env bash
# Shared helpers for pr-workflow scripts. Source it; don't run it.
#
# These avoid `gh repo view` and `gh pr view`, which use GitHub GraphQL. GraphQL is
# blocked in Claude Code cloud sessions, so every lookup here uses git or REST.

# owner/repo from the origin remote, falling back to gh.
repo_slug() {
  local url slug
  url="$(git remote get-url origin 2>/dev/null || true)"
  # Last two path segments: git@host:o/r.git, https://host/o/r, http://proxy/git/o/r ...
  slug="$(sed -E 's#\.git/?$##; s#/$##; s#.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")"
  if [[ "$slug" =~ ^[^/]+/[^/]+$ ]]; then
    echo "$slug"
  else
    gh repo view --json nameWithOwner -q .nameWithOwner
  fi
}

# Head commit SHA of a PR, over REST.
pr_head_sha() {
  gh api "repos/$(repo_slug)/pulls/$1" --jq .head.sha
}
