# Issues

## Open

### 3. The deployed MCP server is two fixes behind the repo, so a rejected write can still wipe the live undo point
*Found 2026-11-18 · severity: high · area: deployment of MCP/mcp-server.mjs to ~/Library/Application Support/Next Up/ · commit: ed5356b · by: claude-opus-5.5*

The copy that agents actually run, `~/Library/Application Support/Next Up/mcp-server.mjs` (placed there by `scripts/install.sh`), is not the repo copy. Its SHA-256 matches `MCP/mcp-server.mjs` at commit 3dfb808 exactly, so it lacks 7007e8e (reject a call that leaves out a required argument) and ed5356b (validate before backing up). The second one matters most: in the deployed copy `mutate()` still copies `library.json` over `library.backup.json` at line 192 before the change is validated, so any rejected write (for example `set_queue_status` with an unknown item) replaces the only undo point with the current state, and the next `undo_last_change` undoes nothing.

How you know: on 2026-11-18, `shasum -a 256` of the deployed file gave `0d7a9a3f…`, the same as `git show 3dfb808:MCP/mcp-server.mjs`; HEAD of branch `ledger-fixes-2026-11-18` (ed5356b) gives `07c8085b…`. `grep -n "copyFileSync(libraryPath, backupPath)"` on the deployed file still finds line 192. The fix itself is covered by `node Tests/mcp-smoke.mjs`, run against a temporary `NEXT_UP_DATA_DIR`.

What closes it: once the branch is merged, Josh copies the repo's `MCP/mcp-server.mjs` over the deployed one (the `cp` line in `scripts/install.sh`, without rebuilding the app if he doesn't want to) and restarts whatever MCP clients have the old server loaded. Nothing was deployed or restarted on 2026-11-18. Close this entry when the two hashes match.

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
