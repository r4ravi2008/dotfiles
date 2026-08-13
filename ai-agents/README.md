# AI Agent Skills & Configuration

Unified AI coding agent configuration managed by [rulesync](https://github.com/dyoshikawa/rulesync). One source of truth, multiple tool outputs.

## Supported Tools

| Tool | Output Directory | Notes |
|------|-----------------|-------|
| **Claude Code** | `.claude/` | Commands, agents, skills, MCP, permissions |
| **Cursor** | `.cursor/` | Commands, agents, skills, MCP, `.mdc` rules |
| **OpenCode** | `.opencode/` + `opencode.json` | Commands, agents, skills, MCP |
| **Codex CLI** | `.codex/` | Agents (TOML), skills, MCP (TOML) |
| **Windsurf** | `.codeiumignore` | Uses `AGENTS.md` for rules |
| **GitHub Copilot** | `.copilot/` | MCP config |

## Quick Start

### 1. Clone

```sh
git clone git@github.intuit.com:rkommineni/skills.git
cd skills
```

### 2. Copy into your project

Copy the repo root into your project directory. Each AI tool will pick up its own config:

```sh
# Copy everything into your project
cp -a . /path/to/your/project/

# Or selectively copy for a single tool, e.g. Claude Code:
cp -a .claude/ /path/to/your/project/.claude/
cp AGENTS.md /path/to/your/project/AGENTS.md
cp .mcp.json /path/to/your/project/.mcp.json
```

### 3. (Optional) Customize and regenerate

If you want to modify rules, commands, skills, or MCP servers:

```sh
npm install -g rulesync   # or: npx rulesync

# Edit the source files in .rulesync/
# Then regenerate all tool-specific outputs:
npx rulesync generate
```

## Repository Structure

```
.
├── .rulesync/                  # === SOURCE OF TRUTH (edit here) ===
│   ├── rules/overview.md       #   Global AI agent rules & coding standards
│   ├── commands/               #   18 slash commands
│   ├── subagents/              #   2 specialized agent profiles
│   ├── skills/                 #   4 reusable knowledge modules
│   ├── mcp.json                #   MCP server definitions
│   └── .aiignore               #   File ignore patterns
│
├── .claude/                    # Generated: Claude Code config
├── .cursor/                    # Generated: Cursor config
├── .opencode/                  # Generated: OpenCode config
├── .codex/                     # Generated: Codex CLI config
├── .copilot/                   # Generated: GitHub Copilot config
│
├── AGENTS.md                   # Generated: Global rules (Windsurf, general)
├── opencode.json               # Generated: OpenCode app + MCP config
├── .mcp.json                   # Generated: Claude Code MCP config
├── .codeiumignore              # Generated: Windsurf ignore
├── .cursorignore               # Generated: Cursor ignore
└── rulesync.jsonc              # Rulesync configuration
```

> **Do not hand-edit files outside `.rulesync/`.** They are generated and will be overwritten on the next `npx rulesync generate`.

## What's Included

### Commands (18)

Slash commands available across all supported tools:

| Command | Description |
|---------|-------------|
| `/commit` | Analyze staged changes and generate a semantic commit message |
| `/debug` | Systematic 8-step debugging workflow |
| `/deslop` | Remove AI-generated code slop from the current branch |
| `/code-review` | Perform a structured code review |
| `/pr` | Create a pull request with summary |
| `/test` | Write or run tests |
| `/refactor` | Refactor code with clear rationale |
| `/explain` | Explain code or architecture |
| `/docs` | Generate documentation |
| `/spec` | Write a technical specification |
| `/security-audit` | Audit code for security issues |
| `/review-pr` | Review an existing pull request |
| `/fix-merge-conflicts` | Resolve merge conflicts |
| `/git-commit-flow` | Full git add/commit/push workflow |
| `/run-all-tests-and-fix` | Run the test suite and fix failures |
| `/cleanup-deprecate-code` | Clean up deprecated code |
| `/audit-effect-native-impl` | Audit Effect/native implementations |
| `/jira-list` | List Jira tickets |

### Skills (4)

Reusable knowledge modules agents can load on demand:

| Skill | Description |
|-------|-------------|
| `mcp-orchestration` | Control and inspect MCP servers via CLI |
| `project-context` | Summarize project goals, constraints, and architecture |
| `obsidian-cli` | Interact with Obsidian vaults via CLI |
| `obsidian-markdown` | Obsidian-flavored Markdown conventions |

### Subagents (2)

Specialized agent profiles for focused tasks:

| Agent | Role | Key Constraint |
|-------|------|----------------|
| `planner` | Creates detailed implementation plans for features, refactors, and bug fixes | Read-only -- produces plans, never writes code |
| `explorer` | Performs structured 6-step codebase analysis and outputs architectural summaries | Exploration and analysis only |

### MCP Servers (7 defined)

Configured in `.rulesync/mcp.json`. Most are disabled by default:

| Server | Type | Default |
|--------|------|---------|
| `context7` | Library documentation lookup | Disabled |
| `playwright` | Browser automation | Disabled |
| `pdf-reader` | PDF content extraction | Disabled |
| `MiniMax` | Coding plan generation | Disabled |
| `x-twitter-mcp` | Twitter/X integration | Disabled |
| `DAST-Orch` | DAST orchestrator | Enabled (URL) |
| `slack` | Slack integration | Enabled (URL) |

## Customization

### Adding a new command

1. Create `.rulesync/commands/my-command.md` with frontmatter:

```markdown
---
description: "What the command does"
targets: ["*"]
---

Your prompt template here. Use $ARGUMENTS for user input.
```

2. Run `npx rulesync generate`

### Adding a new skill

1. Create `.rulesync/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: "What the skill teaches"
targets: ["*"]
---

Skill content here.
```

2. Run `npx rulesync generate`

### Adding a new subagent

1. Create `.rulesync/subagents/my-agent.md` with frontmatter:

```markdown
---
name: my-agent
description: "Agent's role"
targets: ["*"]
---

System prompt for the agent.
```

2. Run `npx rulesync generate`

### Modifying MCP servers

Edit `.rulesync/mcp.json` and run `npx rulesync generate`.

## Rulesync Configuration

The `rulesync.jsonc` file controls generation behavior:

```jsonc
{
  "targets": ["opencode", "codexcli", "cursor", "windsurf", "claudecode"],
  "features": ["rules", "ignore", "mcp", "commands", "subagents", "skills"],
  "delete": true       // Remove orphaned generated files
}
```

See the [rulesync docs](https://github.com/dyoshikawa/rulesync) for all options.
