# Language and environment recommendations

Use the section for each language `detect-stack.sh` reported. Recommend what fits the
project's existing choices first (if it already uses Jest, don't propose Vitest). When
nothing is set up yet, the **Default pick** is a safe starting point.

For each language, the pieces to check are: unit test framework, coverage, linter,
type checking, formatter, UI/e2e (if relevant), and the config file that turns each on.

## JavaScript / TypeScript

| Area | Default pick | Config / where it lives |
|---|---|---|
| Unit | Vitest (Vite projects) or Jest | `vitest.config.ts` / `jest.config.*`; `"test"` script in `package.json` |
| Coverage | built in (`--coverage`, v8 provider) | `coverageThreshold` in the config |
| Component/UI | Testing Library (`@testing-library/react`, `/vue`, `/svelte`), Storybook + interaction tests | |
| Visual | Chromatic, Percy, or Playwright `toHaveScreenshot` | |
| E2E | Playwright (`playwright.config.ts`, traces on first retry, `data-testid`/role locators) | CI uploads the trace/report artifact |
| API | Supertest + MSW for mocks; Pact for consumer contracts | |
| Lint | ESLint flat config (`eslint.config.js`) or Biome; `eslint-plugin-jsx-a11y`, `-security`, `-import` | CI: `eslint . --max-warnings 0` |
| Types | `tsconfig.json` with `"strict": true`, `noUncheckedIndexedAccess`; CI: `tsc --noEmit` | |
| Format | Prettier or Biome; `.editorconfig` | `prettier --check .` in CI |
| Hooks | husky + lint-staged | |
| Deps | `knip` (unused), `npm audit`/`pnpm audit`, `engines` field, `.nvmrc` | |
| Mutation | Stryker | |
| Node services | Pino logging, `helmet`, request validation (zod), graceful shutdown | |

## Python

| Area | Default pick | Config |
|---|---|---|
| Unit | pytest (+ `pytest-xdist` parallel, `pytest-randomly` order checks) | `[tool.pytest.ini_options]` in `pyproject.toml` |
| Coverage | `pytest-cov` / coverage.py, branch coverage on | `[tool.coverage.*]`, `--cov-fail-under` |
| Property | Hypothesis | |
| Lint + format | ruff (lint + format) | `[tool.ruff]` in `pyproject.toml` |
| Types | mypy or pyright; start with `--strict` on new modules, ratchet | `[tool.mypy]` |
| Security | bandit, `pip-audit`, `safety` | |
| Web | Django: `manage.py check --deploy`, `django-debug-toolbar` off in prod; FastAPI: TestClient + schemathesis | |
| Env | `uv`/poetry lockfile, `.python-version`, `tox`/`nox` for a version matrix | |
| Mutation | mutmut | |

## Go

- Unit: `go test ./...` with table-driven tests; `-race` in CI; `-cover`/`-coverprofile`;
  `testify` optional; `go test -fuzz` for parsers; `testcontainers-go` for integration.
- Lint: `golangci-lint` (`.golangci.yml`: `errcheck`, `govet`, `staticcheck`, `gosec`, `revive`),
  `go vet`, `govulncheck`. Format: `gofmt`/`goimports`. CI: `go mod tidy` leaves no diff.
- Build tags for integration tests (`//go:build integration`) so unit runs stay fast.

## Rust

- Unit tests in `#[cfg(test)]` modules, integration tests in `tests/`, doc tests, `proptest`
  / `cargo-fuzz`; coverage with `cargo-llvm-cov` or `tarpaulin`.
