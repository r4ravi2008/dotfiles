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
│   ├── commands/               #   Personal slash commands (Jira, PR, Effect, deslop)
│   ├── skills/                 #   commit + force-pushing-ghes-default + Obsidian + use-computer-mcp + hunk/plannotator extras
│   ├── mcp.json                #   MCP server definitions
│   └── .aiignore               #   File ignore patterns
│
├── .claude/                    # Generated: Claude Code config
├── .cursor/                    # Generated: Cursor config
├── .opencode/                  # Generated: OpenCode config
├── .codex/                     # Generated: Codex CLI config
├── .agents/                    # Generated: shared agent skills (Obsidian)
│
├── opencode.json               # Generated: OpenCode app + MCP config
├── .mcp.json                   # Generated: Claude Code MCP config
├── .cursorignore               # Generated: Cursor ignore
└── rulesync.jsonc              # Rulesync configuration
```

> **Do not hand-edit files outside `.rulesync/`.** They are generated and will be overwritten on the next `npx rulesync generate`.

## What's Included

### Commands (4)

Personal slash commands. Engineering workflows (`/tdd`, `/grill-me`, `/code-review`, …) come from [Matt Pocock's skills](https://github.com/mattpocock/skills). `bootstrap.sh` clones that repo and copies the engineering + productivity skills into `~/.agents/skills` (and Claude/Cursor skill dirs).

| Command | Description |
|---------|-------------|
| `/deslop` | Remove AI-generated code slop from the current branch |
| `/pr` | Create a pull request with `gh` |
| `/audit-effect-native-impl` | Audit Effect/native implementations |
| `/jira-list` | List Jira tickets for the current sprint |

### Skills (3)

| Skill | Description |
|-------|-------------|
| `obsidian-cli` | Interact with Obsidian vaults via CLI |
| `obsidian-markdown` | Obsidian-flavored Markdown conventions |
| `use-computer-mcp` | Drive desktop apps via Open Computer Use MCP |

### MCP Servers

Configured in `.rulesync/mcp.json`.

| Server | Type | Default |
|--------|------|---------|
| `DAST-Orch` | CWS MCP stream | Enabled (URL) |
| `slack-mcp` | Slack MCP | Enabled (HTTP + OAuth) |
| `open-computer-use` | Desktop computer use (`open-computer-use mcp`) | Enabled (stdio) |

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
  "targets": ["opencode", "codexcli", "cursor", "claudecode"],
  "features": ["rules", "ignore", "mcp", "commands", "subagents", "skills"],
  "delete": true       // Remove orphaned generated files
}
```

See the [rulesync docs](https://github.com/dyoshikawa/rulesync) for all options.
