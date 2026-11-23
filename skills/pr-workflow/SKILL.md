---
name: pr-workflow
description: Open a GitHub pull request for the current work, have an independent senior-engineer reviewer (Claude, Codex, Gemini or Copilot; chosen once and remembered, with automatic fallback) review it, fix the comments, re-review until approved (max 3 rounds), then merge once CI passes. Use when asked to open, create, raise or ship a PR, to review and fix a PR, "PR this", or to change which AI reviews PRs.
---

# PR Workflow

Open a PR, get it reviewed by a separate senior-engineer agent, fix what it finds,
repeat until it's approved, then merge it once every comment is addressed and CI passes. The review and every fix are recorded on the PR, so a human
can see what was raised and how it was handled.

**Why a separate agent reviews:** the session that wrote the code is a poor judge of it.
The reviewer starts fresh, sees only the diff, and can't edit anything. This session
does the fixes, and the reviewer checks them on the next round.

`<skill-dir>` below means this skill's folder.

## 0. Check prerequisites

- `gh auth status` succeeds, the folder is a git repo with a GitHub remote, and `jq` is
  installed. If `gh` isn't signed in, stop and tell the user to run `gh auth login`.
- Get `<owner>/<repo>` from `git remote get-url origin`, then find the default branch:
  `gh api repos/<owner>/<repo> --jq .default_branch`.
- Prefer `gh api` (REST) over `gh pr ...` and `gh repo view`. Those commands use GitHub
  GraphQL, which is blocked in Claude Code cloud sessions. The scripts in `scripts/`
  already use REST.
- Find the review folder once: `d="$(git rev-parse --absolute-git-dir)/pr-workflow"; mkdir -p "$d"; echo "$d"`.
  Use that printed absolute path, called `<wf>` below, **literally** in every later
  command, because shell variables don't carry over between tool calls. It sits inside the
  git dir, so the files are never committed, and it's correct in worktrees too.

## 0b. Pick the reviewer (ask once, then remember)

```bash
<skill-dir>/scripts/reviewer-config.sh get
```

- **If it prints a reviewer, use it. Don't ask again.**
- If it prints nothing, this is the first run. Ask the user **once** which AI should
  review their PRs (use AskUserQuestion if available). Offer:
  - **Claude Opus** (`claude-opus`), recommended: strongest reviewer, runs as a subagent
    here with nothing extra to install
  - **OpenAI Codex** (`codex`): needs the `codex` CLI installed and signed in
  - **Google Gemini** (`gemini`): needs the `gemini` CLI installed and signed in
  - **GitHub Copilot** (`copilot`): needs `gh` v2.88+ and a GitHub plan with Copilot code
    review
  - A typed answer of "Claude Sonnet" maps to `claude-sonnet` (faster, cheaper).

  Save the answer: `<skill-dir>/scripts/reviewer-config.sh set <reviewer>`. It's stored
  for the user across all repos, so later runs skip the question.
- Change it only when the user asks (for example, "use Codex to review my PRs"): run
  `set` with the new value. To be asked again, run `clear`.
- Don't ask about fallbacks. They default to Claude Opus, then Claude Sonnet (see step 3).
  Change them only when the user asks:
  `<skill-dir>/scripts/reviewer-config.sh set-fallbacks claude-sonnet,codex`.

## 1. Get the branch ready

