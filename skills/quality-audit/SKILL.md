---
name: quality-audit
description: Audit a codebase for ways to raise its quality, then file each gap as a task in the team's own ticketing system. Detects the languages, frameworks and environment, checks for missing or weak unit, integration, UI, end-to-end, contract, accessibility and performance tests, plus linting, types, CI/CD, security, dependencies, observability, docs and configuration, and creates well-scoped tickets with evidence and acceptance criteria (GitHub Issues, GitLab, Jira, Linear, Asana, ClickUp and others, or a CSV/markdown export). Use when asked to "audit quality", "find what tests we're missing", "improve our test coverage", "check our project's health", "what should we fix to make this more robust", "create tickets for quality improvements", or to review a repo's testing and tooling setup.
---

# Quality Audit

Find the concrete, evidence-backed ways to make this codebase better, rank them, and put
them in the user's task tracker as tickets someone can pick up. Report only what you
verified, so every ticket is worth the time of the person who gets it.

`<skill-dir>` means this skill's folder. `<wf>` is a scratch folder for the run (step 0).

**Principles**

- **Evidence over opinion.** Every finding points at something you saw: a path, a count, a
  config line, command output. No "probably", no generic advice pasted into tickets.
- **Fit the project.** Recommend the tools it already uses before introducing new ones.
  A Jest project gets Jest tests, not a Vitest migration.
- **Right-sized tasks.** One ticket = one PR a single engineer can do. A vague "improve
  testing" ticket helps nobody.
- **Say what's already good.** The report should show strengths too.
- **Read-only until you file.** The audit doesn't change the code. Creating tickets is the
  only outward action, and it needs the user's yes first.
- **Don't leak.** If you find a real secret, don't copy it into a ticket or report. Say where it
  is and tell the user to rotate it.

## 0. Set up & environment

- Read environment configuration: check `<skill-dir>/references/environment.md` or `config/environment.local.yaml` (run `./scripts/setup-environment.sh --check` if in hub). If configured, tracker destination (`ticketing.tracker`), project key (`ticketing.project_key`), and connector (`ticketing.connector`) are taken directly from configuration. If unconfigured or placeholders remain, run `./scripts/setup-environment.sh --init`.
- Scope: the repo root unless the user names a path or package. For a monorepo
  (`monorepo_hint` in step 1) audit the root once for shared tooling, then each package that
  matters (ask if there are more than 5).
- Make a scratch folder: `d="$(git rev-parse --absolute-git-dir 2>/dev/null || echo .git)/quality-audit"; mkdir -p "$d"; echo "$d"`.
  Use the printed path literally as `<wf>`. Outside a git repo, use a temp dir.
- Needs `jq`. Filing GitHub issues also needs `gh auth login` (the scripts use REST only,
  because GraphQL is blocked in Claude Code cloud sessions).

Settings (environment variables, optional): `QUALITY_AUDIT_LABEL` (default `quality` or from environment config),
`QUALITY_AUDIT_MAX_ISSUES` (default `25`).

## 1. Detect the stack and the tracker

```bash
<skill-dir>/scripts/detect-stack.sh   > <wf>/stack.json
<skill-dir>/scripts/detect-tracker.sh > <wf>/tracker.json
```

`stack.json` lists languages, frameworks, which test types exist (unit, UI/component, visual,
e2e, API, contract, integration, property, mutation, load, accessibility), coverage,
linters, type checking, formatters, hooks, what CI actually runs, security tooling,
repo hygiene files, and the source directories with no tests. Treat it as a map of
where to look, not as the answer: it matches file names and manifests, so verify before filing.

`tracker.json` ranks the likely task trackers from repo evidence. If `ticketing.tracker` is set in environment config, use that as the destination; otherwise pick using `<skill-dir>/references/trackers.md` ("Choosing the destination"): check your tool
list for tracker connectors too, and ask the user once if it's ambiguous or you'd have to
guess the project/team/board. Don't create anything yet.

## 2. Audit

