# Next Up

Next Up is a private-by-default movie and TV watch tracker for one person, a
couple, a family, or a movie club. It runs as a desktop app on Windows and
macOS, keeps the library on the user's computer, and works without an account,
cloud server, analytics, or AI.

> The cross-platform Tauri app is the public beta. The original SwiftUI macOS
> app remains in this repository while feature parity and migration are tested.

## What it does

- Tracks movies, movie series, shows, episodes, partial sessions, and rewatches
- Imports a show's announced seasons and episodes from TVmaze in one step, with
  large full-row season expanders
- Keeps separate half-star ratings, short reviews, favorites, and “rewatch?” votes
- Supports one to twelve profiles with optional sealed group ratings
- Builds a permanent watch timeline, genre view, progress stats, and Moviedex achievements
- Sorts and filters the sidebar by watching, next up, unwatched, watched, title,
  progress, public rating, or recent activity
- Shows saved watch links only for the services a household selects
- Imports movie artwork, runtime, genres, scores, and US availability from an
  optional Watchmode key
- Exports and restores portable JSON backups
- Offers a separate, optional local MCP package for Codex, Claude, Hermes,
  OpenClaw, and other compatible assistants

## Install for normal users

Download the Windows or macOS installer from the repository's **Releases** page.
Pre-release friend builds are also available as artifacts from the **Build desktop
installers** GitHub Actions workflow. See [Windows testing](docs/WINDOWS_TESTING.md)
for the exact handoff steps and unsigned-app warnings.

No developer tools, Watchmode key, or AI setup are required after installation.

## Run from source

Requirements: Node.js 22+, Rust stable, and the platform prerequisites listed in
the [official Tauri guide](https://v2.tauri.app/start/prerequisites/).

```sh
git clone YOUR_REPOSITORY_URL
cd NextUp/desktop
npm ci
npm run desktop:dev
```

Checks used in CI:

```sh
cd desktop
npm test
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
cd ..
node Tests/mcp-smoke.mjs
./scripts/scan-secrets.sh
```

Build platform-native installers with `npm run desktop:build`. Tauri creates
Windows NSIS/MSI bundles on Windows and an app bundle/DMG on macOS; GitHub
Actions builds both so developers do not need two computers.

## First run and migration

Onboarding accepts one to twelve unique profile names. AI is off by default.
The app starts with an empty library, and users can add movies manually without
any API key. Show search and episode import use TVmaze and also need no API key;
Watchmode is only needed for enriched movie search and availability.

On macOS, the cross-platform app automatically imports the original app's
`~/Library/Application Support/Next Up/library.json` the first time it opens.
It copies rather than deletes the old file. New data is stored in the platform
application-data folder under `com.nextup.watchtracker` and saved atomically
with a one-step backup.

## Optional integrations

Watchmode and AI/MCP are independent opt-ins:

- **Watchmode:** enter a key in Settings. It is kept in macOS Keychain or
  Windows Credential Manager—not in the library or exports.
- **AI/MCP:** the app works fully without it. The optional server uses local
  standard input/output, opens no network port, and exposes explicit read and
  write tools. Read [AI setup and permissions](AI_SETUP.md) before enabling it.

## Project map

- `desktop/` — React/TypeScript UI and Rust/Tauri desktop shell for Windows/macOS
- `MCP/` — optional dependency-free local MCP server
- `Sources/`, `Package.swift` — original native macOS implementation
- `Tests/` — native, integration, and MCP regression tests
- `docs/` — architecture, privacy, ratings, releases, and tester guides

## Privacy, security, and contributing

Read [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and
[Contributing](CONTRIBUTING.md). Do not commit personal library exports, API
keys, credential files, or screenshots containing account information.

TV series discovery in the legacy app and MCP package uses TVmaze under its
published terms; see [third-party notices](THIRD_PARTY_NOTICES.md).

Next Up is MIT licensed.
