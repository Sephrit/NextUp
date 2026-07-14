# Optional AI and MCP package

AI is not required for Next Up. The desktop app does not send prompts, watch
history, ratings, or profile names to an AI provider. Turning on the AI setting
only reveals setup guidance; a user must separately configure an MCP client.

## What the package can do

The dependency-free Node server in `MCP/mcp-server.mjs` lets a compatible client:

- read collection progress, statistics, watch history, sessions, and recent activity;
- search the saved library and inspect revealed ratings;
- add movies, collections, episodes, series, links, and streaming services;
- log watches or partial sessions, set queue priority, and submit one profile's rating;
- import Watchmode movies or TVmaze series when those external services are used;
- undo the most recent mutation from the automatic local backup.

Ratings that have not met the reveal rule are returned only as `sealed`. The
server never includes their score in reads.

## Requirements

- Next Up has been opened at least once
- Node.js 20 or newer
- An MCP-compatible client

The server auto-detects the app data folder on Windows and macOS. Set
`NEXT_UP_DATA_DIR` only for a portable or nonstandard installation.

## Client configuration

Replace the example path with the folder where this repository or optional MCP
package was extracted.

```json
{
  "mcpServers": {
    "next-up": {
      "command": "node",
      "args": ["C:/Tools/NextUp/MCP/mcp-server.mjs"]
    }
  }
}
```

On macOS, an equivalent path is `/Users/YOU/NextUp/MCP/mcp-server.mjs`.
Codex TOML uses the same command and argument:

```toml
[mcp_servers.next-up]
command = "node"
args = ["/Users/YOU/NextUp/MCP/mcp-server.mjs"]
```

Claude, Hermes, and OpenClaw use the same stdio server command even if their
configuration file format differs.

## Watchmode in AI tools

Most MCP tools need no key. On macOS the server can read the key saved by Next
Up from Keychain. On Windows, Watchmode-powered MCP tools additionally require
`NEXTUP_WATCHMODE_KEY` in the MCP server process environment; omit it if the AI
only needs local library and manual-add tools. Never commit this value or paste
it into an issue.

## Recommended permissions

Allow read tools automatically if desired, but require confirmation for add,
edit, watch, rating, profile, service, and undo tools. Review the client's tool
call before approval. Back up the library from Settings before bulk changes.

The server uses the network only for an explicitly requested Watchmode or
TVmaze tool. It does not run in the background and does not open a TCP port.
