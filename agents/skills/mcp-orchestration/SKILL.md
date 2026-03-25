---
name: mcp-orchestration
description: Discover, Control and inspect the MCP orchestrator via CLI over the RPC server. Use when managing MCP server lifecycle, checking orchestrator status, listing available servers, validating workflow tool requirements, or activating/deactivating MCP servers.
---

# MCP Orchestration

Control and inspect the MCP orchestrator via the CLI over the RPC server.

## When to use this skill

Use this skill when you need to:

- Check the status of the MCP orchestrator
- List available MCP servers
- Validate that required tools are available for a workflow
- Activate or deactivate MCP servers

## Quick reference

**Check status:**

```bash
stork mcp status
```

**List servers:**

```bash
stork mcp list
```

**Validate tools for a workflow:**

```bash
stork mcp validate-tools <workflowId>
```

**Activate/deactivate servers:**

```bash
stork mcp activate <server...>
stork mcp deactivate <server...>
stork mcp deactivate-all
```

## Command details

See [references/COMMANDS.md](references/COMMANDS.md) for complete command documentation including:

- All available options and flags
- RPC server selection
- Error handling patterns
