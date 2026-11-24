#!/usr/bin/env bash
# Detect languages, test tooling, static analysis, CI, security and docs setup for a repo.
# Prints one JSON object. Read-only: it only lists files and reads manifests.
#
# Usage: detect-stack.sh [repo-dir]
#
# Detection is by file names and manifest contents, so it is a starting point: always
# confirm a finding by reading the code before filing it.
set -euo pipefail

cd "${1:-.}"
command -v jq >/dev/null || { echo "detect-stack.sh needs jq" >&2; exit 1; }

# --- file list (tracked + untracked-not-ignored; falls back to find) -------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ALL="$(git ls-files -co --exclude-standard)"
else
  ALL="$(find . -type f \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/.venv/*' -not -path '*/dist/*' -not -path '*/build/*' | sed 's#^\./##')"
fi

# has_file <ERE>: true if any path matches.
has_file() { grep -Eq "$1" <<<"$ALL"; }
# count_files <ERE>: number of matching paths.
count_files() { grep -Ec "$1" <<<"$ALL" || true; }
# first_files <ERE> [n]: first n matching paths.
first_files() { grep -E "$1" <<<"$ALL" | head -n "${2:-5}" || true; }

# --- manifest text, for "does it mention X" checks -------------------------------------
# Concatenate dependency manifests so we can grep them once. Capped to keep this fast.
manifest_text() {
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] && head -c 200000 "$f"
    echo
  done < <(grep -E '(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|setup\.cfg|setup\.py|Pipfile|Cargo\.toml|go\.mod|Gemfile|composer\.json|pom\.xml|build\.gradle(\.kts)?|[^/]+\.csproj|mix\.exs|pubspec\.yaml|Package\.swift|deno\.jsonc?)$' <<<"$ALL" | head -n 60)
}
MANIFESTS="$(manifest_text)"
# mentions <ERE>: true if a dependency manifest matches (case-insensitive).
mentions() { grep -Eiq "$1" <<<"$MANIFESTS"; }

# --- accumulate named lists -------------------------------------------------------------
declare -A L=()
add() { # add <list> <item>
  case ",${L[$1]:-}," in *",$2,"*) return ;; esac
  L[$1]="${L[$1]:+${L[$1]},}$2"
}
arr() { # arr <list> -> JSON array
  if [[ -z "${L[$1]:-}" ]]; then echo '[]'; else tr ',' '\n' <<<"${L[$1]}" | jq -R . | jq -sc .; fi
}
bool() { if "$@"; then echo true; else echo false; fi; }

# --- languages & package managers ------------------------------------------------------
has_file '(^|/)package\.json$'                          && add lang javascript-typescript
has_file '(^|/)tsconfig[^/]*\.json$|\.tsx?$'            && add lang typescript
has_file '(^|/)(pyproject\.toml|setup\.py|requirements[^/]*\.txt|Pipfile)$|\.py$' && add lang python
has_file '(^|/)go\.mod$'                                && add lang go
has_file '(^|/)Cargo\.toml$'                            && add lang rust
has_file '(^|/)(pom\.xml|build\.gradle(\.kts)?)$|\.java$' && add lang java-kotlin
has_file '\.kt$'                                        && add lang kotlin
has_file '\.csproj$|\.sln$|\.cs$'                       && add lang csharp-dotnet
has_file '(^|/)Gemfile$|\.rb$'                          && add lang ruby
has_file '(^|/)composer\.json$|\.php$'                  && add lang php
has_file '\.swift$|(^|/)Package\.swift$'                && add lang swift
has_file '(^|/)pubspec\.yaml$'                          && add lang dart-flutter
has_file '(^|/)mix\.exs$'                               && add lang elixir
has_file '\.(c|cc|cpp|cxx|h|hpp)$'                      && add lang c-cpp
has_file '\.(sh|bash)$'                                 && add lang shell
has_file '(^|/)(Dockerfile[^/]*|[^/]+\.dockerfile)$'    && add lang dockerfile
has_file '\.tf$'                                        && add lang terraform
has_file '\.sql$'                                       && add lang sql