- If on the default branch, create a branch: `git switch -c <type>/<short-slug>`
  (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`).
- Check `git status`. Commit changes that are part of the work being PR'd. If it's unclear
  whether some changes belong, ask before committing them.
- Run the project's tests and linter if they exist (check `package.json` scripts,
  `Makefile`, etc.). Fix failures before opening the PR, or tell the user why you can't.

## 2. Open the PR

- If a PR already exists for this branch, use it and skip to step 3:
  `gh api "repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=open" --jq '.[0] | {number, html_url}'`.
- Push: `git push -u origin HEAD`.
- Write the body to a temp file. If `.github/pull_request_template.md` (or a file in
  `.github/PULL_REQUEST_TEMPLATE/`) exists, fill in that template. Otherwise use:
  **Summary** (what and why), **Changes** (bullets), **Testing** (what you ran), **Notes**
  (risks, follow-ups).
- Open it over REST:
  `gh api repos/<owner>/<repo>/pulls -f title="<title>" -f head=<branch> -f base=<default> -F body=@<file>`.
  Use a clear, imperative title. Add `-F draft=true` only if the user asked for a draft.

## 3. Review round N (start at N = 1)

Every reviewer gets the same instructions (`<skill-dir>/agents/senior-code-reviewer.md`),
and **none** gets your own explanation of the change or why you made it. Fresh eyes are
the point; the PR description is enough.

### Pick who reviews this round (with fallback)

```bash
<skill-dir>/scripts/reviewer-chain.sh
```

This lists, in order: the saved reviewer, the fallbacks (default `claude-opus`, then
`claude-sonnet`), and `self` last. Each line says `ready` or `unavailable`. Go down the
list:

1. Skip `unavailable` lines.
2. Try the first `ready` one, as described below.
3. If it **fails**, note why in a few words and try the next. Failing means: the script
   exits non-zero (3 not installed, 4 timed out, 5 errored or not signed in, or Copilot
   didn't respond in time), the subagent tool isn't available in this session, or the
   reviewer returns invalid JSON twice.
4. Remember who reviewed and why any earlier one was skipped, for example
   `Claude Opus (fallback: Gemini CLI not signed in)`. Pass it to step 4 as `--reviewer`
   and include it in the step 8 report.

**Don't stop to ask the user about a fallback.** The chain is the answer. Don't change
the saved reviewer either; next PR starts from the top of the list again.

Use the same reviewer for later rounds of this PR unless it fails; then continue down the
list from there.

**`claude-opus` or `claude-sonnet`:** spawn a subagent.
- If a `senior-code-reviewer` agent type is available, use it. Otherwise spawn a
  general-purpose agent and give it the full text of the agent file (everything below the
  frontmatter) as its instructions.
- Set the model to match (`opus` or `sonnet`).
- Tell it the repo path, PR number, base branch and round number, and to review with
  `git diff origin/<base>...HEAD`. From round 2 on, also give it the
  previous round's findings JSON and the replies posted on each thread.
- Save its JSON reply to `<wf>/round-N.json`. Check it with `jq -e .verdict`;
  if it isn't valid JSON, ask the reviewer once to resend only the JSON.

**`codex` or `gemini`:** run the CLI in read-only mode. The script passes along the
previous round and replies, and saves the JSON:

```bash
<skill-dir>/scripts/run-external-reviewer.sh <codex|gemini> <pr> <base> N <wf>/round-N.json [<wf>/round-<N-1>.json]
```

**`copilot`:** Copilot posts its own review on the PR, so there's no JSON and no step 4.

```bash
<skill-dir>/scripts/request-copilot-review.sh <pr>
```

When it returns, go straight to step 5. Copilot can't see replies to its comments, so on
re-review it judges the new code only.

**`self` (last resort):** use this only when every other reviewer failed. Review the diff
yourself, following the reviewer instructions as strictly as you can: read the full diff
fresh, as if someone else wrote it, and return the same JSON. Save it to
`<wf>/round-N.json` and post it with `--reviewer "Self-review (no independent reviewer
available: <reasons>)"`. A self-review can't confirm its own fixes, so do **one** round
only, then stop and tell the user plainly that the PR still needs an independent review.


## 4. Post the review (skip for Copilot)

```bash
<skill-dir>/scripts/post-review.sh <pr> <wf>/round-N.json N --reviewer "<who reviewed>"
```

This posts a GitHub review (event `COMMENT`, since GitHub blocks approving or requesting
changes on your own PR) with one inline comment per finding. If GitHub rejects the
inline comments, the script puts them all in the review body instead.

If the verdict is `approve` and there are no comments, skip to step 7.

## 5. Fix the comments

```bash
<skill-dir>/scripts/unresolved-threads.sh <pr>
```

This lists every unresolved thread, **including comments from humans**. Handle humans'
comments the same way as the reviewer's. For each thread:

- **Fix it** when it's correct. That's the normal case for `blocker`, `major` and `minor`.
  Fix `nit`s when it's quick and safe.
