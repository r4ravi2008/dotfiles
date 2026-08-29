#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp -f target/release/herdr-pane-minimap ./herdr-pane-minimap
chmod +x ./herdr-pane-minimap
