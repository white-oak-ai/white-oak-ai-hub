# The five KPIs

Based on the DORA research ("Four Keys") plus review wait, the cheapest delay to fix.
Defaults live in `assets/targets.json`; a repo can override them in `.sdlc-kpis.json`.

| KPI | Measures | Better | On track | Watch | Act now |
|---|---|---|---|---|---|
| Deployment frequency | ships per week | higher | 5+ | 1–5 | under 1 |
| Lead time for changes | median first commit → merge | lower | ≤ 24 h | ≤ 7 days | longer |
| Change failure rate | % of merged PRs that are reverts/hotfixes | lower | ≤ 15% | ≤ 30% | higher |
| Time to restore | median bug/incident open → closed | lower | ≤ 24 h | ≤ 7 days | longer |
| Review wait time | median PR opened → first human review | lower | ≤ 4 h | ≤ 24 h | longer |

## Data sources and limits

- **GitHub mode** (`gh` signed in): PRs, reviews, deployments, releases, issues via REST.
  Deploys come from production deployments, else releases, else merges to the default
  branch (flagged in the report as a stand-in).
- **Git mode** (fallback): merges, reverts and tags from the local clone. Covers deployment
  frequency, lead time (merge commits only) and change failure rate. Time to restore and
  review wait show "No data".
- Review wait starts at PR creation, so draft time inflates it slightly. Bots do not count as reviewers.
- Bugs are issues whose labels match `bug|incident|outage|regression|sev N|p0|p1|critical|hotfix`
  (`--bug-regex` to change). Revert/hotfix PRs: title starts with "Revert" or label matches revert|rollback|hotfix.
- Fewer than 5 data points (10 PRs for failure rate) is flagged "low sample".
- Teams that batch releases or deploy from another system should pass `--env-regex` or
  publish Releases so frequency reflects reality.

## Reading the numbers

Look at trend and drivers before the status colour: a "Watch" that is improving matters
less than a "Watch" that is getting worse. Fix one KPI at a time, starting with the first
item in "Do this next". Do not use these to rank individual people; they describe the
system.