- **Push back** only with a concrete reason: the comment is factually wrong, the fix
  would break something, or it's out of scope for this PR. Don't push back just to avoid
  work.
- For `outdated` threads, check whether the current code already handles the comment.

Then:

1. Run tests and the linter again. Don't push red.
2. Commit as `Address review round N` (one commit per round) and `git push`. **Never
   force-push**; reviewers and humans rely on the history.
3. Reply on each thread, using `comment_id` and `thread_id` from the list (pass `-` if
   `thread_id` is null):
   - Fixed: `<skill-dir>/scripts/reply-thread.sh <pr> <comment_id> <thread_id> "Fixed in <short-sha>: <what changed>" --resolve`
   - Pushed back: `<skill-dir>/scripts/reply-thread.sh <pr> <comment_id> <thread_id> "Not changed: <reason>"`
     (leave it unresolved so a human can decide)

If `unresolved-threads.sh` returns `"resolved": null`, it couldn't tell which threads are
resolved. Skip threads that already have a "Fixed in" or "Not changed" reply.

## 6. Re-review

Go back to step 3 with N + 1. Stop when either:

- the verdict is `approve` and no reviewer threads are left unresolved except ones you
  pushed back on (for Copilot, which gives no verdict: its latest review added no new
  comments), or
- you've finished round 3. Don't loop past 3; if blockers remain, a human needs to look.

## 7. Wait for checks, then merge

When the review loop ends, merge the PR yourself if **all** of these hold:

- The final review came from an independent reviewer (not `self`) with verdict
  `approve`. For Copilot, its latest review added no new comments.
- Every review thread is resolved, **including human comments**. A thread you pushed
  back on stays open for a human, so it blocks the merge.
- The CI checks pass (step below).
- Auto-merge is on: `<skill-dir>/scripts/reviewer-config.sh get-auto-merge` prints `on`
  (the default). Turn it off with `set-auto-merge off` if the user asks.
- The user hasn't said not to merge this one, and it isn't a draft.

If any of these fail, don't merge. Leave the PR open and say what's missing in step 8.

**Wait for CI:**

```bash
<skill-dir>/scripts/wait-for-checks.sh <pr>
```

- Exit 0: checks passed. If it printed "No CI checks configured", that counts as passing,
  but say so in the report.
- Exit 1: a check failed. Treat it like a review comment: find the cause (the failing
  check's logs), fix it, run tests, commit `Fix CI: <what>`, and push. A fix changes code
  the reviewer already approved, so run one more review round (step 3) if you're under 3
  rounds. If you're at 3, don't merge; report it.
- Exit 2: checks were still running after 30 minutes. Don't merge; report it.

**Merge:**

```bash
<skill-dir>/scripts/merge-pr.sh <pr>
```

The script checks everything again right before merging. It refuses if the PR has
unresolved threads, conflicts, failing checks, is out of date, is blocked by branch
protection (such as a required human approval), or targets a branch other than the
default one. It never bypasses branch protection. It pins the merge to the commit that
was checked, so a push in the meantime stops it. It uses a merge commit when the repo
allows one, which keeps the "Fixed in <sha>" replies pointing at real commits; pass
`--method squash` or `--method rebase` only if the user asks.

If it refuses, don't try to work around it. Report the reason.

**Stacked PRs:** if this PR targets another PR's branch, merge that PR first, then
retarget this one to the default branch
(`gh api -X PATCH repos/<owner>/<repo>/pulls/<pr> -f base=<default>`) and merge it.
Merging it into the other branch wouldn't put it on the default branch.

## 8. Report back

Give the user:

- the PR link, and whether it was **merged** (with the merge commit) or left open, and why
- how many review rounds ran and the final verdict
- who reviewed, and any fallback that happened with the reason (for example "Gemini CLI
  wasn't signed in, so Claude Opus reviewed"). If it came down to a self-review, say so
  first: the PR still needs an independent review, so it wasn't merged.
- the CI result, or that the repo has no CI
- what was fixed (a short list, not every nit)
- anything left open: pushed-back comments with your reason, blockers that remain after
  round 3, or what stopped the merge
