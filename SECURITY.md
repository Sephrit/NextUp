# Security policy

## Reporting a vulnerability

Please use GitHub's private **Report a vulnerability** feature. Do not post API
keys, personal library data, exploit details, or account screenshots in a public
issue. Maintainers should acknowledge a report within seven days and avoid
publishing details until a fix is available.

## Security model

- Library data is local and is written atomically with a local backup.
- Watchmode credentials use the operating system credential vault.
- The optional MCP server communicates over standard input/output and opens no
  listening port.
- AI clients can mutate the library only through named MCP tools; users should
  require confirmation for writes in their client settings.
- No analytics, ads, account system, remote database, or background sync is included.

This is a personal media tracker, not a hardened multi-user server. Anyone with
access to the operating-system account can potentially read its local library.

## Before publishing

Run `./scripts/scan-secrets.sh`, `npm audit` inside `desktop/`, the complete test
suite, and a clean build. Never commit `.env` files, credential exports,
`library.json`, personal backups, signing certificates, or built installers.
