# White Oak AI Hub

Shared AI resources for White Oak: Claude skills, prompts, agents and MCP configs.

## Installing skills

Start by cloning the repo:

```bash
git clone https://github.com/white-oak-ai/white-oak-ai-hub.git
cd white-oak-ai-hub
```

### Claude Code

Claude Code picks up skills from two places:

- `~/.claude/skills/`: available in every project (personal)
- `.claude/skills/` inside a project: available in that project only, and shared with
  anyone who clones it

**Symlink (recommended).** Running `git pull` in this repo then updates the skill too.

```bash
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/pr-workflow" ~/.claude/skills/pr-workflow
```

**Copy.** Use this to pin a version or to commit the skill into a project.

```bash
mkdir -p .claude/skills
cp -R /path/to/white-oak-ai-hub/skills/pr-workflow .claude/skills/
```

**All skills at once:**

```bash
mkdir -p ~/.claude/skills
for s in skills/*/; do ln -sfn "$PWD/$s" ~/.claude/skills/"$(basename "$s")"; done
```

Start a new Claude Code session afterward so it loads the skills.

### Claude apps (web, desktop, mobile)

1. Build the zip:
   ```bash
   ./scripts/package-skill.sh pr-workflow   # creates dist/pr-workflow.zip
   ./scripts/package-skill.sh --all         # or one zip per skill
   ```
2. In Claude, go to **Customize > Skills**, click **+**, choose **Create skill**, then
   **Upload a skill**, and pick the zip.
3. Make sure **Code execution and file creation** is turned on in Settings, since skills
   need it.

Skills you upload are private to your account until you share them. Team and
Enterprise owners can upload a skill under **Organization settings > Plugins & skills**
to give it to everyone in the organization. Skills enabled in your Claude account also
load in Claude Code when you sign in with the same account.

Upload the zip this script builds rather than zipping the folder by hand. Claude needs
the skill folder at the top of the zip (`pr-workflow.zip` → `pr-workflow/SKILL.md`), and
a zip with `SKILL.md` at its root isn't recognized as a skill.

### Skill requirements

| Skill | Needs | Best in |
|---|---|---|
| `pr-workflow` | `git`, `gh` signed in (`gh auth login`), `jq`, `python3`. Plus whichever reviewer you pick: nothing extra for Claude; the `codex` CLI for Codex; the `gemini` CLI for Gemini; `gh` v2.88+ and Copilot code review on your plan for Copilot | Claude Code, which can reach your repo and GitHub |

**Choosing the PR reviewer.** The first time you run `pr-workflow`, it asks which AI
should review your PRs: Claude Opus (recommended), Claude Sonnet, OpenAI Codex, Google
Gemini or GitHub Copilot. It saves the answer to
`~/.config/white-oak-ai-hub/pr-workflow.json` and doesn't ask again. To switch, tell
Claude something like "use Gemini to review my PRs", or run
`skills/pr-workflow/scripts/reviewer-config.sh set <claude-opus|claude-sonnet|codex|gemini|copilot>`.

**If the reviewer isn't available.** When your reviewer can't run (CLI not installed,
not signed in, timed out after 10 minutes, or returned no usable review), the skill moves
to the next reviewer on its own instead of stopping. The default order is your reviewer,
then Claude Opus, then Claude Sonnet. Each review on the PR names who reviewed it and why
any fallback happened. If nothing else can run, the skill does a single self-review,
clearly labeled, and tells you the PR still needs an independent review.

To change the fallback order:
`skills/pr-workflow/scripts/reviewer-config.sh set-fallbacks claude-sonnet,codex`.
To change the time limit for the Codex and Gemini CLIs, set `PR_REVIEW_TIMEOUT` (seconds).

**Merging (new: on by default).** `pr-workflow` used to always leave PRs open for you;
it now merges them itself when it's safe. When the reviewer approves, every review thread is resolved (including
human comments) and CI passes, the skill merges the PR. It won't merge after a
self-review, with a comment it pushed back on still open, with failing checks or merge
conflicts, or past branch protection such as a required human approval. A repo with no
CI counts as passing, and the report says so. It only merges the exact commit the
reviewer approved: anything pushed afterward needs another review. A human's "Request
changes" review or an objection in the PR conversation also blocks it. To turn merging off and keep PRs open for
you: `skills/pr-workflow/scripts/reviewer-config.sh set-auto-merge off`.

### Subagents

`pr-workflow` works without extra setup. To also make its reviewer available as a
standalone agent in Claude Code:

```bash
mkdir -p ~/.claude/agents
ln -s "$PWD/skills/pr-workflow/agents/senior-code-reviewer.md" ~/.claude/agents/
```

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
    ├── validate.sh         # check every SKILL.md has valid frontmatter
    └── package-skill.sh    # zip a skill for upload to the Claude apps
```

## Skills

| Skill | What it does |
|---|---|
| [`pr-workflow`](skills/pr-workflow/SKILL.md) | Opens a PR, has an independent senior-engineer reviewer (Claude, Codex, Gemini or Copilot, chosen once and remembered) review it, fixes the comments, re-reviews (max 3 rounds), then merges once every comment is addressed and CI passes. |

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

## License

Apache 2.0 — see [LICENSE](LICENSE).
