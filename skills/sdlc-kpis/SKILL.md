---
name: sdlc-kpis
description: Track five software-delivery KPIs (deployment frequency, lead time for changes, change failure rate, time to restore, PR review wait time) from a repo's GitHub or git history and produce a clear HTML and Markdown report with traffic-light status, trend vs the previous period, the specific PRs and bugs driving each number, and concrete next actions. Use when asked for "SDLC metrics", "engineering KPIs", "DORA metrics", "delivery health", "how fast are we shipping", "team velocity report", "lead time", "change failure rate", "review turnaround", or a periodic engineering health report.
---

# SDLC KPIs

Measure how well the team delivers software with five numbers anyone can read, and say
what to do about the ones that are off. Every number comes from real PR, deployment and
issue data, never estimates.

`<skill-dir>` means this skill's folder. Definitions and targets: `references/kpis.md`.

The five KPIs: **deployment frequency**, **lead time for changes**, **change failure
rate**, **time to restore**, **review wait time**. Each gets a status (on track / watch /
act now), a trend against the previous period, the items driving it, and next steps.

## Steps

1. **Pick scope & check environment.** Read `config/environment.local.yaml` or `<skill-dir>/references/environment.md` for target repository (`default_repo`) and branch (`default_branch`). Defaults to the repo in the current directory, last 30 days unless the user says
   otherwise. Needs `jq`. For full data, `gh auth login` (REST only; no GraphQL). Without
   GitHub access the skill falls back to local git and says which KPIs it can't measure.
2. **Run it:**
   ```bash
   <skill-dir>/scripts/run.sh --days 30 --out sdlc-kpi-report
   ```
   Options: `--repo owner/repo`, `--branch main`, `--targets FILE`, `--max-prs 100`,
   `--env-regex`, `--bug-regex`, `--mode git`. `--demo` renders sample data to preview the
   report. Teams can keep custom thresholds in `.sdlc-kpis.json` at the repo root
   (copy `assets/targets.json`).
3. **Read `kpis.json` and sanity-check it.** Look at `notes` (stand-in data, low samples,
   skipped PRs). If deploy frequency uses merges as a stand-in, or a KPI is "No data",
   tell the user how to fix it (publish Releases, label bugs, sign in to gh). Don't
   present a low-sample number as a verdict.
4. **Add judgement (optional but valuable).** If you know context the script can't (a
   release freeze, an incident week, a holiday), write `<out>/narrative.json` with
   `headline`, `summary_text` (2 sentences max) and/or `top_actions` (`[{kpi, status,
   action}]`, at most 3, specific and doable this week), then re-render:
   `<skill-dir>/scripts/render-report.sh <out> --narrative <out>/narrative.json`.
   Never invent numbers; only reword or prioritise what the data shows.
5. **Deliver.** Open or share `<out>/sdlc-kpi-report.html` (self-contained, works offline,
   prints cleanly; publish it with an Artifact tool if one is available). Reply with the
   headline, the five-row table from `sdlc-kpi-report.md`, and the top 3 actions. Offer to
   file the actions as tickets (`quality-audit` / `issue-workflow` skills) and to re-run
   next month to show progress.

## Rules

- Report system health, never individual performance. Don't rank people.
- Keep the answer short: headline, table, top actions. The details are in the report.
- Say what you couldn't measure and why.
- The output folder is generated; suggest adding it to `.gitignore` unless the team wants
  to commit snapshots.
