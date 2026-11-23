# Scoring issues: value vs risk

Score each shortlisted issue on two 1–5 scales, then rank by **value ÷ risk**. Ties go to
the lower risk, then the older issue. Base every score on evidence you can point to (the
issue text, labels, reactions, the code you looked at), not on how interesting it sounds.

## Value (higher is better)

| Score | Looks like |
|---|---|
| 5 | Security fix, data loss or corruption, outage, or a bug blocking users with no workaround. Labels such as `security`, `critical`, `P0`/`P1`, `priority: high`. |
| 4 | A bug many people hit (several upvotes or "me too" comments), a regression, or an issue that other open issues depend on (`blocked by #this`). |
| 3 | A real bug with a workaround, or a small feature users asked for. In the current milestone. |
| 2 | Polish: docs, error messages, small UX fixes, test coverage, tidy-ups with a clear payoff. |
| 1 | Nice-to-have with no stated user, cosmetic, or speculative. |

Add 1 (cap 5) when the issue unblocks other issues, or when a maintainer asked for it in
a comment. Subtract 1 when it's old and nobody has reacted or commented in months.

## Risk (lower is better)

Look at the code before scoring risk. Find where the change goes (`grep` for the names
the issue mentions) and estimate the diff.

| Score | Looks like |
|---|---|
| 1 | One or two files, a few dozen lines, well-covered by existing tests, clear expected result. Docs, copy, config defaults, an obvious off-by-one. |
| 2 | A contained change in one module with tests you can extend. Behavior is fully specified. |
| 3 | Several files or modules, or behavior that's only partly specified, or code with thin tests. |
| 4 | Touches a sensitive area (see below), changes a public API or data format, needs a migration, or the issue leaves real design decisions open. |
| 5 | Cross-cutting refactor, needs infra/secrets/services you don't have, can't be tested here, or the right behavior is disputed in the comments. |

**Sensitive areas** (add 1, cap 5): authentication and authorization, payments and
billing, database migrations and schema changes, encryption and secrets handling,
deletion of user data, CI/CD and deploy config, concurrency and locking, anything the
repo marks as critical in its docs or CODEOWNERS.

## Hard exclusions

Don't pick an issue, whatever its score, when:

- Its risk is 5.
- It depends on an open issue or unmerged PR.
- Someone else is assigned, it already has the in-progress label, or an open PR
  references it.
- A recent comment (last ~14 days) from someone other than you says they're working on it.
- Maintainers disagree in the comments about what should happen, or the last
  maintainer comment asks a question nobody answered.
- It's really a tracking issue, epic, or question rather than a unit of work.

## Example

| # | Title | Value | Risk | Score | Why |
|---|---|---|---|---|---|
| 42 | Crash when config file is empty | 4 | 1 | 4.0 | 6 upvotes; a null check in `config/load.ts` with an existing test file |
| 17 | Add SSO login | 4 | 4 | 1.0 | Auth area, open design questions |
| 58 | Typo in README install step | 2 | 1 | 2.0 | Trivial, low impact |

Pick #42.