has_file '(^|/)package-lock\.json$'   && add pm npm
has_file '(^|/)yarn\.lock$'           && add pm yarn
has_file '(^|/)pnpm-lock\.yaml$'      && add pm pnpm
has_file '(^|/)bun\.lockb?$'          && add pm bun
has_file '(^|/)poetry\.lock$'         && add pm poetry
has_file '(^|/)uv\.lock$'             && add pm uv
has_file '(^|/)Pipfile\.lock$'        && add pm pipenv
has_file '(^|/)Cargo\.lock$'          && add pm cargo
has_file '(^|/)go\.sum$'              && add pm go-modules
has_file '(^|/)Gemfile\.lock$'        && add pm bundler
has_file '(^|/)composer\.lock$'       && add pm composer
has_file '(^|/)packages\.lock\.json$' && add pm nuget

# Frameworks (affect which UI / e2e checks apply).
mentions '"react"|"react-dom"'                && add fw react
mentions '"vue"'                              && add fw vue
mentions '"@angular/core"'                    && add fw angular
mentions '"svelte"'                           && add fw svelte
mentions '"next"'                             && add fw nextjs
mentions '"express"|"fastify"|"@nestjs/core"|"koa"' && add fw node-server
mentions 'django'                             && add fw django
mentions 'flask'                              && add fw flask
mentions 'fastapi'                            && add fw fastapi
mentions 'spring-boot|org\.springframework'   && add fw spring
mentions 'rails'                              && add fw rails
mentions 'laravel/framework'                  && add fw laravel
mentions 'react-native|"expo"'                && add fw react-native
mentions 'flutter'                            && add fw flutter
has_file '\.(xcodeproj|xcworkspace)/'         && add fw ios-xcode
has_file '(^|/)AndroidManifest\.xml$'         && add fw android

# --- testing ----------------------------------------------------------------------------
# Unit / general test frameworks
mentions '"jest"|jest\.config'                          && add unit jest
has_file '(^|/)jest\.config\.[a-z]+$'                   && add unit jest
mentions '"vitest"'                                     && add unit vitest
mentions '"mocha"'                                      && add unit mocha
mentions '"ava"|"tap"|"node:test"'                      && add unit node-test-runner
mentions 'pytest'                                       && add unit pytest
has_file '(^|/)(conftest\.py|pytest\.ini)$'             && add unit pytest
has_file '(^|/)test_[^/]+\.py$|_test\.py$'              && add unit pytest-or-unittest
has_file '_test\.go$'                                   && add unit go-test
has_file '(^|/)tests?/.*\.rs$|(^|/)src/.*\.rs$'         && has_file '#\[test\]' && add unit rust-test
mentions 'junit'                                        && add unit junit
mentions 'xunit|nunit|mstest'                           && add unit dotnet-test
mentions 'rspec'                                        && add unit rspec
mentions 'minitest'                                     && add unit minitest
mentions 'phpunit|pestphp'                              && add unit phpunit-pest
has_file '(^|/)Tests?/.*\.swift$|Tests\.swift$'         && add unit xctest
mentions 'exunit'                                       && add unit exunit
has_file '(^|/)(bats|test)/.*\.bats$|\.bats$'           && add unit bats

# UI / component tests
mentions '@testing-library|"enzyme"'                    && add ui testing-library
mentions '@storybook|"storybook"'                       && add ui storybook
has_file '(^|/)\.storybook/'                            && add ui storybook
mentions 'chromatic|percy|loki|backstopjs'              && add visual visual-regression
mentions '@vue/test-utils'                              && add ui vue-test-utils
mentions 'espresso|compose-ui-test'                     && add ui android-ui-test
has_file '(^|/)[^/]*UITests?/'                          && add ui xcuitest
mentions 'flutter_test|integration_test'                && add ui flutter-test

# End-to-end
mentions '"@playwright/test"|"playwright"'              && add e2e playwright
has_file '(^|/)playwright\.config\.[a-z]+$'             && add e2e playwright
mentions '"cypress"'                                    && add e2e cypress
has_file '(^|/)cypress\.config\.[a-z]+$|(^|/)cypress/'  && add e2e cypress
mentions '"puppeteer"'                                  && add e2e puppeteer
mentions '"selenium|selenium-webdriver|selenium'        && add e2e selenium
mentions '"webdriverio"|"@wdio/'                        && add e2e webdriverio
mentions '"testcafe"'                                   && add e2e testcafe
mentions 'detox'                                        && add e2e detox
mentions 'appium'                                       && add e2e appium
mentions 'maestro'                                      && add e2e maestro
has_file '(^|/)(e2e|end-to-end)/'                       && add e2e-dir e2e-directory