- `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, `cargo audit`/`cargo deny`,
  `cargo-semver-checks` for libraries, `cargo-mutants`, `rust-toolchain.toml`.

## Java / Kotlin (Maven, Gradle)

- Unit: JUnit 5 + AssertJ + Mockito/MockK; integration: Testcontainers, `@SpringBootTest`
  slices (`@WebMvcTest`, `@DataJpaTest`); contracts: Spring Cloud Contract or Pact; architecture:
  ArchUnit; mutation: PIT.
- Coverage: JaCoCo with a rule (`jacocoTestCoverageVerification`).
- Static: Checkstyle, SpotBugs + FindSecBugs, PMD, Error Prone; Kotlin: detekt + ktlint.
  Format: Spotless (google-java-format/ktfmt). Security: OWASP dependency-check.
- Build: wrapper committed (`mvnw`/`gradlew`), toolchain version pinned, dependency locking.

## C# / .NET

- Unit: xUnit (or NUnit) + FluentAssertions + NSubstitute/Moq; integration:
  `WebApplicationFactory`, Testcontainers; coverage: coverlet + ReportGenerator.
- Static: Roslyn analyzers with `<AnalysisMode>All</AnalysisMode>`, `<TreatWarningsAsErrors>`,
  `<Nullable>enable</Nullable>`, StyleCop; `dotnet format --verify-no-changes`;
  `dotnet list package --vulnerable`; `global.json` pins the SDK; Central Package Management.

## Ruby / Rails

- RSpec (or Minitest) + FactoryBot; system tests with Capybara + Playwright/Selenium; SimpleCov
  with `minimum_coverage`; RuboCop (+ `rubocop-rails`, `-rspec`, `-performance`);
  Brakeman, `bundler-audit`; `bullet` for N+1; `.ruby-version`.

## PHP / Laravel / Symfony

- PHPUnit or Pest; Laravel feature tests and Dusk for browser; coverage via PCOV;
  PHPStan/Larastan (level 6+) or Psalm; PHP-CS-Fixer/Pint; `composer audit`; Infection for mutation.

## Swift / iOS and macOS

- XCTest or Swift Testing; XCUITest for UI; snapshot tests (`swift-snapshot-testing`);
  coverage via `xcodebuild -enableCodeCoverage YES`; SwiftLint + SwiftFormat; test plans for
  unit/UI/performance split; CI with `xcodebuild test` on a simulator matrix.

## Android (Kotlin / Java)

- JUnit + MockK + Turbine (flows); Robolectric; Espresso / Compose UI tests; screenshot tests
  (Paparazzi/Roborazzi); Lint (`./gradlew lint` with `warningsAsErrors`), detekt, ktlint;
  baseline profiles and macrobenchmarks for performance; Gradle managed devices in CI.

## Dart / Flutter

- `flutter_test` (unit + widget), golden tests, `integration_test`, `mocktail`;
  `analysis_options.yaml` with `flutter_lints`/`very_good_analysis`; `flutter test --coverage`.

## React Native / Expo

- Jest + Testing Library (`@testing-library/react-native`); E2E with Detox or Maestro;
  ESLint + TypeScript strict; EAS/Fastlane build checks in CI.

## Shell scripts

- ShellCheck in CI; `shfmt`; Bats tests (`bats-core`) for exit codes, args, idempotency;
  `set -euo pipefail`; no unquoted variables; scripts executable (mode checked).

## Containers and infrastructure as code

- Dockerfile: hadolint, multi-stage, non-root, pinned digests, `.dockerignore`, Trivy image scan,
  `HEALTHCHECK`. Compose: a smoke test that `docker compose up` becomes healthy.
- Terraform: `terraform fmt -check`, `validate`, tflint, tfsec/Checkov, plan on PR, state locking,
  Terratest for modules. Kubernetes: kubeconform/kubeval, kube-linter/Polaris, policy checks (OPA/Kyverno).
- Ansible: ansible-lint, Molecule. GitHub workflows: actionlint, pinned action SHAs.

## SQL and database migrations

- sqlfluff; migrations run in CI against a real DB from scratch and from the previous release;
  down/rollback or expand-contract; schema diff check (`atlas`, `prisma migrate diff`,
  `alembic check`); indexes reviewed for query patterns; seed data script.

## Data / ML projects

- Unit tests for transforms; data validation (Great Expectations, pandera, dbt tests);
  notebook hygiene (`nbstripout`, `papermill`/`nbmake` executes notebooks in CI);
  fixed random seeds; model regression test on a small golden dataset; DVC or lockfile for
  data versions; resource/cost budgets; no credentials in notebooks.

## By environment

| Environment | Prioritise |
|---|---|
| **Web frontend** | Component tests, Playwright e2e on critical journeys, visual regression, accessibility checks, bundle-size budget, Lighthouse CI, error tracking |
| **Backend API / microservice** | Integration tests with real DB, contract tests, auth tests, load test, structured logs + tracing, health checks, migration tests, timeouts/retries |
| **CLI tool** | Golden-output tests, exit codes, `--help` snapshot, cross-OS CI matrix, install/uninstall smoke test, shell completion |
| **Library / SDK** | Public API tests, semver/API-diff checks, docs examples run as tests, support-matrix CI, type definitions tests, deprecation policy |
| **Mobile app** | UI tests on simulators, crash reporting, accessibility, device/OS matrix, release-train automation, offline/poor-network tests |
| **Data pipeline / ML** | Data-quality tests, idempotent reruns, lineage, backfill tests, cost alerts, model evaluation gates |
| **Infrastructure** | Plan-on-PR, policy-as-code, drift detection, disaster-recovery drill, least-privilege IAM review |
| **Monorepo** | Affected-only CI (Nx/Turborepo/Bazel), per-package test/lint scripts, shared config, dependency-boundary rules, CODEOWNERS per package |
