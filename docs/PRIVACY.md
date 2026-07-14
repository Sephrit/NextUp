# Privacy and local data

Next Up has no account, remote database, telemetry, advertising, or automatic
cloud sync. The library contains profile names, watch dates, session notes,
ratings, and provider links, so treat exported JSON as personal data.

Default application-data folders:

- macOS: `~/Library/Application Support/com.nextup.watchtracker/`
- Windows: `%APPDATA%\com.nextup.watchtracker\`

The folder contains `library.json` and the previous `library.backup.json`.
Watchmode credentials are separate in macOS Keychain or Windows Credential
Manager and are not included in exports.

Network requests occur only when a user searches or refreshes an enabled
metadata integration, or opens an external watch link. Optional AI access is a
separate local MCP process configured by the user; its privacy then also depends
on the chosen AI client and provider.
