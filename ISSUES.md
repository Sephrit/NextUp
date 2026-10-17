# Issues

## Open

### 2. The library's audit log cannot show an undo, so it can never explain how the library reached its current state
*Found 2026-09-15 · severity: medium · area: MCP/mcp-server.mjs (`undo_last_change` line 763, `mutate()` line 188) · commit: b427c6d · by: deepseek-v4.1-flash*

Every other mutation goes through `mutate()`, which appends to `library.auditLog` before writing — that is what makes `recent_activity` a history of the library. `undo_last_change` does not. It takes its own lock and swaps the two files directly:

```js
const current = fs.readFileSync(libraryPath); const backup = fs.readFileSync(backupPath);
fs.writeFileSync(libraryPath, backup); fs.writeFileSync(backupPath, current);
```

So it records nothing of its own, and because what it restores is the whole file, the audit entries for the mutation being undone are restored away with it. The log is not a history of the library; it is a history of whichever library file is on disk right now, and an undo silently rewrites the past it is explaining.

How you know: measured across the restore described in issue 1. Before the undo, `library.json` held 141 audit entries ending `verify-mcp-tools | Updated streaming services` (2026-09-14T23:07:28). After the undo it holds 140, ending `verify-mcp-tools | Refreshed metadata for 1 movies` (2026-09-14T17:54:08) — the wipe it just reversed is gone from the trail, and nothing anywhere records that a restore happened. Anyone investigating "how did this get wiped" reads a log that the repair has already edited.

Worth keeping, and worth stating: the swap itself is correct and deliberately reversible ("Call again to redo"), and the lock discipline is right — this entry is about the missing record, not the mechanism. A fix is for `undo_last_change` to append its own audit entry and to leave the restored log's entries in place rather than discarding them, so a restore shows up in the trail it changes.
