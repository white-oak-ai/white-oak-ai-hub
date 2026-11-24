# Environment & Conventions Reference

This skill reads its operational context (repository locations, issue tracker, branching conventions) from the local environment configuration before executing.

## Configuration Resolution

The skill searches for configuration in this order:
1. Local skill override: `<skill-dir>/references/environment.local.yaml` (or `.md`)
2. Hub-wide local configuration: `config/environment.local.yaml`
3. Hub-wide default configuration: `config/environment.yaml`
4. Standalone skill reference: `<skill-dir>/references/environment.md`

If unconfigured or containing placeholder values (`example-org/example-repo`), run the setup wizard:
```bash
# From hub root:
./scripts/setup-environment.sh --init

# Or via skill helper:
<skill-dir>/scripts/setup-environment.sh --init
```

## Repositories & Paths

| Name | GitHub Slug | Local Path | Default Branch | Build Command | Test Command | Issue Prefixes |
|---|---|---|---|---|---|---|
| `main` | `my-org/my-project` | `.` | `main` | `npm run build` | `npm test` | `ENG-`, `APP-` |

## Task & Ticketing Tracker

- **Tracker**: `github-issues` (or `linear`, `jira`, `gitlab-issues`, `azure-boards`)
- **Project/Team Key**: `my-org/my-project` (or `ENG`)
- **Ticket Format**: `#[0-9]+` (or `ENG-[0-9]+`)
- **Connector Tool**: `github` (or `linear`, `jira` MCP tools)
- **Workflow Labels**:
  - In Progress: `in-progress`
  - Quality: `quality`
  - Skip Labels: `blocked, on-hold, wontfix, duplicate, invalid, question`

## Conventions

- **Branch Pattern**: `feat/{issue_id}-{slug}`
- **Commit Format**: Conventional Commits (`feat: ...`, `fix: ...`)
- **PR Reviewers**: `senior-code-reviewer`
- **Require CI**: `true`