# API / contract / integration
mentions 'supertest|"pactum"|"nock"|"msw"'              && add api http-test-or-mocking
mentions '"@pact-foundation|pact-python|pact-jvm'       && add contract pact
mentions 'testcontainers'                               && add integration testcontainers
mentions 'schemathesis|dredd'                           && add contract openapi-contract
has_file '(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$'   && add api openapi-spec
has_file '\.(http|rest)$|(^|/)postman[^/]*\.json$|\.postman_collection\.json$' && add api request-collections
has_file '(^|/)(integration|it)/'                       && add integration-dir integration-directory

# Other test types
mentions 'hypothesis|fast-check|proptest|jqwik|quickcheck' && add property property-based
mentions 'stryker|mutmut|pitest|cargo-mutants|infection' && add mutation mutation-testing
mentions 'k6|locust|gatling|artillery|jmeter'           && add load load-testing
has_file '(^|/)(k6|load|perf|performance)[^/]*/'        && add load load-dir
mentions 'axe-core|jest-axe|pa11y|@axe-core|lighthouse' && add a11y automated-a11y

# Coverage
mentions 'istanbul|nyc|c8|coverage\.py|pytest-cov|jacoco|coverlet|simplecov|tarpaulin|llvm-cov|codecov' && add coverage tool
has_file '(^|/)(\.nycrc[^/]*|\.coveragerc|codecov\.ya?ml|\.codecov\.ya?ml|coveralls\.yml|sonar-project\.properties)$' && add coverage config
grep -Eqi 'coverageThreshold|fail_under|fail-under|--cov-fail-under|minimum.*coverage|COVERAGE_MIN|coverage:\s*$' <<<"$MANIFESTS$(first_files '(^|/)(jest\.config[^/]*|\.coveragerc|codecov\.ya?ml|pyproject\.toml)$' 5 | xargs -r cat 2>/dev/null)" \
  && add coverage threshold-configured

# --- static analysis / types / formatting ----------------------------------------------
has_file '(^|/)(\.eslintrc[^/]*|eslint\.config\.[a-z]+)$' && add lint eslint
mentions '"eslint"'                                      && add lint eslint
mentions '"biome"|@biomejs'                              && add lint biome
mentions 'ruff'                                          && add lint ruff
has_file '(^|/)ruff\.toml$|(^|/)\.ruff\.toml$'           && add lint ruff
mentions 'flake8|pylint'                                 && add lint flake8-pylint
has_file '(^|/)\.golangci\.ya?ml$'                       && add lint golangci-lint
has_file '(^|/)clippy\.toml$'                            && add lint clippy
has_file '(^|/)\.rubocop\.yml$'                          && add lint rubocop
mentions 'phpstan|psalm|php-cs-fixer|phpcs'              && add lint php-static
mentions 'detekt|ktlint|spotbugs|checkstyle|pmd|errorprone' && add lint jvm-static
has_file '(^|/)\.swiftlint\.ya?ml$'                      && add lint swiftlint
has_file '(^|/)analysis_options\.yaml$'                  && add lint dart-analyze
has_file '(^|/)\.shellcheckrc$'                          && add lint shellcheck
has_file '(^|/)\.hadolint\.ya?ml$'                       && add lint hadolint
has_file '(^|/)\.markdownlint[^/]*$'                     && add lint markdownlint
has_file '(^|/)\.yamllint[^/]*$'                         && add lint yamllint
has_file '(^|/)\.tflint\.hcl$'                           && add lint tflint
has_file '(^|/)\.stylelintrc[^/]*$|stylelint\.config'    && add lint stylelint
mentions 'sonar|codeclimate|qodana'                      && add lint code-quality-platform
has_file '(^|/)(sonar-project\.properties|\.codeclimate\.ya?ml)$' && add lint code-quality-platform

