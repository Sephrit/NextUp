#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$HOME/Desktop/Next Up.app"
MCP_DIR="$HOME/Library/Application Support/Next Up"

"$ROOT/scripts/build.sh" "$APP"
mkdir -p "$MCP_DIR"
cp "$ROOT/MCP/mcp-server.mjs" "$MCP_DIR/mcp-server.mjs"
chmod +x "$MCP_DIR/mcp-server.mjs"

echo "Installed: $APP"
echo "MCP server: $MCP_DIR/mcp-server.mjs"
