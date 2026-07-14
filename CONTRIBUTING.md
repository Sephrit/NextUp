# Contributing

Issues and pull requests are welcome. Keep changes small enough to review and
include tests for library rules, migrations, or MCP mutations.

## Development

1. Install the Tauri prerequisites for your operating system.
2. Run `npm ci` inside `desktop/`.
3. Run `npm test`, `npm run build`, and `cargo check --manifest-path src-tauri/Cargo.toml`.
4. From the repository root, run `node Tests/mcp-smoke.mjs` and
   `./scripts/scan-secrets.sh`.
5. Test onboarding with one profile and at least three profiles, then test a
   wide window and a narrow vertical window.

macOS contributors changing the legacy SwiftUI app should also run `swift test`.

## Product rules

- A title may have many watch events; rewatches never overwrite history.
- A partial session does not count as watched until the runtime is reached.
- One rating belongs to one profile and one watch event.
- Sealed ratings must not appear in summaries, timelines, AI reads, or averages
  until the configured reveal condition is satisfied.
- Integrations are opt-in and failures must not block manual tracking.
- New schema fields need backward-compatible defaults in `normalizeLibrary`.

Never add real API keys, personal watch libraries, generated installers, or MCP
client configuration containing secrets. External metadata must be documented
in `THIRD_PARTY_NOTICES.md`.
