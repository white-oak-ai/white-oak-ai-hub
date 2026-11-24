# Filing tasks in the user's tracker

The goal: the tasks end up where the team already works, in a form they can act on.
Never invent a tracker. If the evidence is ambiguous, ask.

## Choosing the destination

1. User named one ("file these in Linear") → use it.
2. Otherwise run `scripts/detect-tracker.sh` and look at your own tool list for connectors
   (search the deferred tools: `ToolSearch` for `linear`, `jira`/`atlassian`, `asana`,
   `clickup`, `notion`, `trello`, `github`).
3. A repo-side hint plus a matching connector (for example Jira keys in commits **and** an
   Atlassian connector) → use it, and say so in the plan you show the user.
4. Several plausible trackers, or a hint with no connector → ask once which one, and which
   project/team/board/list to use. Offer "export to files" as an option.
5. Nothing at all → GitHub/GitLab issues if the remote is on that host and the user is
   signed in; otherwise export `tasks.md` and `tasks.csv` and say how to import them.

Before creating anything, **show the plan** (count, titles, priorities, tracker, project) and
get a yes. Creating tickets is visible to the whole team and awkward to undo in bulk.

## Rules for every tracker

- **No duplicates.** Search the tracker for the finding's marker `quality-audit:<id>` and for
  the title before creating. If it exists, link to it in the report and don't file it again.
  A closed ticket means the team decided; don't reopen it, mention it in the report.
- **Same content everywhere:** use `scripts/render-body.sh <findings.json> <id>` for the
  description. It includes the hidden `quality-audit:<id>` marker. If a tracker strips HTML
  comments, keep the visible "finding `<id>`" line, which is searchable.
- **Priority mapping:** P1 → High/Urgent, P2 → Medium, P3 → Low.
- **Labels/tags:** `quality` and `quality/<category>` where the tracker supports labels.
- **Cap and order:** highest priority first, then smallest effort. Default cap 25
  (`QUALITY_AUDIT_MAX_ISSUES`); mention what was left out.
- **Group** with an epic/parent/project only if the tracker has one at hand and the user
  wants it; otherwise create one tracking issue that lists the rest.
- **Don't assign people.** Only assign the user if they ask.
- Never put secrets, tokens, or real credentials in a ticket. Describe where and what.
- Report every ticket's key/URL back to the user.

## GitHub Issues (script)

```bash
scripts/create-github-issues.sh findings.json                 # dry run, shows what would be created
scripts/create-github-issues.sh findings.json --create --summary
```

Uses REST only (GraphQL is blocked in Claude Code cloud sessions). Creates labels
(`quality`, `quality/<category>`, `priority: high|medium|low`) if they're missing, skips findings
already filed (open or closed), and with `--summary` adds a tracking issue with a checklist.
Needs `gh auth login` with permission to create issues. If `gh` isn't available but a GitHub
MCP tool is, create the issues with that tool using the same title, body and labels.

## GitLab Issues

No script, so use a GitLab connector if present. Otherwise the REST API with a token the user
already has configured (`glab auth status` or `GITLAB_TOKEN`):
`POST /projects/:id/issues` with `title`, `description`, `labels` (comma-separated). The project
id is the URL-encoded `group%2Fproject` path from `detect-tracker.sh`. Search first with
`GET /projects/:id/issues?search=quality-audit:<id>&state=all`.

## Jira (Atlassian connector or CLI)

Find the project key first (ask, or take the prefix from `detect-tracker.sh`). Create
**Task** (or **Improvement**/**Story** if the project has no Task) issues: summary = title,
description = rendered body, priority per mapping, labels `quality` and `quality-<category>`
(Jira labels can't contain spaces or slashes). Link them to an Epic called "Quality audit
<date>" if the user wants. Jira Cloud descriptions use ADF through the REST API; the
connector usually converts markdown for you. If you can only reach it through CSV import, use
`export-findings.sh` and map Title→Summary, Description→Description, Priority→Priority,
Labels→Labels.

## Linear

Needs a **team** (ask if the user belongs to several). Create issues with title, description
(markdown is native), priority (Urgent 1, High 2, Medium 3, Low 4, so P1 → High (2) unless
it's a security issue → Urgent), and labels `quality` plus a category label (create missing
labels with the connector). Optionally add them to a project "Quality audit <date>". Estimates
can use effort: S=1, M=2, L=3 if the team has estimates on.

## Asana

Needs a **project** (and optionally a section). Create tasks with name = title and notes =
description (Asana renders limited markdown, so keep headings simple), custom field Priority if
the project has one, and tags `quality`. Put acceptance criteria in as **subtasks** when the
user wants checkable steps.

## ClickUp

Needs a **list**. Create tasks with name, markdown description, priority (1 Urgent, 2 High, 3
Normal, 4 Low), tags `quality`, and the effort in time-estimate or a custom field. Acceptance
criteria can become a checklist.

## Azure Boards

Create **Task** or **User Story** work items under the project's area path, with title,
description (HTML or markdown depending on the field), priority 1–4 (P1 → 1, P2 → 2, P3 → 3),
and tag `quality`. The Azure DevOps CLI/MCP connector handles auth; REST needs a PAT the user
already has set up.

## Notion, Trello, Monday, YouTrack, Shortcut, and others

Use the connector if there is one: one card/row/page per finding with the same title and
description, a priority/status property if the board has one, and the `quality` tag. If no
connector exists, export and tell the user how to import:

```bash
scripts/export-findings.sh findings.json quality-audit-out
```

This writes `tasks.md` (readable, grouped by priority) and `tasks.csv` (columns: Title,
Description, Priority, Effort, Category, Labels, Id) which import into Jira, Linear, Asana,
ClickUp, Trello, GitLab, Azure Boards, and spreadsheets (map the columns on import).

## When creation fails

Report which tickets were created (with links) and which failed with the error. Don't retry
in a loop and don't switch trackers silently: the user decides. The same findings file can be
re-run later; the duplicate check makes it safe.
