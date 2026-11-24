# Quality checklist

Work through the categories that apply to the project. For each check: look for the
evidence, and only raise a finding if it's really missing or weak. "Skip when" says when
a check doesn't apply, so you don't file noise. Finding `category` values are in
backticks.

Prove a gap with something you saw: a path, a config line, a command's output, a number.
"Probably no tests for auth" is not evidence; "`src/auth/` has 6 source files and no test
file references any of them" is.

## 1. Testing (`unit-tests`, `integration-tests`, `ui-tests`, `e2e-tests`, `test-infra`)

| Check | Look for | Skip when |
|---|---|---|
| **Unit tests exist for core logic** | `detect-stack.sh` → `stats.source_dirs_without_tests`; business logic, parsers, validators, calculations, auth/permission code with no test referencing it | Pure config, generated code, thin glue |
| **Unit tests cover edge cases** | Tests only on the happy path: no empty input, null, boundary, error, timeout, or concurrency cases in code that has them | Trivial functions |
| **Bug-fix regression tests** | `git log --grep -iE 'fix|bug'` commits that touch only source, no tests | Few fix commits |
| **Integration tests for boundaries** | DB access, HTTP clients, queues, file I/O, third-party APIs tested only with mocks, or not at all. Ideal: real dependency in a container (Testcontainers, docker-compose) | No external dependencies |
| **API / contract tests** | An OpenAPI/GraphQL schema or client/server pair with no test checking they agree; no tests of status codes, validation errors, auth failures | No API |
| **UI / component tests** | UI components with logic (forms, conditional rendering, state) and no component tests; no Storybook or visual regression for a design-system library | No UI |
| **End-to-end tests for critical journeys** | No e2e suite, or one that skips the money paths: sign-up/login, checkout/payment, core create-edit-delete flow, upgrade/migration. Check selectors are stable (`data-testid`/roles, not CSS chains) | Library, CLI with no UI (use CLI-level tests instead) |
| **CLI / script tests** | CLIs and shell scripts with no test of exit codes, `--help`, bad args, or idempotency (Bats, pytest + subprocess, `go test` on `main`) | No CLI |
| **Mobile UI tests** | iOS/Android/Flutter/RN app with no XCUITest/Espresso/Detox/Maestro/integration_test | Not mobile |
| **Coverage is measured** | No coverage tool, or collected but not reported anywhere | Tests don't exist yet (file the tests first) |
| **Coverage is enforced** | Coverage tool present but CI has no threshold or ratchet, so it can drop silently. Prefer "no decrease" or a threshold at the current level over a vanity target | No coverage tool yet |
| **Tests run in CI and block merging** | No CI step runs tests; a failing test doesn't fail the build; branch protection doesn't require the check | |
| **Tests are reliable** | `skip`/`xit`/`@Ignore`/`t.Skip` counts; `sleep(` in tests; retries hiding flakes; tests depending on order, wall-clock, network, or shared state; `.only` committed | |
| **Tests are fast and parallel** | Whole suite runs serially for minutes; no test selection by changed files; no way to run one test quickly | Small suite |
| **Test data & fixtures** | Hand-copied fixtures drifting from reality; no factories/builders; tests share a mutable DB | |
| **Property-based / fuzz tests** | Parsers, serializers, encoders, state machines, and math with only example-based tests (Hypothesis, fast-check, proptest, jqwik, go fuzz) | No such code |
| **Mutation testing** | High coverage but weak assertions (tests that never `expect`/`assert`). Suggest Stryker, mutmut, PIT, cargo-mutants on the core module only | Low coverage: fix that first |
| **Snapshot hygiene** | Huge snapshots nobody reviews; snapshots updated blindly | No snapshots |
| **Performance / load tests** | Latency- or throughput-sensitive service with no k6/Locust/Gatling/benchmark and no budget | Internal tool, low traffic |
| **Accessibility tests** | Web UI with no axe/pa11y/Lighthouse check in CI or component tests | No UI |
| **Test docs** | No instructions for how to run unit/integration/e2e tests locally; undocumented env vars or seed data | |

## 2. Static analysis, types and style (`static-analysis`, `types`, `config`)

- **Linter configured and enforced in CI** for each language (see `references/stacks.md`).
  Check that the config isn't mostly disabled (`/* eslint-disable */` at the top of many
  files, a hundred ignored rules).
- **Type checking on:** TypeScript `strict`, mypy/pyright (start non-strict on changed
  files and ratchet), `Nullable` annotations in Java/Kotlin, `-Wall -Werror`/clang-tidy for C/C++,
  `go vet`, `clippy -D warnings`. Count `any`, `# type: ignore`, `@ts-ignore`, `unsafe`.
