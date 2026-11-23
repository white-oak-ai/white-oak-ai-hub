---
name: issue-workflow
description: Pick up a GitHub issue end to end. Ranks open issues by value versus risk and picks the best one (or takes the issue you name), checks it's ready to work on, marks it in progress (assign + label + comment), implements and tests the fix, runs the pr-workflow skill to open, review and merge the PR, then closes the issue out. Use when asked to pick up, grab, work on or knock out an issue, "what should I work on next", "do the next issue", "work issue #N", or to pick the highest-value, lowest-risk issue.
---

# Issue Workflow

Find the open issue that gives the most value for the least risk, make sure it's
actually ready to work on, claim it, do the work, ship it through `pr-workflow`, and
close it. Every state change is visible on the issue, so the team always knows who has
it and what happened.

`<skill-dir>` below means this skill's folder.

**The issue's state must always tell the truth.** Claim it only once it passes the
readiness check. If you stop for any reason before the PR merges, either leave a comment
saying where things stand (PR open) or release the claim (no PR). Never leave an issue
labeled in progress with nobody working on it.

## 0. Check prerequisites

- `gh auth status` succeeds, the folder is a git repo with a GitHub remote, and `jq` is
  installed. If `gh` isn't signed in, stop and tell the user to run `gh auth login`.
- Get `<owner>/<repo>` from `git remote get-url origin` and the default branch from
  `gh api repos/<owner>/<repo> --jq .default_branch`.
- Use `gh api` (REST) for everything, never `gh issue ...`, `gh pr ...` or `gh repo view`:
  those use GraphQL, which is blocked in Claude Code cloud sessions. The scripts in
  `scripts/` already use REST.
- The `pr-workflow` skill must be available (step 6). Check now so you don't find out
  after doing the work: it's either in your skills list or at `<skill-dir>/../pr-workflow/SKILL.md`.
  If it's missing, stop and tell the user to install it.
- `git status` is clean. If there are uncommitted changes, stop and ask: they aren't part
  of this issue.
- Make a scratch folder for notes: `d="$(git rev-parse --absolute-git-dir)/issue-workflow"; mkdir -p "$d"; echo "$d"`.
  Use the printed path, called `<wf>` below, literally in later commands.

Settings (environment variables, all optional):
- `ISSUE_WORKFLOW_LABEL`: the in-progress label. Default `in-progress`; created if missing.
- `ISSUE_WORKFLOW_SKIP_LABELS`: comma-separated labels that are never picked. Default
  `blocked, on-hold, wontfix, duplicate, invalid, question, needs-design,
  needs-discussion, needs-info, needs-triage, epic, discussion`.

## 1. Find candidates

**If the user named an issue** ("work #42"), skip ranking: go to step 3 with that issue.
Still run the readiness check, and tell the user plainly if it fails instead of
substituting a different issue.

Otherwise:

```bash
<skill-dir>/scripts/list-candidates.sh --limit 40
```

This lists open issues that aren't PRs, aren't assigned to someone else, aren't already
in progress, and don't have a skip label, with the signals used for scoring (labels,
upvotes, comment count, body length, whether it has acceptance criteria, issues it
depends on). If it returns `[]`, stop and report that there's nothing to pick up (run it
with `--all` to see what was excluded and why).

