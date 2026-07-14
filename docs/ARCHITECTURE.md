# Architecture

Next Up is a local-first desktop application:

```text
React + TypeScript UI
        │ Tauri commands
Rust desktop shell ── OS credential vault
        │ atomic JSON
Local library + backup

Optional MCP client ── stdio ── Node MCP server ── same local library
```

The UI contains no embedded API secret. Rust owns filesystem and credential
operations. A browser-only preview falls back to localStorage for visual
development, but production persistence uses Tauri commands.

The JSON model separates media items, collections/orders, watch events, viewing
sessions, and ratings. IDs connect records without duplicating watch history
when an item appears in multiple viewing orders. The schema is normalized on
load so old libraries receive safe defaults.

There is intentionally no hosted backend. “Full stack” here means a packaged
frontend, native application layer, durable storage, secure credential handling,
external metadata boundary, tests, CI, and release pipeline—not an unnecessary
remote account service.
