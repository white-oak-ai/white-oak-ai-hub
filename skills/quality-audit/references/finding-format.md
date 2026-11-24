# Finding format

Every finding is one JSON object. The whole audit is a JSON array in `<wf>/findings.json`.
`scripts/render-body.sh <file> --validate` checks it; the scripts refuse to file anything
that fails validation.

```json
{
  "id": "e2e-checkout-flow",
  "title": "Add Playwright e2e test for the checkout flow",
  "category": "e2e-tests",
  "priority": "P1",
  "effort": "M",
  "why": "Checkout is the revenue path and has no automated end-to-end coverage. A regression here would reach customers unnoticed.",
  "evidence": [
    "`e2e/` contains only `smoke.spec.ts` (loads the home page)",
    "`src/checkout/` has 11 source files; none are referenced by a test",
    "`.github/workflows/ci.yml` runs `npm test` only; no Playwright step"
  ],
  "approach": [
    "Add `@playwright/test` and a `playwright.config.ts` (trace on first retry)",
    "Cover add to cart, pay with test card, payment declined, empty cart",
    "Run in CI against a seeded preview environment and upload the HTML report"
  ],
  "acceptance": [
    "`npx playwright test` passes locally and in CI",
    "The declined-card path is asserted",
    "A failing run uploads a trace artifact"
  ]
}
```

## Fields

| Field | Rules |
|---|---|
| `id` | Stable lowercase slug, 3–81 chars of `a-z 0-9 . _ -`. **Derive it from the subject, not the date**, so the same gap gets the same id next time (`unit-tests-billing`, `ci-coverage-threshold`). The id is how re-runs skip tickets that already exist. |
| `title` | 8–120 chars, starts with a verb, names the thing: "Add unit tests for `src/billing/`", not "Improve tests". |
| `category` | One of: `unit-tests` `integration-tests` `ui-tests` `e2e-tests` `test-infra` `static-analysis` `types` `ci-cd` `security` `dependencies` `observability` `docs` `performance` `accessibility` `reliability` `config` `dx` `architecture` |
| `priority` | `P1` real risk now (security, no tests on critical path, broken or missing CI gate). `P2` clear value, plan it. `P3` nice to have. Aim for few P1s: if everything is P1, nothing is. |
| `effort` | `S` under half a day. `M` a day or two. `L` longer, and you should try to split it. |
| `why` | One to three sentences on the consequence, not a restatement of the title. |
| `evidence` | At least one entry, each something you observed: paths, counts, config lines, command output. No guesses. Keep secrets out. |
| `approach` | Optional but recommended: 2–4 concrete steps, naming the tool that fits this stack. |
| `acceptance` | At least one **checkable** criterion: a command that passes, a file that exists, a CI job that runs. These become the ticket's checklist. |

## Quality bar for each finding

- An engineer who has never seen the audit can start work from the ticket alone.
- It names the tool the project should use, matching what it already uses (`references/stacks.md`).
- It is one PR-sized task, or an obvious first slice of a larger one ("start with `src/billing/`").
- It doesn't duplicate another finding or an existing open issue.
- The evidence would still be true if someone checked it now.

## The report

Alongside `findings.json`, write `<wf>/report.md` for the user, in this order:

1. **Summary:** stack detected, what's already good (say so; it's useful and builds trust),
   counts by priority.
2. **Table of findings:** id, title, category, priority, effort.
3. **Also noticed:** things you saw but didn't file (low value, too vague, or over the cap).
4. **Couldn't check:** anything you couldn't verify (couldn't run tests, no access to branch
   protection, no network), so the user knows the audit's limits.
