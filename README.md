# White Oak AI Hub

Shared AI resources for White Oak: Claude skills, prompts, agents and MCP configs.

## Layout

```
white-oak-ai-hub/
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md        # required: frontmatter + instructions
│       ├── scripts/        # optional: executable helpers the skill calls
│       ├── references/     # optional: docs loaded only when needed
│       └── assets/         # optional: templates, images, files used in output
├── prompts/                # reusable prompts and system prompts
├── agents/                 # subagent definitions
├── mcp/                    # MCP server configs
├── docs/                   # guides and notes
├── templates/
│   └── skill-template/
│       └── SKILL.md        # copy this to start a new skill
└── scripts/
    ├── new-skill.sh        # scaffold a new skill from the template
    └── validate.sh         # check every SKILL.md has valid frontmatter
```

## Skills

| Skill | What it does |
|---|---|
| [`pr-workflow`](skills/pr-workflow/SKILL.md) | Opens a PR, has an independent senior-engineer agent review it, posts the review, fixes the comments, and re-reviews (max 3 rounds). Never merges. Needs `gh` and `jq`. |

**Optional:** to make the reviewer available as its own agent in Claude Code, copy
`skills/pr-workflow/agents/senior-code-reviewer.md` into `~/.claude/agents/`. The skill
works without this step.

## Creating a skill

```bash
./scripts/new-skill.sh my-new-skill
```

Then edit `skills/my-new-skill/SKILL.md`.

## SKILL.md rules

- Frontmatter needs `name` and `description`.
- `name`: lowercase letters, numbers and hyphens; must match the folder name; max 64 chars.
- `description`: what the skill does **and when to use it** — this is what decides whether Claude picks it up. Max 1024 chars.
- Keep the body focused (under ~500 lines). Move long reference material into `references/` and link to it.

## Validating

```bash
./scripts/validate.sh
```

## Installing a skill

- **Claude Code:** copy or symlink a skill folder into `~/.claude/skills/` (personal) or `.claude/skills/` in a project.
- **Claude apps:** zip the skill folder and upload it under Settings → Capabilities → Skills.

## License

Apache 2.0 — see [LICENSE](LICENSE).