Issues already assigned to you with the in-progress label are included: they may be
work you left unfinished. Mention them to the user and prefer finishing one over
starting something new, unless it has an open PR (then it's waiting on review, not you).

## 2. Rank by value versus risk

Score candidates with the rubric in `<skill-dir>/references/scoring.md` (read it now):
value 1–5, risk 1–5, rank by value ÷ risk.

1. **First pass, from the list alone:** drop hard exclusions (rubric), then score value
   and give a rough risk from the title, labels and body. Keep the top 5.
2. **Second pass, with the code:** for each of the top 5, run
   `<skill-dir>/scripts/issue-context.sh <n>` and read the code the issue points at
   (search for the names it mentions). Re-score risk from what you find: how many files,
   whether tests cover it, whether it touches a sensitive area. Do this yourself; don't
   change any code yet.
3. Write the ranked table (number, title, value, risk, score, one-line reason) to
   `<wf>/ranking.md` and show it to the user in a short progress message. Then carry on
   with the top pick; the user can interrupt to redirect.

## 3. Readiness check

Run `<skill-dir>/scripts/issue-context.sh <n>` (if you haven't) and confirm **every**
item. Write the result to `<wf>/readiness.md`.

- [ ] **Still available:** open, unassigned or assigned to you, no in-progress label
  from someone else, `open_linked_prs` is empty, and no recent comment from someone else
  saying they're on it.
- [ ] **Unblocked:** every entry in `dependencies` is `closed`.
- [ ] **Clear outcome:** you can write down, in a sentence or two, what "done" means and
  how you'll show it (a test that fails now and passes after, or a concrete check). If
  the issue gives acceptance criteria, use them. Don't invent requirements the issue
  doesn't state; an ambiguous issue fails this check.
- [ ] **Located:** you've found the code to change and it's in this repo.
- [ ] **Buildable here:** the project's tests (and linter, if any) run in this
  environment. Run them now on the default branch. If they already fail, note which; you
  must not make it worse, and you must be able to tell your changes apart.
- [ ] **Nothing missing:** no secrets, services, accounts, hardware or access you don't
  have. No pending decision only a maintainer can make.
- [ ] **Sized right:** you expect a focused change. If it really needs splitting, it
  isn't ready.

**If any item fails**, don't claim the issue. Note the reason, then try the next issue
in the ranking. Stop after **3** rejected issues and report what blocked each one. Don't
comment on rejected issues unless the user asks; you may suggest the comment (for
example, the question that would unblock it) in the report.

## 4. Claim it

Write a short comment to `<wf>/claim.md`: that you're picking it up, the planned
approach in 2–4 bullets, and how you'll verify it. Then:

```bash
<skill-dir>/scripts/claim-issue.sh <n> --comment-file <wf>/claim.md
```

It re-checks availability right before claiming (someone may have taken it while you
were analyzing), creates the label if needed, assigns you, adds the label and posts the
comment.

- Exit 0: claimed. If it warns that it couldn't assign you, carry on; the label marks it.
- Exit 2: someone else got there first. Go back to step 3 with the next issue.
- Exit 1: an API error. Stop and report it.

Create a branch from the up-to-date default branch: `git fetch origin <default>` then
`git switch -c <type>/<n>-<short-slug> origin/<default>`, with `<type>` one of `fix`,
`feat`, `docs`, `chore`, `refactor`. If the session tells you which branch to use, use
that one instead.

## 5. Do the work

- **Test first where you can:** write or extend a test that captures the issue and
  watch it fail, then fix the code until it passes.
- **Stay in scope.** Change only what the issue needs. Note unrelated problems you spot
  for the report instead of fixing them here; they raise the risk of this change.
- Follow the repo's conventions (CLAUDE.md, CONTRIBUTING, existing style).
- Run the full test suite and linter. Everything that passed in step 3 must still pass.
- Commit with a clear message that references the issue, for example
  `Fix crash on empty config (#42)`.
- Check the result against the "done" definition from step 3, item by item.

**If you can't finish** (the fix turns out much bigger or riskier than assessed, the
behavior is genuinely ambiguous, or you hit a blocker you can't clear), stop. Don't open
a half-done PR. Release the claim with what you learned:

```bash
<skill-dir>/scripts/release-issue.sh <n> "Releasing this: <what you found and what's needed to move it forward>."
```

Then report to the user. Don't move on to another issue in the same run.

## 6. Ship it with pr-workflow

Invoke the `pr-workflow` skill (if the Skill tool doesn't list it, read
`<skill-dir>/../pr-workflow/SKILL.md` and follow it). Tell it:

- The branch is ready and tested, and the PR is for issue #<n>.
- The PR body must start its Summary with `Closes #<n>` and restate the "done"
  definition from step 3, so the reviewer can judge the change against the issue.

Follow `pr-workflow` through to its end: review rounds, fixes, CI and merge. Its rules
decide whether the PR merges; don't override them to close the issue sooner.

## 7. Close it out

Write a 2–4 line summary of what changed to `<wf>/summary.md`.

**If the PR merged:**

```bash
<skill-dir>/scripts/close-issue.sh <n> <pr> --summary-file <wf>/summary.md
```

It refuses unless the PR is merged, then comments with the PR and merge commit, removes
the in-progress label, and closes the issue as completed if the merge didn't already.

**If the PR didn't merge** (left open by `pr-workflow`: self-review only, open
pushed-back threads, failing CI, round limit, branch protection, auto-merge off), don't
close the issue. Leave it assigned and labeled, since the work is in flight, and post a
status comment:

```bash
gh api -X POST repos/<owner>/<repo>/issues/<n>/comments -f body="PR #<pr> is open and ready for a human: <what's needed to merge it>."
```

## 8. Report back

Give the user:

- which issue you picked and why (value, risk, one-line reason), plus the runners-up
- any issues rejected at the readiness check and what blocked each
- what you changed and how you verified it
- the PR link and the `pr-workflow` outcome (merged or open, reviewer, rounds, CI)
- the issue's final state: closed, or open and still in progress, with what's needed
- anything you noticed but left out of scope