has_file '(^|/)tsconfig[^/]*\.json$' && add types typescript
grep -Eq '"strict"[[:space:]]*:[[:space:]]*true' <<<"$(first_files '(^|/)tsconfig[^/]*\.json$' 5 | xargs -r cat 2>/dev/null)" && add types typescript-strict
mentions 'mypy|pyright|pytype'                           && add types python-type-checker
has_file '(^|/)(mypy\.ini|pyrightconfig\.json|\.mypy\.ini)$' && add types python-type-checker
has_file '(^|/)(\.flowconfig|sorbet/)'                   && add types flow-or-sorbet

has_file '(^|/)(\.prettierrc[^/]*|prettier\.config\.[a-z]+)$' && add format prettier
mentions '"prettier"'                                    && add format prettier
mentions '\bblack\b|ruff format'                         && add format python-formatter
has_file '(^|/)(rustfmt|\.rustfmt)\.toml$'               && add format rustfmt
has_file '(^|/)\.clang-format$'                          && add format clang-format
has_file '(^|/)\.editorconfig$'                          && add format editorconfig

has_file '(^|/)(\.pre-commit-config\.ya?ml|lefthook\.ya?ml|\.lefthook\.ya?ml)$|(^|/)\.husky/' && add hooks pre-commit
mentions '"husky"|"lint-staged"|"simple-git-hooks"'      && add hooks pre-commit

# --- CI / CD ----------------------------------------------------------------------------
has_file '(^|/)\.github/workflows/[^/]+\.ya?ml$'         && add ci github-actions
has_file '(^|/)\.gitlab-ci\.ya?ml$'                      && add ci gitlab-ci
has_file '(^|/)(azure-pipelines\.ya?ml)$'                && add ci azure-pipelines
has_file '(^|/)(\.circleci/config\.yml)$'                && add ci circleci
has_file '(^|/)Jenkinsfile$'                             && add ci jenkins
has_file '(^|/)(bitbucket-pipelines\.yml)$'              && add ci bitbucket-pipelines
has_file '(^|/)(\.travis\.yml|appveyor\.yml|\.drone\.yml|buildkite[^/]*\.ya?ml|\.buildkite/)' && add ci other

CI_TEXT="$(first_files '(^|/)(\.github/workflows/[^/]+\.ya?ml|\.gitlab-ci\.ya?ml|azure-pipelines\.ya?ml|\.circleci/config\.yml|Jenkinsfile|bitbucket-pipelines\.yml)$' 30 | xargs -r cat 2>/dev/null || true)"
ci_mentions() { grep -Eiq "$1" <<<"$CI_TEXT"; }
ci_mentions 'npm (run )?test|yarn test|pnpm (run )?test|pytest|go test|cargo test|mvn.* test|mvn.* verify|gradle.* test|dotnet test|rspec|phpunit|bundle exec rake|make test|ctest|swift test|xcodebuild.* test|mix test|flutter test' && add ci-has tests
ci_mentions 'lint|eslint|ruff|flake8|golangci|clippy|rubocop|shellcheck|phpstan|detekt|swiftlint|ktlint' && add ci-has lint
ci_mentions 'tsc|mypy|pyright|typecheck|type-check'      && add ci-has typecheck
ci_mentions 'coverage|--cov|codecov|coveralls|jacoco|lcov' && add ci-has coverage
ci_mentions 'playwright|cypress|e2e|selenium|detox|maestro|appium' && add ci-has e2e
ci_mentions 'codeql|semgrep|snyk|trivy|bandit|gosec|brakeman|sonar|dependency-review|osv-scanner|grype' && add ci-has security-scan
ci_mentions 'gitleaks|trufflehog|detect-secrets|secret.?scan' && add ci-has secret-scan
ci_mentions 'matrix:'                                    && add ci-has matrix
ci_mentions 'cache'                                      && add ci-has caching
ci_mentions 'timeout-minutes|timeout:'                   && add ci-has timeouts
ci_mentions 'concurrency:'                               && add ci-has concurrency-control
ci_mentions 'permissions:'                               && add ci-has least-privilege-token
ci_mentions 'uses:[^#]*@[0-9a-f]{40}'                    && add ci-has pinned-action-shas

