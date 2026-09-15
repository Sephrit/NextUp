# Issues

## Open

### 1. A tool's advertised `required` list is never enforced, so an empty call reaches the handler — and on 2026-09-14 that wiped the household's streaming services
*Found 2026-09-15 · severity: high · area: MCP/mcp-server.mjs (`tool()` line 141, `callTool()` line 471) · commit: b427c6d · by: deepseek-v4.1-flash*

`tool(name, description, properties, required)` builds `inputSchema.required`, and that is the only thing `required` is used for — the file contains exactly three references to it, two of them in that one line. `callTool(name, args = {})` then dispatches on the tool name alone; nothing compares `args` against the schema before the handler body runs. A caller that omits a required argument therefore reaches handler code with the argument `undefined`, and whether that is survivable is left to each handler.

Most handlers survive by accident. `submit_rating` guards explicitly (`typeof args.stars !== "number"` throws). `log_watch` reaches `findItem(library, args.item)`, which throws `Item not found: undefined`. `set_streaming_services` was the outlier, because its missing value coerced into a *valid* one:

```js
library.subscribedProviders = [...new Set(args.services)];
```

`new Set(undefined)` does not throw — the `Set` constructor treats a non-iterable argument as "no items" — so an empty call wrote `subscribedProviders: []`, a state the app accepts as "this household subscribes to nothing", and `setupComplete: true` on top of it.

How you know: the 2026-09-14 tool-by-tool sweep over the MCP pool (`~/AI/MCP/bin/verify-mcp-tools.py --all`, which probes mutating tools with an empty call and expects a refusal) recorded `set_streaming_services` as a BREACH rather than a guarded refusal, with the answer `{ "streamingServices": [] }`. Reading `~/Library/Application Support/Next Up/library.json` against `library.backup.json` afterwards shows the damage and its extent: `subscribedProviders` empty against eleven services in the backup, with `items` unchanged at 977 in both — the provider list was destroyed and nothing else was touched. The library's own audit log dated it (`verify-mcp-tools | Updated streaming services`, 2026-09-14T23:07:28) and showed no later mutation, so the backup held exactly the pre-wipe state; the entry was restored through `undo_last_change`.

What is fixed, and what is not: `set_streaming_services` now refuses an empty or absent list, and its schema declares `minItems: 1` and `minLength: 1` so a schema-validating client refuses the call before it is sent. That closes the tool, not the entry. The class is open for every other tool, including future ones, because the check is still per-handler arithmetic rather than one validation at dispatch. A fix is to validate `args` against the tool's own `required` list inside `callTool` before dispatch — the list already exists, so it is one lookup and one throw, in one place, and a missing argument fails the same way for every tool.

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