- **Formatter enforced** (Prettier, Black/ruff format, gofmt, rustfmt, google-java-format,
  dotnet format) so reviews aren't about whitespace. Plus an `.editorconfig`.
- **Pre-commit/pre-push hooks** (pre-commit, husky + lint-staged, lefthook) that run fast
  checks. Make sure CI runs the same checks, since hooks can be skipped.
- **Complexity and duplication:** very long functions/files, high cyclomatic complexity,
  copy-pasted blocks. Name the worst few files with sizes rather than "refactor everything".
- **Dead code and unused dependencies:** knip/ts-prune/depcheck, vulture, `go mod tidy`,
  `cargo udeps`, `deptry`.
- **Other languages in the repo are linted too:** shellcheck, hadolint (Dockerfile),
  actionlint (GitHub workflows), yamllint, markdownlint, tflint/`terraform validate`,
  sqlfluff, stylelint.
- **Compiler/runtime warnings treated as errors** where the language supports it.

## 3. CI/CD and build (`ci-cd`)

- CI exists, runs on every PR and on the default branch, and runs **build + lint + types +
  tests** (see `ci.runs` from `detect-stack.sh`).
- **Required status checks and branch protection** on the default branch: required reviews,
  required checks, no force-push, up-to-date before merge. Check through the API if you have
  access; otherwise suggest it as a question for an admin.
- **Caching** of dependencies/build outputs, and a **timeout** on every job.
- **Matrix** across supported language/runtime/OS versions (match what `package.json`
  `engines`, `python_requires`, `go.mod` etc. claim to support).
- **Concurrency control** (cancel superseded runs) and **least-privilege tokens**
  (`permissions:` block in GitHub Actions).
- **Third-party CI actions pinned** to a commit SHA (or at least a major version), and a
  Dependabot/Renovate rule to update them.
- **Reproducible builds:** lockfile committed and installed with the frozen/`ci` variant
  (`npm ci`, `pip install --require-hashes` or `uv sync --frozen`, `cargo --locked`),
  pinned toolchain version (`.nvmrc`, `.python-version`, `rust-toolchain.toml`, `.tool-versions`).
- **Release pipeline:** tagged, automated, with a changelog (Conventional Commits +
  release-please/semantic-release/changesets), not a manual checklist.
- **Deploy safety:** staging/preview environments, smoke tests after deploy, rollback
  documented or automated, migrations run safely (backwards-compatible, separate step).
- **Flaky or slow pipeline:** jobs over ~10 minutes, frequent re-runs. Split, shard, cache.

## 4. Security (`security`, `dependencies`)

- **Dependency updates automated** (Dependabot/Renovate) with grouped updates and a
  schedule, and **vulnerability scanning** in CI (`npm audit`, `pip-audit`, `cargo audit`,
  `govulncheck`, OWASP dependency-check, Trivy, OSV-Scanner).
- **Static security analysis** (CodeQL, Semgrep, Bandit, gosec, Brakeman, SpotBugs+FindSecBugs).
- **Secret scanning:** run `gitleaks`/`trufflehog` if installed, and grep for obvious keys.
  Check `.env`, `*.pem`, `*.key`, `credentials*` are not committed and are in `.gitignore`.
  A `.env.example` exists with no real values. If you find a real secret, don't repeat it in
  a ticket: describe where and tell the user to rotate it.
- **Input validation and output encoding** at boundaries (SQL built from strings, `eval`,
  `innerHTML`/`dangerouslySetInnerHTML`, shell commands from user input, path traversal,
  unsafe deserialization, SSRF-prone fetches).
