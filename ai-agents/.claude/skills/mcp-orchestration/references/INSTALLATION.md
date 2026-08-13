# Smith CLI Installation

The `smith` binary is required for all MCP orchestration commands. If `which smith` returns nothing, guide the user through one of the installation methods below.

## Quick Check

```bash
which smith && smith --version
```

If this prints a version, Smith is already installed — skip to verification.

## Method 1: Standalone Binary (Recommended)

Download the pre-built binary from [GitHub Releases](https://github.intuit.com/tax-taxdev/stork-workflows/releases).

### macOS (Apple Silicon)

```bash
# Download the latest release
# (user should get the URL from the releases page)
curl -L -o smith-macos <RELEASE_URL>/smith-macos

# Make executable and install to PATH
chmod +x smith-macos
sudo mv smith-macos /usr/local/bin/smith
```

### Linux (x64)

```bash
curl -L -o smith-linux <RELEASE_URL>/smith-linux

chmod +x smith-linux
sudo mv smith-linux /usr/local/bin/smith
```

### Windows (x64)

Download `smith-windows.exe` from the releases page and add its location to your PATH.

## Method 2: Build from Source

If the user has the `stork-workflows` repository cloned and `bun` installed:

```bash
cd <path-to-stork-workflows-repo>
./scripts/install-from-local.sh
```

This builds the binary for the current platform and installs it to `~/.local/bin/smith`. The script checks that `bun` is installed, detects the platform, compiles, and verifies PATH.

If `~/.local/bin` is not in PATH, the script will print instructions to add it.

### Manual build alternative

```bash
cd <path-to-stork-workflows-repo>
bun install
bun run build:binary
# Binary is created as ./smith in the repo root
sudo mv smith /usr/local/bin/smith
```

## Post-Installation Verification

After installation, verify everything works:

```bash
# Confirm binary is on PATH
smith --version

# Check agent dependencies
smith verify

# Check MCP orchestrator connectivity (optional — requires Intuit Dev Assist Desktop App)
smith mcp status
```

`smith verify` checks for available agent tools (`cursor`, `opencode`, `claude-agent-acp`) and MCP orchestrator connectivity. Agent tools are required for running agent workflows; the MCP orchestrator is optional but needed for MCP-dependent workflows.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `smith: command not found` after install | Ensure the install directory is in PATH. For `~/.local/bin`: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc` or `~/.bashrc`, then `source` it. |
| Permission denied on `/usr/local/bin` | Use `sudo mv` or install to `~/.local/bin` instead. |
| `bun: command not found` (build from source) | Install Bun first: `curl -fsSL https://bun.sh/install \| bash` |
| Binary built but wrong platform | The build scripts auto-detect platform. For cross-compilation use `bun run build:binary:macos` or `bun run build:binary:linux` explicitly. |
