# MCP Orchestration Commands Reference

Complete reference for all MCP orchestrator CLI commands.

## Status command

Check the current status of the MCP orchestrator:

```bash
smith mcp status
```

## List servers command

List all available MCP servers and their current state:

```bash
smith mcp list
```

## Validate tools command

Validate that all required tools for a workflow are available:

```bash
smith mcp validate-tools <workflowId>
```

## Activate/deactivate commands

Control server lifecycle:

```bash
# Activate one or more servers
smith mcp activate <server...>

# Deactivate one or more servers
smith mcp deactivate <server...>

# Deactivate all servers
smith mcp deactivate-all
```

