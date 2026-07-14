import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import readline from "node:readline";

const folder = fs.mkdtempSync(path.join(os.tmpdir(), "next-up-mcp-"));
const fixture = {
  schemaVersion: 2, setupComplete: true, profiles: ["A", "B"], subscribedProviders: ["Disney+"],
  collections: [{ id: "queue", name: "Queue", subtitle: "Test", kind: "queue", symbol: "film", accent: "6C63FF", position: 1, orders: [{ id: "queue-order", name: "Queue Order", itemIDs: ["movie"] }] }],
  items: [{ id: "movie", title: "Test Movie", kind: "movie", seriesTitle: null, season: null, episode: null, releaseYear: 2026, airDate: null, runtimeMinutes: 100, providerLinks: [{ id: "link", provider: "Disney+", url: "https://example.com/watch" }] }],
  watchEvents: [], ratings: [], auditLog: []
};
fs.writeFileSync(path.join(folder, "library.json"), JSON.stringify(fixture));

const server = spawn(process.execPath, [path.resolve("MCP/mcp-server.mjs")], { cwd: path.resolve("."), env: { ...process.env, NEXT_UP_DATA_DIR: folder }, stdio: ["pipe", "pipe", "inherit"] });
const lines = readline.createInterface({ input: server.stdout });
const waiting = new Map();
lines.on("line", line => {
  const message = JSON.parse(line);
  const handler = waiting.get(message.id);
  if (handler) { waiting.delete(message.id); handler(message); }
});
let nextId = 1;
function request(method, params = {}) {
  const id = nextId++;
  server.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Timed out: ${method}`)), 3000);
    waiting.set(id, message => { clearTimeout(timeout); message.error ? reject(new Error(message.error.message)) : resolve(message.result); });
  });
}
function call(name, args = {}) { return request("tools/call", { name, arguments: args }).then(result => result.structuredContent); }

try {
  const initialized = await request("initialize", { clientInfo: { name: "automated-smoke", version: "1" } });
  assert.equal(initialized.serverInfo.name, "next-up");
  const listed = await request("tools/list");
  assert.ok(listed.tools.some(tool => tool.name === "import_series"));
  assert.ok(listed.tools.some(tool => tool.name === "import_movie"));
  assert.ok(listed.tools.some(tool => tool.name === "import_movie_series"));
  assert.ok(listed.tools.some(tool => tool.name === "refresh_movie_metadata"));
  assert.ok(listed.tools.some(tool => tool.name === "get_watch_history"));
  assert.ok(listed.tools.some(tool => tool.name === "set_queue_status"));

  assert.equal((await call("what_is_watchable"))[0].items[0].title, "Test Movie");
  assert.equal((await call("set_queue_status", { item: "movie", status: "nextUp" })).queueStatus, "nextUp");
  assert.equal((await call("get_collection", { collection: "Queue" })).queueStatus, "nextUp");
  await call("log_watch", { item: "movie" });
  assert.equal((await call("get_collection", { collection: "Queue" })).completed, true);
  assert.equal((await call("submit_rating", { item: "movie", person: "A", stars: 4.5 })).status, "sealed");
  const sealed = (await call("search_library", { query: "Test Movie" }))[0].rating;
  assert.deepEqual(sealed, { status: "sealed" });
  assert.equal((await call("submit_rating", { item: "movie", person: "B", stars: 3.5 })).status, "revealed");
  const history = await call("get_watch_history", { item: "movie" });
  assert.equal(history.stats.completedWatches, 1);
  assert.equal(history.completions[0].rating.status, "revealed");

  const standalone = await call("add_standalone_movie", { title: "Another Movie", runtimeMinutes: 90, releaseYear: 2025, artworkUrl: "https://example.com/poster.jpg" });
  assert.equal(standalone.collection.name, "Another Movie");
  assert.equal(standalone.collection.kind, "queue");
  assert.equal(standalone.item.artworkURL, "https://example.com/poster.jpg");

  await call("add_collection", { name: "Episodes", kind: "series" });
  const batch = { collection: "Episodes", seriesTitle: "Episodes", season: 1, runtimeMinutes: 24, episodes: [{ number: 1, title: "Pilot" }, { number: 2, title: "Second" }] };
  assert.equal((await call("bulk_add_episodes", batch)).added, 2);
  const repeated = await call("bulk_add_episodes", batch);
  assert.equal(repeated.added, 0);
  assert.equal(repeated.updated, 2);
  assert.equal((await call("get_collection", { collection: "Episodes" })).progress.total, 2);

  await assert.rejects(() => call("attach_provider_link", { item: "movie", provider: "Bad", url: "file:///tmp/not-streaming" }), /http/);
  await assert.rejects(() => call("submit_rating", { item: "movie", person: "A", stars: 4.2 }), /half-star/);
  process.stdout.write("MCP smoke test passed\n");
} finally {
  server.kill();
  fs.rmSync(folder, { recursive: true, force: true });
}