# --- security & dependency hygiene ------------------------------------------------------
has_file '(^|/)\.github/dependabot\.ya?ml$'              && add sec dependabot
has_file '(^|/)(renovate\.json5?|\.renovaterc[^/]*|\.github/renovate\.json5?)$' && add sec renovate
has_file '(^|/)SECURITY\.md$'                            && add sec security-policy
has_file '(^|/)\.gitleaks\.toml$|(^|/)\.secrets\.baseline$' && add sec secret-scanning-config
has_file '(^|/)\.github/workflows/[^/]*codeql[^/]*\.ya?ml$' && add sec codeql
has_file '(^|/)\.(env|env\.local|env\.production)$'      && add sec env-file-committed
has_file '(^|/)\.env\.example$|(^|/)\.env\.sample$'      && add sec env-example
has_file '\.(pem|key|p12|pfx)$'                          && add sec key-like-files-committed
has_file '(^|/)(sbom|bom)[^/]*\.(json|xml)$'             && add sec sbom

# --- docs, ownership & repo hygiene -----------------------------------------------------
has_file '(^|/)README(\.[a-z]+)?$'                       && add repo readme
has_file '(^|/)CONTRIBUTING(\.[a-z]+)?$'                 && add repo contributing
has_file '(^|/)(LICENSE|LICENCE|COPYING)[^/]*$'          && add repo license
has_file '(^|/)CHANGELOG(\.[a-z]+)?$|(^|/)HISTORY\.md$|(^|/)RELEASES?\.md$' && add repo changelog
has_file '(^|/)(CODEOWNERS|\.github/CODEOWNERS|docs/CODEOWNERS)$' && add repo codeowners
has_file '(^|/)CODE_OF_CONDUCT(\.[a-z]+)?$'              && add repo code-of-conduct
has_file '(^|/)\.github/(pull_request_template\.md|PULL_REQUEST_TEMPLATE(/|\.md))' && add repo pr-template
has_file '(^|/)\.github/ISSUE_TEMPLATE/'                 && add repo issue-templates
has_file '(^|/)(docs?|documentation)/'                   && add repo docs-dir
has_file '(^|/)(adr|adrs|docs/adr|docs/decisions)/'      && add repo adrs
has_file '(^|/)(CLAUDE|AGENTS)\.md$'                     && add repo agent-instructions
has_file '(^|/)\.gitignore$'                             && add repo gitignore
has_file '(^|/)(\.nvmrc|\.node-version|\.python-version|\.tool-versions|rust-toolchain(\.toml)?|\.ruby-version|\.sdkmanrc|global\.json)$' && add repo pinned-runtime
has_file '(^|/)(Makefile|justfile|Taskfile\.ya?ml)$'     && add repo task-runner
has_file '(^|/)(Dockerfile[^/]*)$'                       && add repo dockerfile
has_file '(^|/)(docker-compose[^/]*\.ya?ml|compose\.ya?ml)$' && add repo compose
has_file '(^|/)(\.devcontainer/|devcontainer\.json)'     && add repo devcontainer
has_file '(^|/)(\.dockerignore)$'                        && add repo dockerignore

# Observability signals (checked in code, not just manifests).
mentions 'sentry|rollbar|bugsnag|datadog|newrelic|opentelemetry|prom-client|prometheus|micrometer|honeycomb|elastic-apm' && add obs apm-or-tracing
mentions 'winston|pino|bunyan|structlog|loguru|zap|logrus|slog|serilog|log4j|logback|tracing' && add obs structured-logging

# --- stats ------------------------------------------------------------------------------
TEST_RE='(^|/)(tests?|__tests__|spec|specs|e2e|cypress|playwright|integration|it)/|[._-](test|spec)\.[a-z]+$|_test\.(go|py|rb|exs?)$|(^|/)test_[^/]+\.py$|Tests?\.(java|kt|cs|swift|php)$|\.bats$'
SRC_RE='\.(js|jsx|ts|tsx|mjs|cjs|py|go|rs|java|kt|cs|rb|php|swift|dart|ex|exs|c|cc|cpp|h|hpp|sh|vue|svelte)$'
TOTAL_SRC="$(grep -E "$SRC_RE" <<<"$ALL" | grep -Evc "$TEST_RE" || true)"
TOTAL_TEST="$(grep -E "$SRC_RE" <<<"$ALL" | grep -Ec "$TEST_RE" || true)"
WORKFLOWS="$(count_files '(^|/)\.github/workflows/[^/]+\.ya?ml$')"
MANIFEST_COUNT="$(count_files '(^|/)(package\.json|pyproject\.toml|go\.mod|Cargo\.toml|pom\.xml|build\.gradle(\.kts)?|[^/]+\.csproj)$')"
# Monorepo hint: several manifests in different folders, or a workspace tool.
MONO=false
{ (( MANIFEST_COUNT > 2 )) || has_file '(^|/)(pnpm-workspace\.yaml|lerna\.json|nx\.json|turbo\.json|rush\.json)$'; } && MONO=true