Read `<skill-dir>/references/checklist.md` and go through every category that applies to
what step 1 found. For each language detected, read its section of
`<skill-dir>/references/stacks.md` so recommendations name the right tools and config.

Do real checks, not just a read of `stack.json`:

- **Tests:** open a few test files and judge quality (assertions, edge cases, flakiness
  markers, mocks vs real dependencies). Map important modules (auth, payments, parsing,
  permissions, data access, the main user journeys) to the tests that cover them.
- **Run what's cheap and safe** if the environment allows it: the test command, the linter,
  the type checker, coverage. Record pass/fail and numbers. Never run deploys, migrations,
  or anything that writes to shared systems. If the tests can't run here, note that under
  "couldn't check".
- **CI:** read the workflow files. What runs on PRs? Is anything required to merge?
- **Search for risk markers:** skipped tests, `TODO`/`FIXME` counts, ignored lint rules,
  `any`/`type: ignore`, swallowed errors, committed `.env`/keys, unpinned deps.
- **Existing tickets:** check the tracker's open issues for the same gaps so you don't file
  duplicates (GitHub: `gh api -X GET repos/<o>/<r>/issues -f state=open -f labels=quality`).

Stop collecting once the picture is clear; a focused audit beats an exhaustive one.

## 3. Turn gaps into findings

Write `<wf>/findings.json` following `<skill-dir>/references/finding-format.md`. In short:

- **Group and size** so each finding is one PR-sized task. Prefer "unit tests for
  `src/billing/`" over "increase coverage".
- **Prioritise:** P1 real risk now (untested critical path, no CI test gate, committed secret,
  known-vulnerable dependency), P2 clear value, P3 nice to have. Keep P1 rare.
- **Cap** at `QUALITY_AUDIT_MAX_ISSUES`. Keep the best by value for effort. Put the rest in
  the report under "Also noticed".
- Give each a **stable id** derived from its subject, so a later audit recognises it.

Check the file, then render a ticket body to see what the team will read:

```bash
<skill-dir>/scripts/render-body.sh <wf>/findings.json --validate
<skill-dir>/scripts/render-body.sh <wf>/findings.json <some-id>
```

Write `<wf>/report.md` (format at the end of `finding-format.md`).

## 4. Confirm, then file

Show the user a short plan: tracker and project/team, number of tickets by priority, and the
list of titles with priority and effort. Include anything already open that you're skipping.
Then ask for a go-ahead before creating tickets, unless they already told you to file them
directly. Filing is visible to the whole team.

On approval, follow `<skill-dir>/references/trackers.md` for the chosen tracker:

- **GitHub Issues:** `<skill-dir>/scripts/create-github-issues.sh <wf>/findings.json` first
  (dry run, lists what would be created and what already exists), then again with
  `--create --summary`. It skips findings already filed, creates the labels, and prints one
  JSON line per finding.
- **Any other tracker with a connector** (Jira, Linear, Asana, ClickUp, GitLab, Azure
  Boards, Notion, Trello): create one item per finding with the connector's tools, using
  `render-body.sh <findings> <id>` as the description and the priority mapping in
  `trackers.md`. Search for the finding's id first to avoid duplicates.
- **No tracker or no connector:** `<skill-dir>/scripts/export-findings.sh <wf>/findings.json <dir>`
  writes `tasks.md` and an import-ready `tasks.csv`. Tell the user how to import it.

If creation fails partway, stop and report what was created and what wasn't. Don't switch
trackers or retry in a loop.

## 5. Report back

Give the user:

- the stack you detected and what already looks good
- counts by priority, plus the top findings in one line each, with ticket links
- where the tickets were filed (or where the export files are) and anything skipped as
  already tracked
- what you couldn't check and why
- **further improvements** beyond what you filed: the next tier of ideas from
  `checklist.md` that didn't make the cut or need a decision from the team (for
  example mutation testing, contract tests, SLOs, preview environments, dependency
  automation, architecture rules)

Offer to start on the first ticket (the `issue-workflow` skill can pick it up and ship it).