- **AuthN/AuthZ tests:** a test per permission boundary (can user A read user B's data?).
- **Security headers / CORS / cookies:** CSP, HSTS, `SameSite`/`HttpOnly`/`Secure`, narrow CORS.
- **SECURITY.md** with a reporting channel; **CODEOWNERS** for sensitive paths.
- **Container hygiene:** non-root user, pinned base image digests, multi-stage build,
  `.dockerignore`, image scan (Trivy/Grype), no secrets in layers.
- **IaC scanning:** tfsec/Checkov/kics for Terraform, Kubernetes manifests, CloudFormation.
- **SBOM and provenance** for released artifacts (CycloneDX/SPDX, SLSA attestations, signed releases).
- **License compliance:** a dependency license check if the project is distributed.
- **Dependency hygiene:** unpinned (`*`, `latest`) versions, abandoned packages,
  multiple versions of the same library, large transitive trees for a trivial need.

## 5. Reliability and error handling (`reliability`)

- Errors swallowed (`catch {}`, `except: pass`, ignored `err` in Go), generic error messages,
  no error-path tests.
- External calls without **timeouts, retries with backoff, or circuit breakers**; no
  idempotency on retried writes.
- **Graceful shutdown** and signal handling; health/readiness endpoints.
- **Resource handling:** unclosed files/connections, unbounded queues/caches, no pagination.
- **Concurrency:** shared mutable state without locks, race detector not run in CI
  (`go test -race`, ThreadSanitizer), async code without cancellation.
- **Data safety:** migrations not reversible or tested, no backup/restore drill, no
  constraints at the DB level, money as floats, naive datetimes/time zones.
- **Feature flags** or staged rollouts for risky changes; **config validation at startup**
  (fail fast on missing env vars instead of at first use).

## 6. Observability (`observability`)

- **Structured logging** with levels and request/correlation IDs, no `print`/`console.log`
  debugging left in production paths, no PII/secrets in logs.
- **Error tracking** (Sentry, Rollbar, etc.) with release tagging and source maps.
- **Metrics** (RED: rate, errors, duration; saturation) and **tracing** (OpenTelemetry)
  for services; **dashboards and alerts** with an owner and a runbook link.
- **SLOs** for the user-facing paths that matter.
- **Frontend:** real-user monitoring (web vitals), JS error reporting.

## 7. Performance (`performance`)

- Known hot paths without **benchmarks** or a **budget** (bundle size, Lighthouse score, p95 latency).
- N+1 queries, missing DB indexes on filtered/joined columns, `SELECT *`, unbounded queries.
- Large bundles, unoptimized images, no code splitting/lazy loading, blocking scripts.
- No caching strategy (HTTP caching headers, memoization, CDN).
- A CI check that fails on regressions (bundle-size limit, benchmark comparison).

## 8. Accessibility and UX quality (`accessibility`)

- Automated checks (axe, pa11y, Lighthouse CI, eslint-plugin-jsx-a11y, Storybook a11y addon).
- Semantic HTML, labels on inputs, keyboard navigation and focus order, colour contrast,
  alt text, ARIA only where needed, reduced-motion support.
- Responsive/mobile viewport tests; internationalisation (hard-coded strings, date/number
  formats, RTL) if the product is multilingual.
- Loading, empty, and error states exist and are tested.

## 9. Documentation and project hygiene (`docs`, `dx`)

- **README** states what it is, how to install, run, test, and deploy. A new developer can go
  from clone to running tests using only the docs (try the commands if you can).
- **CONTRIBUTING**, PR template, issue templates, CODEOWNERS, CODE_OF_CONDUCT (public repos).
- **Architecture overview** and **ADRs** for non-obvious decisions; diagrams that match the code.
- **API docs** generated from source (OpenAPI, typedoc, Sphinx, godoc, rustdoc) and published;
  public functions have doc comments.
- **CHANGELOG** and a versioning policy. **LICENSE** present and matches `package.json`/metadata.
- **One-command setup:** `make setup`/`just`/devcontainer/`docker compose up`, pinned runtime versions,
  seed data, `.env.example` documented.
- **Agent/AI instructions** (`CLAUDE.md`/`AGENTS.md`) with the build, test, and style commands.
- **Stale TODO/FIXME/HACK** comments: count them, list the oldest, link to issues or remove.
- **Large files/binaries** committed; missing `.gitignore` entries; Git LFS for assets.

## 10. Architecture and maintainability (`architecture`)

- Circular dependencies, layering violations (UI importing DB code), god classes/modules
  (use `wc -l` and fan-in/fan-out to name the worst offenders).
- Missing module boundaries in a monorepo (no `exports`/visibility rules, no dependency
  constraints such as dependency-cruiser/ArchUnit/import-linter).
- Inconsistent patterns (three ways to fetch data, two state managers).
- Public API surface unclear; breaking changes not detected (API-diff tooling like
  `api-extractor`, `japicmp`, `cargo-semver-checks`, `buf breaking`).
- Deprecated APIs and end-of-life runtimes/frameworks (check the versions against
  vendor support dates).

## How to size a finding

One finding = one PR-sized task a single engineer can pick up. Split "improve test
coverage" into: *unit tests for `src/billing/` (4 modules, 0 tests)*, *CI coverage
threshold*, *Playwright test for checkout*. Merge tiny related items (three missing lint
configs) into one. If a category has more than ~5 findings, keep the top 3 by value and put
the rest in the report under "Also noticed".