# Untested-source heuristic: top-level source dirs with source files but no test files.
UNTESTED_DIRS="$(
  grep -E "$SRC_RE" <<<"$ALL" | grep -Ev "$TEST_RE" \
    | awk -F/ 'NF>1 {d=$1; if ($1 ~ /^(src|lib|app|packages|apps|services|internal|pkg|cmd)$/ && NF>2) d=$1"/"$2; c[d]++} END {for (k in c) print c[k], k}' \
    | sort -rn | head -n 25 \
    | while read -r n d; do
        t="$(grep -E "$TEST_RE" <<<"$ALL" | grep -Fc "$d/" || true)"
        # tests living beside the code or in a mirrored tests/ tree both count
        base="${d##*/}"
        m="$(grep -E "$TEST_RE" <<<"$ALL" | grep -Ec "(^|/)(tests?|__tests__|spec)/(.*/)?$base(/|$)" || true)"
        (( t + m == 0 )) && jq -nc --arg d "$d" --argjson n "$n" '{dir:$d, source_files:$n}'
      done | jq -sc . 2>/dev/null || echo '[]'
)"
[[ -n "$UNTESTED_DIRS" ]] || UNTESTED_DIRS='[]'

# --- output -----------------------------------------------------------------------------
jq -n \
  --arg root "$(pwd)" \
  --argjson languages "$(arr lang)" \
  --argjson package_managers "$(arr pm)" \
  --argjson frameworks "$(arr fw)" \
  --argjson unit "$(arr unit)" --argjson ui "$(arr ui)" --argjson visual "$(arr visual)" \
  --argjson e2e "$(arr e2e)" --argjson e2e_dir "$(arr e2e-dir)" \
  --argjson api "$(arr api)" --argjson contract "$(arr contract)" \
  --argjson integration "$(arr integration)" --argjson integration_dir "$(arr integration-dir)" \
  --argjson property "$(arr property)" --argjson mutation "$(arr mutation)" \
  --argjson load "$(arr load)" --argjson a11y "$(arr a11y)" --argjson coverage "$(arr coverage)" \
  --argjson linters "$(arr lint)" --argjson types "$(arr types)" \
  --argjson formatters "$(arr format)" --argjson hooks "$(arr hooks)" \
  --argjson ci "$(arr ci)" --argjson ci_has "$(arr ci-has)" \
  --argjson security "$(arr sec)" --argjson repo "$(arr repo)" --argjson observability "$(arr obs)" \
  --argjson src "$TOTAL_SRC" --argjson tst "$TOTAL_TEST" --argjson wf "$WORKFLOWS" \
  --argjson mono "$MONO" --argjson untested "$UNTESTED_DIRS" \
  '{
    root: $root,
    languages: $languages, package_managers: $package_managers, frameworks: $frameworks,
    monorepo_hint: $mono,
    testing: {
      unit: $unit, ui_component: $ui, visual_regression: $visual,
      e2e: ($e2e + $e2e_dir | unique), api: $api, contract: $contract,
      integration: ($integration + $integration_dir | unique),
      property_based: $property, mutation: $mutation, load: $load,
      accessibility: $a11y, coverage: $coverage
    },
    static_analysis: { linters: $linters, type_checking: $types, formatters: $formatters, git_hooks: $hooks },
    ci: { providers: $ci, workflow_files: $wf, runs: $ci_has },
    security: $security,
    repo_hygiene: $repo,
    observability: $observability,
    stats: {
      source_files: $src, test_files: $tst,
      test_to_source_ratio: (if $src == 0 then null else (($tst / $src * 100 | round) / 100) end),
      source_dirs_without_tests: $untested
    }
  }'
