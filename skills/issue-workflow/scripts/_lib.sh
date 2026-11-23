#!/usr/bin/env bash
# Shared helpers for issue-workflow scripts. Source it; don't run it.
#
# Everything here uses git or GitHub REST. `gh issue ...`, `gh repo view` and friends use
# GraphQL, which is blocked in Claude Code cloud sessions.

# Label that marks an issue as being worked on. Override with ISSUE_WORKFLOW_LABEL.
IW_LABEL="${ISSUE_WORKFLOW_LABEL:-in-progress}"

# Issues with any of these labels are never picked. Override with a comma-separated
# ISSUE_WORKFLOW_SKIP_LABELS. Matching ignores case.
IW_DEFAULT_SKIP_LABELS="blocked,on-hold,wontfix,won't fix,duplicate,invalid,question,needs-design,needs-discussion,needs-info,needs-triage,epic,discussion"
IW_SKIP_LABELS="${ISSUE_WORKFLOW_SKIP_LABELS:-$IW_DEFAULT_SKIP_LABELS}"

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

# Login of the signed-in GitHub user.
me_login() {
  gh api user --jq .login
}

# URL-encode one path segment (label names can contain spaces and slashes).
uri_encode() {
  jq -rn --arg s "$1" '$s|@uri'
}

# Open PRs that reference issue $2 in repo $1, as a JSON array of {number,title,url}.
open_linked_prs() {
  gh api "repos/$1/issues/$2/timeline?per_page=100" --paginate \
    --jq '.[] | select(.event == "cross-referenced" and .source.issue.pull_request != null
                       and .source.issue.state == "open")
              | {number: .source.issue.number, title: .source.issue.title, url: .source.issue.html_url}' \
    | jq -s 'unique_by(.number)'
}
