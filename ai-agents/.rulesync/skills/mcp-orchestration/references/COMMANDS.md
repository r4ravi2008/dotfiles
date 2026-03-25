# MCP Orchestration Commands Reference

Complete reference for all MCP orchestrator CLI commands.

## Status command

Check the current status of the MCP orchestrator:

```bash
stork mcp status
```

## List servers command

List all available MCP servers and their current state:

```bash
stork mcp list
```

## Validate tools command

Validate that all required tools for a workflow are available:

```bash
stork mcp validate-tools <workflowId>
```

## Activate/deactivate commands

Control server lifecycle:

```bash
# Activate one or more servers
stork mcp activate <server...>

# Deactivate one or more servers
stork mcp deactivate <server...>

# Deactivate all servers
stork mcp deactivate-all
```

## RPC server selection

Use `--rpc-ws-url` to specify the RPC server:

- **Default:** `ws://127.0.0.1:4000/rpc`
- **Explicit URL provided:** If `--rpc-ws-url` is explicitly provided and unreachable, the command fails fast
- **Default URL unreachable:** If `--rpc-ws-url` is not provided and the default URL is unreachable, the CLI auto-starts a local RPC server (separate process) and retries

## JSON mode

**On success:** stdout contains JSON only

**On failure:**

- stdout is empty
- stderr contains JSON error:

```json
{
  "error": {
    "message": "...",
    "tag": "...",
    "wsUrl": "..."
  }
}
```

- Exit code is non-zero
