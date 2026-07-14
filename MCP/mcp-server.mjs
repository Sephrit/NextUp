#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { execFileSync } from "node:child_process";

function defaultDataFolder() {
  if (process.env.NEXT_UP_DATA_DIR) return path.resolve(process.env.NEXT_UP_DATA_DIR);
  const home = os.homedir();
  const candidates = process.platform === "darwin"
    ? [path.join(home, "Library", "Application Support", "com.nextup.watchtracker"), path.join(home, "Library", "Application Support", "Next Up")]
    : process.platform === "win32"
      ? [path.join(process.env.APPDATA || path.join(home, "AppData", "Roaming"), "com.nextup.watchtracker")]
      : [path.join(process.env.XDG_DATA_HOME || path.join(home, ".local", "share"), "com.nextup.watchtracker")];
  return candidates.find(candidate => fs.existsSync(path.join(candidate, "library.json"))) || candidates[0];
}

const folder = defaultDataFolder();
const libraryPath = path.join(folder, "library.json");
const backupPath = path.join(folder, "library.backup.json");
const lockPath = path.join(folder, "library.lock");
let clientName = "MCP client";
let cachedWatchmodeKey = null;

const tools = [
  tool("next_up_summary", "Summarize the Next Up library, collection progress, and the next unwatched item.", {}),
  tool("list_collections", "List collections and their available viewing orders.", {}),
  tool("get_collection", "Get one collection, its progress, ordered items, and revealed ratings. A lone rating remains sealed.", {
    collection: stringProp("Collection id or exact name"),
    order: stringProp("Optional order id or name")
  }, ["collection"]),
  tool("search_library", "Search movies and episodes by title or series.", {
    query: stringProp("Search text")
  }, ["query"]),
  tool("get_watch_history", "Read completed watches, rewatches, partial viewing sessions, notes, resume positions, and revealed ratings.", {
    item: stringProp("Optional item id or exact title"),
    collection: stringProp("Optional collection id or exact name"),
    limit: { type: "integer", minimum: 1, maximum: 500 }
  }),
  tool("add_collection", "Create an empty film, series, or queue collection.", {
    name: stringProp("Collection name"),
    kind: { type: "string", enum: ["films", "series", "queue", "placeholder"] },
    subtitle: stringProp("Optional description")
  }, ["name", "kind"]),
  tool("add_media", "Add a movie, episode, or special to a collection and all of its viewing orders.", {
    collection: stringProp("Collection id or exact name"),
    title: stringProp("Media title"),
    kind: { type: "string", enum: ["movie", "episode", "special"] },
    runtimeMinutes: { type: "integer", minimum: 1, maximum: 1000 },
    releaseYear: { type: "integer", minimum: 1888, maximum: 2200 },
    season: { type: "integer", minimum: 1 },
    episode: { type: "integer", minimum: 1 },
    provider: stringProp("Streaming provider name"),
    providerUrl: stringProp("Provider detail or playback URL")
  }, ["collection", "title", "kind", "runtimeMinutes"]),
  tool("add_standalone_movie", "Add one standalone movie as its own poster-backed Single Movies sidebar entry.", {
    title: stringProp("Movie title"),
    runtimeMinutes: { type: "integer", minimum: 1, maximum: 1000 },
    releaseYear: { type: "integer", minimum: 1888, maximum: 2200 },
    artworkUrl: stringProp("Optional poster image URL"),
    provider: stringProp("Optional streaming provider name"),
    providerUrl: stringProp("Optional provider detail or playback URL")
  }, ["title", "runtimeMinutes"]),
  tool("import_movie", "Search Watchmode using Next Up's Keychain API key and import a movie with title, year, runtime, poster, and current US streaming/rental/purchase links and prices.", {
    query: stringProp("Movie title; be specific when titles are ambiguous"),
    releaseYear: { type: "integer", minimum: 1888, maximum: 2200 }
  }, ["query"]),
  tool("import_movie_series", "Recognize related Watchmode movie results and import them together as one release-order movie series.", {
    query: stringProp("Franchise or movie-series search, such as Harry Potter"),
    name: stringProp("Optional collection name; defaults to the query"),
    maxMovies: { type: "integer", minimum: 2, maximum: 30 }
  }, ["query"]),
  tool("refresh_movie_metadata", "Refresh existing movies in place from Watchmode, including audience rating, critic score, content rating, poster, runtime, and current provider offers. Never creates duplicate titles.", {
    onlyMissingRatings: { type: "boolean", description: "Default true; set false to refresh every movie" }
  }),
  tool("bulk_add_episodes", "Add multiple episodes for one season in a single safe change.", {
    collection: stringProp("Series collection id or exact name"),
    seriesTitle: stringProp("Series title"),
    season: { type: "integer", minimum: 1 },
    runtimeMinutes: { type: "integer", minimum: 1 },
    episodes: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        properties: { number: { type: "integer", minimum: 1 }, title: stringProp("Episode title"), airDate: stringProp("YYYY-MM-DD") },
        required: ["number", "title"],
        additionalProperties: false
      }
    }
  }, ["collection", "seriesTitle", "season", "runtimeMinutes", "episodes"]),
  tool("import_series", "Search TVmaze for a series and automatically import all announced seasons and episodes.", {
    query: stringProp("Series name; be specific when titles are ambiguous")
  }, ["query"]),
  tool("sync_series", "Refresh a TVmaze-linked collection and add newly announced episodes without duplicates.", {
    collection: stringProp("Collection id or exact name")
  }, ["collection"]),
  tool("attach_provider_link", "Add or replace a streaming link on a movie or episode.", {
    item: stringProp("Item id or exact title"), provider: stringProp("Provider name"), url: stringProp("Full URL")
  }, ["item", "provider", "url"]),
  tool("attach_provider_link_to_collection", "Add or replace one confirmed streaming link on every item in a collection.", {
    collection: stringProp("Collection id or exact name"), provider: stringProp("Provider name"), url: stringProp("Full collection or series URL")
  }, ["collection", "provider", "url"]),
  tool("log_watch", "Record a first watch or rewatch for the configured household or group.", {
    item: stringProp("Item id or exact title"), watchedAt: stringProp("Optional ISO-8601 date/time")
  }, ["item"]),
  tool("log_viewing_session", "Record a partial viewing session, resume position, and optional note. Completes the watch only when accumulated minutes reach the runtime.", {
    item: stringProp("Item id or exact title"),
    minutesWatched: { type: "integer", minimum: 1, maximum: 1000 },
    watchedAt: stringProp("Optional ISO-8601 date/time"),
    note: stringProp("Optional session note")
  }, ["item", "minutesWatched"]),
  tool("set_queue_status", "Pin an unwatched title to Watching or Next Up, or remove its pin. Partial sessions automatically use Watching and completed titles automatically leave the queue.", {
    item: stringProp("Item id or exact title"),
    status: { type: "string", enum: ["watching", "nextUp", "none"] }
  }, ["item", "status"]),
  tool("submit_rating", "Submit one profile's half-star rating and optional review signals. The score follows the library's reveal rule.", {
    item: stringProp("Item id or exact title"),
    person: stringProp("One configured profile name"),
    stars: { type: "number", minimum: 0.5, maximum: 5, multipleOf: 0.5 },
    review: stringProp("Optional short review"),
    wouldRewatch: { type: "boolean" },
    favorite: { type: "boolean" }
  }, ["item", "person", "stars"]),
  tool("set_profiles", "Configure one to twelve profiles for a solo viewer, household, or movie club.", {
    profiles: { type: "array", minItems: 1, maxItems: 12, uniqueItems: true, items: { type: "string", minLength: 1 } },
    first: stringProp("Legacy first profile name"), second: stringProp("Legacy second profile name")
  }),
  tool("set_streaming_services", "Set the streaming services currently available to the household.", {
    services: { type: "array", uniqueItems: true, items: { type: "string", enum: ["Disney+", "Prime Video", "Peacock", "Paramount+", "Netflix", "Hulu", "Max", "Apple TV+", "Crunchyroll", "AMC+", "STARZ", "MGM+", "Shudder", "BritBox", "The Criterion Channel", "Tubi", "The Roku Channel", "Pluto TV", "Plex", "Kanopy", "Hoopla"] } }
  }, ["services"]),
  tool("what_is_watchable", "List unwatched library items with confirmed links on the household's selected streaming services.", {
    includeWatched: { type: "boolean" }, provider: stringProp("Optional selected provider name")
  }),
  tool("recent_activity", "List recent app and harness changes.", { limit: { type: "integer", minimum: 1, maximum: 100 } }),
  tool("undo_last_change", "Undo the most recent library mutation by restoring the automatic backup.", {})
];

function tool(name, description, properties, required = []) {
  return { name, description, inputSchema: { type: "object", properties, required, additionalProperties: false } };
}
function stringProp(description) { return { type: "string", description }; }
function id() { return crypto.randomUUID(); }
function now() { return Date.now() / 1000; }
function slug(text) { return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }
function movieSearchName(item) {
  const aliases = {
    "sw-new-hope": "Star Wars: Episode IV - A New Hope",
    "sw-empire": "Star Wars: Episode V - The Empire Strikes Back",
    "sw-return": "Star Wars: Episode VI - Return of the Jedi",
    "sw-phantom": "Star Wars: Episode I - The Phantom Menace",
    "sw-clones": "Star Wars: Episode II - Attack of the Clones",
    "sw-sith": "Star Wars: Episode III - Revenge of the Sith",
    "sw-force": "Star Wars: Episode VII - The Force Awakens",
    "sw-last-jedi": "Star Wars: Episode VIII - The Last Jedi",
    "sw-rise": "Star Wars: Episode IX - The Rise of Skywalker",
    "sw-rogue": "Rogue One: A Star Wars Story",
    "sw-solo": "Solo: A Star Wars Story",
    "twilight-4": "The Twilight Saga: Breaking Dawn - Part 1",
    "twilight-5": "The Twilight Saga: Breaking Dawn - Part 2"
  };
  return aliases[item.id] || item.title;
}
function httpURL(value) {
  const parsed = new URL(value);
  if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("Streaming links must use http:// or https://.");
  return parsed;
}

function readLibrary() {
  if (!fs.existsSync(libraryPath)) throw new Error("Next Up has not created its library yet. Open the desktop app once, then retry.");
  return JSON.parse(fs.readFileSync(libraryPath, "utf8"));
}

function acquireLock() {
  fs.mkdirSync(folder, { recursive: true });
  for (let attempt = 0; attempt < 100; attempt++) {
    try { fs.mkdirSync(lockPath); return; }
    catch (error) {
      if (error.code !== "EEXIST") throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
    }
  }
  throw new Error("Next Up library is busy. Retry in a moment.");
}

function mutate(action, change) {
  acquireLock();
  try {
    const library = readLibrary();
    fs.copyFileSync(libraryPath, backupPath);
    const result = change(library);
    library.auditLog ||= [];
    library.auditLog.push({ id: id(), timestamp: now(), source: clientName, action });
    if (library.auditLog.length > 250) library.auditLog = library.auditLog.slice(-250);
    const temporary = `${libraryPath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(library, null, 2));
    fs.renameSync(temporary, libraryPath);
    return result;
  } finally {
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

function findCollection(library, value) {
  const needle = String(value).toLowerCase();
  const matches = library.collections.filter(c => c.id.toLowerCase() === needle || c.name.toLowerCase() === needle);
  if (matches.length !== 1) throw new Error(matches.length ? `Collection is ambiguous: ${value}` : `Collection not found: ${value}`);
  return matches[0];
}

function findItem(library, value) {
  const needle = String(value).toLowerCase();
  const exact = library.items.filter(item => item.id.toLowerCase() === needle || item.title.toLowerCase() === needle);
  if (exact.length !== 1) throw new Error(exact.length ? `Item title is ambiguous; use its id: ${value}` : `Item not found: ${value}`);
  return exact[0];
}

function orderFor(collection, value) {
  if (!value) return collection.orders[0];
  const needle = String(value).toLowerCase();
  const order = collection.orders.find(o => o.id.toLowerCase() === needle || o.name.toLowerCase() === needle);
  if (!order) throw new Error(`Viewing order not found: ${value}`);
  return order;
}

function watchEventsFor(library, itemId) { return library.watchEvents.filter(e => e.itemID === itemId).sort((a, b) => b.watchedAt - a.watchedAt); }
function latestWatch(library, itemId) { return watchEventsFor(library, itemId)[0]; }
function currentPosition(library, itemId) {
  const completedAt = latestWatch(library, itemId)?.watchedAt ?? -Infinity;
  const item = library.items.find(candidate => candidate.id === itemId);
  const minutes = (library.viewingSessions || []).filter(session => session.itemID === itemId && session.watchedAt > completedAt).reduce((sum, session) => sum + session.minutesWatched, 0);
  return Math.min(item?.runtimeMinutes || 0, Math.max(0, minutes));
}
function visibleRatings(library, itemId) {
  const event = latestWatch(library, itemId);
  if (!event) return { status: "unwatched" };
  return visibleRatingsForEvent(library, event);
}
function visibleRatingsForEvent(library, event) {
  const ratings = library.ratings.filter(r => r.watchEventID === event.id);
  if (!library.profiles.every(person => ratings.some(r => r.person === person))) return { status: ratings.length ? "sealed" : "not-rated" };
  return { status: "revealed", ratings: Object.fromEntries(ratings.map(r => [r.person, r.stars])) };
}
function effectiveQueueStatus(library, item) {
  if (latestWatch(library, item.id)) return null;
  if (currentPosition(library, item.id) > 0) return "watching";
  return item.queueStatus || null;
}
function priorityRank(library, item) {
  const status = effectiveQueueStatus(library, item);
  return status === "watching" ? 0 : status === "nextUp" ? 1 : 2;
}

function addStandaloneMovieData(library, movie) {
  const cleanTitle = String(movie.title || "").trim();
  if (!cleanTitle) throw new Error("Movie title cannot be empty.");
  if (!Number.isInteger(movie.runtimeMinutes) || movie.runtimeMinutes < 1) throw new Error("runtimeMinutes must be a positive whole number.");
  const preferredItemId = movie.watchmodeID ? `watchmode-movie-${movie.watchmodeID}` : null;
  let item = preferredItemId ? library.items.find(candidate => candidate.id === preferredItemId) : null;
  let collection = item && library.collections.find(c => c.kind === "queue" && c.orders.some(order => order.itemIDs.includes(item.id)));
  if (!collection) collection = library.collections.find(c => c.kind === "queue" && c.name.toLowerCase() === cleanTitle.toLowerCase());
  if (!item) item = collection?.orders.flatMap(order => order.itemIDs).map(itemId => library.items.find(candidate => candidate.id === itemId)).find(Boolean);
  if (!item) {
    const itemId = preferredItemId || `${slug(cleanTitle)}-${id().slice(0, 6)}`;
    item = { id: itemId, title: cleanTitle, kind: "movie", seriesTitle: null, season: null, episode: null, releaseYear: movie.releaseYear ?? null, airDate: null, runtimeMinutes: movie.runtimeMinutes, providerLinks: movie.providerLinks || [], artworkURL: movie.artworkURL || null, publicRating: movie.publicRating ?? null, criticScore: movie.criticScore ?? null, contentRating: movie.contentRating ?? null };
    library.items.push(item);
  } else {
    item.title = cleanTitle; item.runtimeMinutes = movie.runtimeMinutes; item.releaseYear = movie.releaseYear ?? item.releaseYear;
    if (movie.artworkURL) item.artworkURL = movie.artworkURL;
    if (movie.providerLinks?.length) item.providerLinks = movie.providerLinks;
    if (movie.publicRating != null) item.publicRating = movie.publicRating;
    if (movie.criticScore != null) item.criticScore = movie.criticScore;
    if (movie.contentRating != null) item.contentRating = movie.contentRating;
  }
  if (!collection) {
    const collectionId = `single-movie-${item.id}`;
    collection = { id: collectionId, name: cleanTitle, subtitle: movie.releaseYear ? `Standalone movie · ${movie.releaseYear}` : "Standalone movie", kind: "queue", symbol: "popcorn.fill", accent: "6C63FF", position: Math.max(0, ...library.collections.map(c => c.position)) + 1, orders: [{ id: `${collectionId}-order`, name: "Movie", itemIDs: [item.id] }], artworkURL: movie.artworkURL || null };
    library.collections.push(collection);
  } else {
    collection.name = cleanTitle;
    collection.subtitle = movie.releaseYear ? `Standalone movie · ${movie.releaseYear}` : "Standalone movie";
    collection.symbol = "popcorn.fill";
    if (movie.artworkURL) collection.artworkURL = movie.artworkURL;
    if (!collection.orders.some(order => order.itemIDs.includes(item.id))) {
      if (!collection.orders.length) collection.orders.push({ id: `${collection.id}-order`, name: "Movie", itemIDs: [] });
      collection.orders[0].itemIDs.push(item.id);
    }
  }
  return { collection, item };
}

function watchmodeKey() {
  if (cachedWatchmodeKey) return cachedWatchmodeKey;
  if (process.env.NEXTUP_WATCHMODE_KEY?.trim()) {
    cachedWatchmodeKey = process.env.NEXTUP_WATCHMODE_KEY.trim();
    return cachedWatchmodeKey;
  }
  if (process.platform !== "darwin") {
    throw new Error("Set NEXTUP_WATCHMODE_KEY for Watchmode-powered MCP tools, or use tools that do not require Watchmode.");
  }
  try {
    for (const service of ["com.nextup.watchtracker.watchmode", "com.nextup.app.watchmode"]) {
      try {
        cachedWatchmodeKey = execFileSync("/usr/bin/security", ["find-generic-password", "-s", service, "-a", "api-key", "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
        if (cachedWatchmodeKey) return cachedWatchmodeKey;
      } catch {}
    }
    throw new Error("missing credential");
  } catch {
    throw new Error("No Watchmode key is available. Save one in Next Up Settings first.");
  }
}

async function watchmodeFetch(pathname, params = {}) {
  const url = new URL(`https://api.watchmode.com/v1/${pathname}`);
  Object.entries(params).forEach(([key, value]) => { if (value != null) url.searchParams.set(key, String(value)); });
  const response = await fetch(url, { headers: { "X-API-Key": watchmodeKey(), "User-Agent": "Next-Up/1.0" } });
  if (response.status === 401 || response.status === 403) { cachedWatchmodeKey = null; throw new Error("Watchmode rejected the saved API key."); }
  if (response.status === 429) throw new Error("Watchmode's request limit was reached. Try again in a minute.");
  if (!response.ok) throw new Error(`Watchmode returned HTTP ${response.status}.`);
  return response.json();
}

function providerName(name) {
  const providers = {
    "disney+": "Disney+", "disney plus": "Disney+",
    "prime video": "Prime Video", "amazon prime video": "Prime Video",
    "peacock": "Peacock", "peacock premium": "Peacock",
    "paramount+": "Paramount+", "paramount plus": "Paramount+",
    "netflix": "Netflix", "hulu": "Hulu", "max": "Max", "hbo max": "Max",
    "appletv+": "Apple TV+", "apple tv+": "Apple TV+", "apple tv plus": "Apple TV+",
    "tubi": "Tubi", "tubi tv": "Tubi", "the roku channel": "The Roku Channel", "roku channel": "The Roku Channel",
    "amazon": "Prime Video", "crunchyroll": "Crunchyroll", "crunchyroll premium": "Crunchyroll",
    "amc+": "AMC+", "amc plus": "AMC+", "starz": "STARZ", "mgm+": "MGM+", "mgm plus": "MGM+",
    "shudder": "Shudder", "britbox": "BritBox", "the criterion channel": "The Criterion Channel", "criterion channel": "The Criterion Channel",
    "pluto tv": "Pluto TV", "plex": "Plex", "kanopy": "Kanopy", "hoopla": "Hoopla"
  };
  return providers[String(name || "").toLowerCase().trim()] || null;
}

function watchmodeMovieFromDetails(match, details) {
  if (details.type !== "movie" && details.type !== "tv_movie") throw new Error("Watchmode did not return a movie for this result.");
  const links = new Map();
  for (const source of details.sources || []) {
    const provider = providerName(source.name);
    if (!["sub", "free", "rent", "buy", "purchase"].includes(source.type) || (source.region && source.region !== "US") || !provider || !source.web_url) continue;
    const accessType = source.type === "purchase" ? "buy" : source.type;
    const key = `${provider.toLowerCase()}|${accessType}|${source.format || ""}`;
    try {
      const candidate = { id: id(), provider, url: httpURL(source.web_url).href, accessType, price: source.price ?? null, format: source.format ?? null };
      const existing = links.get(key);
      if (!existing || candidate.price == null || existing.price == null || candidate.price < existing.price) links.set(key, candidate);
    } catch {}
  }
  return {
    watchmodeID: match.id,
    title: details.title || match.name,
    releaseYear: details.year || match.year || null,
    runtimeMinutes: Math.max(1, details.runtime_minutes || 120),
    artworkURL: details.posterMedium || details.poster || details.posterLarge || match.image_url || null,
    providerLinks: [...links.values()],
    publicRating: details.user_rating ?? null,
    criticScore: details.critic_score ?? null,
    contentRating: details.us_rating ?? null
  };
}

function addMovieSeriesData(library, name, movies) {
  const cleanName = String(name || "").trim();
  if (!cleanName || movies.length < 2) throw new Error("A movie series needs a name and at least two films.");
  let collection = library.collections.find(candidate => candidate.kind === "films" && candidate.name.toLowerCase() === cleanName.toLowerCase());
  if (!collection) {
    const collectionId = `movie-series-${slug(cleanName)}-${id().slice(0, 6)}`;
    collection = { id: collectionId, name: cleanName, subtitle: "Movie series · imported from Watchmode", kind: "films", symbol: "film.stack.fill", accent: "6C63FF", position: Math.max(0, ...library.collections.map(c => c.position)) + 1, orders: [{ id: `${collectionId}-release`, name: "Release Order", itemIDs: [] }], artworkURL: movies.find(movie => movie.artworkURL)?.artworkURL || null };
    library.collections.push(collection);
  }
  const itemIDs = [];
  for (const movie of movies.sort((left, right) => (left.releaseYear || 0) - (right.releaseYear || 0) || left.title.localeCompare(right.title))) {
    const preferredId = `watchmode-movie-${movie.watchmodeID}`;
    let item = library.items.find(candidate => candidate.id === preferredId)
      || library.items.find(candidate => candidate.kind === "movie" && candidate.title.toLowerCase() === movie.title.toLowerCase() && (!candidate.releaseYear || !movie.releaseYear || candidate.releaseYear === movie.releaseYear));
    if (!item) {
      item = { id: preferredId, title: movie.title, kind: "movie", seriesTitle: cleanName, season: null, episode: null, releaseYear: movie.releaseYear, airDate: null, runtimeMinutes: movie.runtimeMinutes, providerLinks: movie.providerLinks, artworkURL: movie.artworkURL, publicRating: movie.publicRating, criticScore: movie.criticScore, contentRating: movie.contentRating };
      library.items.push(item);
    } else {
      item.title = movie.title; item.runtimeMinutes = movie.runtimeMinutes; item.releaseYear = movie.releaseYear; item.artworkURL = movie.artworkURL; item.providerLinks = movie.providerLinks; item.publicRating = movie.publicRating; item.criticScore = movie.criticScore; item.contentRating = movie.contentRating; item.seriesTitle ||= cleanName;
    }
    itemIDs.push(item.id);
  }
  const groupedIds = new Set(itemIDs);
  library.collections = library.collections.filter(candidate => candidate === collection || candidate.kind !== "queue" || !candidate.orders.flatMap(order => order.itemIDs).every(itemId => groupedIds.has(itemId)));
  collection.orders ||= [];
  if (!collection.orders.length) collection.orders.push({ id: `${collection.id}-release`, name: "Release Order", itemIDs: [] });
  collection.orders[0].itemIDs = [...new Set(itemIDs)];
  collection.subtitle = `${collection.orders[0].itemIDs.length} films · release order`;
  collection.artworkURL ||= movies.find(movie => movie.artworkURL)?.artworkURL || null;
  return { collection, movies: collection.orders[0].itemIDs.length };
}

function importTVMazeData(library, show, episodes) {
  let collection = library.collections.find(c => c.externalSource?.provider === "TVmaze" && c.externalSource?.id === String(show.id));
  if (!collection) collection = library.collections.find(c => c.name.toLowerCase() === show.name.toLowerCase());
  if (!collection) {
    const collectionId = `${slug(show.name)}-${id().slice(0,6)}`;
    collection = { id: collectionId, name: show.name, subtitle: "Imported from TVmaze", kind: "series", symbol: "play.rectangle.on.rectangle", accent: "4BBE84", position: Math.max(0, ...library.collections.map(c => c.position)) + 1, orders: [{ id: `${collectionId}-episodes`, name: "Episode Order", itemIDs: [] }] };
    library.collections.push(collection);
  }
  collection.externalSource = { provider: "TVmaze", id: String(show.id), url: show.url || null, lastSyncedAt: now() };
  collection.artworkURL = show.image?.medium || null;
  collection.subtitle = `${new Set(episodes.map(e => e.season).filter(Boolean)).size} seasons · synced from TVmaze`;
  const order = collection.orders[0] || { id: `${collection.id}-episodes`, name: "Episode Order", itemIDs: [] };
  if (!collection.orders.length) collection.orders.push(order);
  for (const episode of episodes) {
    if (!episode.season || !episode.number) continue;
    let item = order.itemIDs.map(itemId => library.items.find(i => i.id === itemId)).find(i => i?.kind === "episode" && i.season === episode.season && i.episode === episode.number);
    if (item) {
      item.title = episode.name; item.airDate = episode.airdate || null; item.releaseYear = episode.airdate ? Number(episode.airdate.slice(0,4)) : null;
      if (episode.runtime) item.runtimeMinutes = episode.runtime;
    } else {
      const itemId = `tvmaze-episode-${episode.id}`;
      item = library.items.find(i => i.id === itemId);
      if (!item) {
        item = { id: itemId, title: episode.name, kind: "episode", seriesTitle: show.name, season: episode.season, episode: episode.number, releaseYear: episode.airdate ? Number(episode.airdate.slice(0,4)) : null, airDate: episode.airdate || null, runtimeMinutes: episode.runtime || 30, providerLinks: [] };
        library.items.push(item);
      }
      if (!order.itemIDs.includes(itemId)) order.itemIDs.push(itemId);
    }
  }
  order.itemIDs.sort((leftId, rightId) => {
    const left = library.items.find(i => i.id === leftId), right = library.items.find(i => i.id === rightId);
    if (!left?.season) return -1; if (!right?.season) return 1;
    return left.season - right.season || (left.episode || 0) - (right.episode || 0);
  });
  return { collection: collection.name, seasons: new Set(episodes.map(e => e.season).filter(Boolean)).size, episodes: episodes.length };
}

function collectionView(library, collection, orderValue, includeItems = true) {
  const order = orderFor(collection, orderValue);
  const items = order.itemIDs.map(itemId => library.items.find(item => item.id === itemId)).filter(Boolean);
  const watched = items.filter(item => watchEventsFor(library, item.id).length);
  const services = library.subscribedProviders || [];
  const watchable = items.filter(item => item.providerLinks.some(link => services.some(service => service.toLowerCase() === link.provider.toLowerCase())));
  const positions = new Map(items.map((item, index) => [item.id, index]));
  const unwatched = items.filter(item => !watchEventsFor(library, item.id).length).sort((left, right) =>
    priorityRank(library, left) - priorityRank(library, right)
      || ((right.pinnedAt || 0) - (left.pinnedAt || 0))
      || positions.get(left.id) - positions.get(right.id)
  );
  const next = unwatched[0];
  const collectionStatus = unwatched.some(item => effectiveQueueStatus(library, item) === "watching") ? "watching"
    : unwatched.some(item => effectiveQueueStatus(library, item) === "nextUp") ? "nextUp" : null;
  const base = {
    id: collection.id, name: collection.name, subtitle: collection.subtitle, kind: collection.kind,
    order: { id: order.id, name: order.name },
    progress: { watched: watched.length, total: items.length, percent: items.length ? Math.round(watched.length / items.length * 100) : 0 },
    completed: items.length > 0 && watched.length === items.length,
    queueStatus: collectionStatus,
    watchableOnSelectedServices: watchable.length,
    next: next ? { id: next.id, title: next.title, runtimeMinutes: next.runtimeMinutes, resumeAtMinutes: currentPosition(library, next.id), remainingMinutes: Math.max(0, next.runtimeMinutes - currentPosition(library, next.id)), season: next.season, episode: next.episode } : null
  };
  if (includeItems) base.items = items.map(item => {
    const position = currentPosition(library, item.id);
    const sessions = (library.viewingSessions || []).filter(session => session.itemID === item.id);
    return { ...item, effectiveQueueStatus: effectiveQueueStatus(library, item), watchCount: watchEventsFor(library, item.id).length, rating: visibleRatings(library, item.id), resumeAtMinutes: position, remainingMinutes: watchEventsFor(library, item.id).length ? 0 : Math.max(0, item.runtimeMinutes - position), viewingSessionCount: sessions.length, totalSessionMinutes: sessions.reduce((sum, session) => sum + session.minutesWatched, 0) };
  });
  return base;
}

async function callTool(name, args = {}) {
  if (name === "next_up_summary") {
    const library = readLibrary();
    const watchedItemIds = new Set(library.watchEvents.map(event => event.itemID));
    const sessions = library.viewingSessions || [];
    return {
      profiles: library.profiles,
      streamingServices: library.subscribedProviders || [],
      stats: {
        totalTitles: library.items.length,
        watchedTitles: watchedItemIds.size,
        percentWatched: library.items.length ? Math.round(watchedItemIds.size / library.items.length * 1000) / 10 : 0,
        completedWatches: library.watchEvents.length,
        rewatches: Math.max(0, library.watchEvents.length - watchedItemIds.size),
        viewingSessions: sessions.length,
        totalSessionMinutes: sessions.reduce((sum, session) => sum + session.minutesWatched, 0),
        completedCollections: library.collections.filter(collection => {
          const ids = collection.orders[0]?.itemIDs || [];
          return ids.length && ids.every(itemId => watchedItemIds.has(itemId));
        }).length,
        watching: library.items.filter(item => effectiveQueueStatus(library, item) === "watching").length,
        pinnedNextUp: library.items.filter(item => effectiveQueueStatus(library, item) === "nextUp").length
      },
      collections: library.collections.sort((a,b) => a.position-b.position).map(c => collectionView(library, c, null, false))
    };
  }
  if (name === "list_collections") {
    const library = readLibrary();
    return library.collections.sort((a,b) => a.position-b.position).map(c => ({ ...collectionView(library, c, null, false), orders: c.orders.map(o => ({ id: o.id, name: o.name })) }));
  }
  if (name === "get_collection") {
    const library = readLibrary(); return collectionView(library, findCollection(library, args.collection), args.order);
  }
  if (name === "search_library") {
    const library = readLibrary(); const needle = args.query.toLowerCase();
    return library.items.filter(i => i.title.toLowerCase().includes(needle) || (i.seriesTitle || "").toLowerCase().includes(needle)).slice(0, 100).map(i => ({ ...i, effectiveQueueStatus: effectiveQueueStatus(library, i), watchCount: watchEventsFor(library, i.id).length, rating: visibleRatings(library, i.id) }));
  }
  if (name === "get_watch_history") {
    const library = readLibrary();
    let allowedItemIds = new Set(library.items.map(item => item.id));
    if (args.collection) {
      const collection = findCollection(library, args.collection);
      allowedItemIds = new Set(collection.orders.flatMap(order => order.itemIDs));
    }
    if (args.item) {
      const item = findItem(library, args.item);
      allowedItemIds = new Set([item.id]);
    }
    const itemFor = itemId => library.items.find(item => item.id === itemId);
    const limit = args.limit || 100;
    const completions = library.watchEvents.filter(event => allowedItemIds.has(event.itemID)).sort((a, b) => b.watchedAt - a.watchedAt);
    const sessions = (library.viewingSessions || []).filter(session => allowedItemIds.has(session.itemID)).sort((a, b) => b.watchedAt - a.watchedAt);
    const uniqueTitles = new Set(completions.map(event => event.itemID));
    return {
      stats: {
        completedWatches: completions.length,
        uniqueTitlesWatched: uniqueTitles.size,
        rewatches: Math.max(0, completions.length - uniqueTitles.size),
        viewingSessions: sessions.length,
        totalSessionMinutes: sessions.reduce((sum, session) => sum + session.minutesWatched, 0)
      },
      completions: completions.slice(0, limit).map(event => {
        const item = itemFor(event.itemID);
        return { id: event.id, itemID: event.itemID, title: item?.title, seriesTitle: item?.seriesTitle, season: item?.season, episode: item?.episode, watchedAt: new Date(event.watchedAt * 1000).toISOString(), source: event.source, rating: visibleRatingsForEvent(library, event) };
      }),
      sessions: sessions.slice(0, limit).map(session => {
        const item = itemFor(session.itemID);
        return { id: session.id, itemID: session.itemID, title: item?.title, seriesTitle: item?.seriesTitle, season: item?.season, episode: item?.episode, watchedAt: new Date(session.watchedAt * 1000).toISOString(), minutesWatched: session.minutesWatched, endingPositionMinutes: session.endingPositionMinutes, remainingMinutes: Math.max(0, (item?.runtimeMinutes || 0) - session.endingPositionMinutes), completed: Boolean(session.watchEventID), note: session.note, source: session.source };
      })
    };
  }
  if (name === "add_collection") return mutate(`Added collection: ${args.name}`, library => {
    const cleanName = String(args.name || "").trim();
    if (!cleanName) throw new Error("Collection name cannot be empty.");
    if (library.collections.some(c => c.name.toLowerCase() === cleanName.toLowerCase())) throw new Error("A collection with that name already exists.");
    const collectionId = `${slug(cleanName)}-${id().slice(0, 6)}`;
    const collection = { id: collectionId, name: cleanName, subtitle: args.subtitle || "Added by a harness", kind: args.kind, symbol: args.kind === "series" ? "play.rectangle.on.rectangle" : "film.stack", accent: "6C63FF", position: Math.max(0, ...library.collections.map(c => c.position)) + 1, orders: [{ id: `${collectionId}-default`, name: args.kind === "series" ? "Episode Order" : "Custom Order", itemIDs: [] }] };
    library.collections.push(collection); return collection;
  });
  if (name === "add_media") return mutate(`Added media: ${args.title}`, library => {
    const collection = findCollection(library, args.collection);
    const cleanTitle = String(args.title || "").trim();
    if (!cleanTitle) throw new Error("Media title cannot be empty.");
    if (!Number.isInteger(args.runtimeMinutes) || args.runtimeMinutes < 1) throw new Error("runtimeMinutes must be a positive whole number.");
    const itemId = `${slug(cleanTitle)}-${id().slice(0, 6)}`;
    const links = args.providerUrl ? [{ id: id(), provider: args.provider || "Streaming", url: httpURL(args.providerUrl).href }] : [];
    const item = { id: itemId, title: cleanTitle, kind: args.kind, seriesTitle: collection.name, season: args.season ?? null, episode: args.episode ?? null, releaseYear: args.releaseYear ?? null, airDate: null, runtimeMinutes: args.runtimeMinutes, providerLinks: links };
    library.items.push(item); collection.orders.forEach(o => o.itemIDs.push(itemId)); return item;
  });
  if (name === "add_standalone_movie") return mutate(`Added standalone movie: ${args.title}`, library => {
    const providerLinks = args.providerUrl ? [{ id: id(), provider: args.provider || "Streaming", url: httpURL(args.providerUrl).href }] : [];
    const artworkURL = args.artworkUrl ? httpURL(args.artworkUrl).href : null;
    return addStandaloneMovieData(library, { title: args.title, runtimeMinutes: args.runtimeMinutes, releaseYear: args.releaseYear, artworkURL, providerLinks });
  });
  if (name === "import_movie") {
    const clean = String(args.query || "").trim();
    if (!clean) throw new Error("Movie search cannot be empty.");
    const search = await watchmodeFetch("autocomplete-search/", { search_value: clean, search_type: 3 });
    const candidates = (search.results || []).filter(result => result.type === "movie" || result.type === "tv_movie");
    if (!candidates.length) throw new Error(`No Watchmode movie matched: ${clean}`);
    const normalized = value => String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    const wanted = normalized(clean);
    candidates.sort((left, right) => {
      const score = candidate => (normalized(candidate.name) === wanted ? 100 : normalized(candidate.name).includes(wanted) ? 40 : 0) + (args.releaseYear && candidate.year === args.releaseYear ? 50 : 0);
      return score(right) - score(left);
    });
    const match = candidates[0];
    const details = await watchmodeFetch(`title/${match.id}/details/`, { append_to_response: "sources", regions: "US" });
    const movie = watchmodeMovieFromDetails(match, details);
    return mutate(`Imported movie: ${movie.title}`, library => addStandaloneMovieData(library, movie));
  }
  if (name === "import_movie_series") {
    const clean = String(args.query || "").trim();
    if (!clean) throw new Error("Movie-series search cannot be empty.");
    const search = await watchmodeFetch("autocomplete-search/", { search_value: clean, search_type: 3 });
    const normalized = value => String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    const wanted = normalized(clean);
    const all = (search.results || []).filter(result => result.type === "movie" || result.type === "tv_movie");
    const related = all.filter(result => normalized(result.name).includes(wanted));
    const matches = (related.length >= 2 ? related : all).slice(0, args.maxMovies || 20);
    if (matches.length < 2) throw new Error(`Watchmode did not find enough related movies for: ${clean}`);
    const movies = [];
    for (const match of matches) {
      const details = await watchmodeFetch(`title/${match.id}/details/`, { append_to_response: "sources", regions: "US" });
      movies.push(watchmodeMovieFromDetails(match, details));
    }
    const name = String(args.name || clean).trim();
    return mutate(`Imported movie series: ${name}`, library => addMovieSeriesData(library, name, movies));
  }
  if (name === "refresh_movie_metadata") {
    const snapshot = readLibrary();
    const onlyMissing = args.onlyMissingRatings !== false;
    const candidates = snapshot.items.filter(item => item.kind === "movie" && (!onlyMissing || item.publicRating == null));
    const updates = [], warnings = [];
    const normalized = value => String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    for (const item of candidates) {
      try {
        let match;
        const known = /^watchmode-movie-(\d+)$/.exec(item.id);
        if (known) {
          match = { id: Number(known[1]), name: item.title, year: item.releaseYear, image_url: item.artworkURL };
        } else {
          const searchName = movieSearchName(item);
          const search = await watchmodeFetch("autocomplete-search/", { search_value: searchName, search_type: 3 });
          const movieResults = (search.results || []).filter(result => result.type === "movie" || result.type === "tv_movie");
          movieResults.sort((left, right) => {
            const score = candidate => (normalized(candidate.name) === normalized(searchName) ? 140 : normalized(candidate.name).includes(normalized(searchName)) ? 45 : 0)
              + (item.releaseYear > 1800 && candidate.year === item.releaseYear ? 80 : 0);
            return score(right) - score(left);
          });
          match = movieResults[0];
        }
        if (!match) { warnings.push(`No Watchmode match for ${item.title}`); continue; }
        const details = await watchmodeFetch(`title/${match.id}/details/`, { append_to_response: "sources", regions: "US" });
        updates.push({ itemID: item.id, movie: watchmodeMovieFromDetails(match, details) });
      } catch (error) {
        warnings.push(`${item.title}: ${error.message}`);
      }
    }
    if (!updates.length) return { checked: candidates.length, updated: 0, warnings };
    return mutate(`Refreshed metadata for ${updates.length} movies`, library => {
      for (const update of updates) {
        const item = library.items.find(candidate => candidate.id === update.itemID);
        if (!item) continue;
        item.runtimeMinutes = update.movie.runtimeMinutes;
        if (!(item.releaseYear > 1800)) item.releaseYear = update.movie.releaseYear ?? item.releaseYear;
        item.artworkURL = update.movie.artworkURL || item.artworkURL;
        item.publicRating = update.movie.publicRating;
        item.criticScore = update.movie.criticScore;
        item.contentRating = update.movie.contentRating;
        if (update.movie.providerLinks.length) item.providerLinks = update.movie.providerLinks;
        for (const collection of library.collections.filter(collection => collection.orders.some(order => order.itemIDs.includes(item.id)))) {
          collection.artworkURL ||= item.artworkURL;
        }
      }
      return { checked: candidates.length, updated: updates.length, warnings };
    });
  }
  if (name === "bulk_add_episodes") return mutate(`Added ${args.episodes.length} episodes to season ${args.season}`, library => {
    const collection = findCollection(library, args.collection); const added = [], updated = [];
    const collectionItemIds = new Set(collection.orders.flatMap(order => order.itemIDs));
    for (const episode of args.episodes) {
      const existing = library.items.find(item => collectionItemIds.has(item.id) && item.kind === "episode" && item.season === args.season && item.episode === episode.number);
      if (existing) {
        existing.title = episode.title.trim(); existing.airDate = episode.airDate || null;
        existing.releaseYear = episode.airDate ? Number(episode.airDate.slice(0,4)) : existing.releaseYear;
        existing.runtimeMinutes = args.runtimeMinutes; updated.push(existing); continue;
      }
      const itemId = `${slug(args.seriesTitle)}-s${args.season}e${episode.number}-${id().slice(0,4)}`;
      const item = { id: itemId, title: episode.title, kind: "episode", seriesTitle: args.seriesTitle, season: args.season, episode: episode.number, releaseYear: episode.airDate ? Number(episode.airDate.slice(0,4)) : null, airDate: episode.airDate || null, runtimeMinutes: args.runtimeMinutes, providerLinks: [] };
      library.items.push(item); collection.orders.forEach(o => o.itemIDs.push(itemId)); added.push(item);
    }
    collection.orders.forEach(order => order.itemIDs.sort((leftId, rightId) => {
      const left = library.items.find(item => item.id === leftId), right = library.items.find(item => item.id === rightId);
      return (left?.season || 0) - (right?.season || 0) || (left?.episode || 0) - (right?.episode || 0);
    }));
    return { added: added.length, updated: updated.length, items: [...added, ...updated] };
  });
  if (name === "import_series") {
    const url = `https://api.tvmaze.com/singlesearch/shows?q=${encodeURIComponent(args.query)}&embed=episodes`;
    const response = await fetch(url, { headers: { "User-Agent": "Next-Up/1.0 (https://github.com/)" } });
    if (!response.ok) throw new Error(`TVmaze search failed with HTTP ${response.status}.`);
    const show = await response.json(); const episodes = show._embedded?.episodes || [];
    return mutate(`Imported series: ${show.name}`, library => importTVMazeData(library, show, episodes));
  }
  if (name === "sync_series") {
    const library = readLibrary(); const collection = findCollection(library, args.collection);
    if (collection.externalSource?.provider !== "TVmaze") throw new Error("This collection is not linked to TVmaze. Use import_series first.");
    const response = await fetch(`https://api.tvmaze.com/shows/${collection.externalSource.id}?embed=episodes`, { headers: { "User-Agent": "Next-Up/1.0 (https://github.com/)" } });
    if (!response.ok) throw new Error(`TVmaze sync failed with HTTP ${response.status}.`);
    const show = await response.json(); const episodes = show._embedded?.episodes || [];
    return mutate(`Synced series: ${show.name}`, current => importTVMazeData(current, show, episodes));
  }
  if (name === "attach_provider_link") return mutate(`Attached ${args.provider} link`, library => {
    const item = findItem(library, args.item); const parsed = httpURL(args.url);
    item.providerLinks = item.providerLinks.filter(link => link.provider.toLowerCase() !== args.provider.toLowerCase());
    item.providerLinks.push({ id: id(), provider: args.provider, url: parsed.href }); return item;
  });
  if (name === "attach_provider_link_to_collection") return mutate(`Attached ${args.provider} to collection`, library => {
    const collection = findCollection(library, args.collection); const parsed = httpURL(args.url);
    const itemIds = new Set(collection.orders.flatMap(order => order.itemIDs)); let updated = 0;
    library.items.filter(item => itemIds.has(item.id)).forEach(item => {
      item.providerLinks = item.providerLinks.filter(link => link.provider.toLowerCase() !== args.provider.toLowerCase());
      item.providerLinks.push({ id: id(), provider: args.provider, url: parsed.href }); updated++;
    });
    return { collection: collection.name, provider: args.provider, updated };
  });
  if (name === "log_watch") return mutate("Logged a watch", library => {
    const item = findItem(library, args.item); const timestamp = args.watchedAt ? Date.parse(args.watchedAt) / 1000 : now();
    if (!Number.isFinite(timestamp)) throw new Error("watchedAt must be an ISO-8601 date/time.");
    const event = { id: id(), itemID: item.id, watchedAt: timestamp, source: clientName };
    const position = currentPosition(library, item.id);
    library.viewingSessions ||= [];
    library.viewingSessions.push({ id: id(), itemID: item.id, watchedAt: timestamp, minutesWatched: Math.max(1, item.runtimeMinutes - position), endingPositionMinutes: item.runtimeMinutes, note: null, source: clientName, watchEventID: event.id });
    library.watchEvents.push(event); item.queueStatus = null; item.pinnedAt = null;
    return { item: item.title, watchCount: watchEventsFor(library, item.id).length, event, movedTo: "watched" };
  });
  if (name === "log_viewing_session") return mutate("Logged a viewing session", library => {
    const item = findItem(library, args.item);
    const timestamp = args.watchedAt ? Date.parse(args.watchedAt) / 1000 : now();
    if (!Number.isFinite(timestamp)) throw new Error("watchedAt must be an ISO-8601 date/time.");
    const position = currentPosition(library, item.id);
    const minutes = Math.min(args.minutesWatched, Math.max(1, item.runtimeMinutes - position));
    const endingPositionMinutes = Math.min(item.runtimeMinutes, position + minutes);
    const completed = endingPositionMinutes >= item.runtimeMinutes;
    const event = completed ? { id: id(), itemID: item.id, watchedAt: timestamp, source: clientName } : null;
    library.viewingSessions ||= [];
    const session = { id: id(), itemID: item.id, watchedAt: timestamp, minutesWatched: minutes, endingPositionMinutes, note: args.note?.trim() || null, source: clientName, watchEventID: event?.id || null };
    library.viewingSessions.push(session);
    if (event) library.watchEvents.push(event);
    item.queueStatus = completed ? null : "watching";
    item.pinnedAt = completed ? null : timestamp;
    return { item: item.title, session, completed, queueStatus: item.queueStatus, remainingMinutes: completed ? 0 : item.runtimeMinutes - endingPositionMinutes, watchCount: watchEventsFor(library, item.id).length };
  });
  if (name === "set_queue_status") return mutate("Updated watch queue", library => {
    const item = findItem(library, args.item);
    if (latestWatch(library, item.id)) throw new Error("Completed titles already live in Watched. Undo the latest watch before pinning it again.");
    item.queueStatus = args.status === "none" ? null : args.status;
    item.pinnedAt = args.status === "none" ? null : now();
    return { item: item.title, queueStatus: effectiveQueueStatus(library, item) };
  });
  if (name === "submit_rating") return mutate(`${args.person} submitted a sealed rating`, library => {
    if (!library.profiles.includes(args.person)) throw new Error(`Unknown profile. Use one of: ${library.profiles.join(", ")}`);
    if (typeof args.stars !== "number" || args.stars < 0.5 || args.stars > 5 || !Number.isInteger(args.stars * 2)) throw new Error("stars must be from 0.5 to 5 in half-star steps.");
    const item = findItem(library, args.item); const event = latestWatch(library, item.id); if (!event) throw new Error("Log a watch before rating.");
    library.ratings = library.ratings.filter(r => !(r.watchEventID === event.id && r.person === args.person));
    library.ratings.push({ id: id(), itemID: item.id, watchEventID: event.id, person: args.person, stars: args.stars, ratedAt: now(), review: args.review?.trim() || null, wouldRewatch: args.wouldRewatch ?? null, favorite: args.favorite ?? false });
    return { item: item.title, person: args.person, status: visibleRatings(library, item.id).status };
  });
  if (name === "set_profiles") return mutate("Updated rating profiles", library => {
    const requested = Array.isArray(args.profiles) ? args.profiles : [args.first, args.second].filter(Boolean);
    const names = requested.map(name => String(name).trim()).filter(Boolean);
    if (names.length < 1 || names.length > 12 || new Set(names.map(name => name.toLowerCase())).size !== names.length) throw new Error("Provide one to twelve different, non-empty profile names.");
    const old = library.profiles;
    library.ratings.forEach(rating => { const index = old.indexOf(rating.person); if (index >= 0 && names[index]) rating.person = names[index]; });
    library.profiles = names; library.setupComplete = true; return { profiles: names };
  });
  if (name === "set_streaming_services") return mutate("Updated streaming services", library => {
    library.subscribedProviders = [...new Set(args.services)]; library.setupComplete = true;
    return { streamingServices: library.subscribedProviders };
  });
  if (name === "what_is_watchable") {
    const library = readLibrary();
    const services = (library.subscribedProviders || []).filter(service => !args.provider || service.toLowerCase() === args.provider.toLowerCase());
    return services.map(provider => ({
      provider,
      items: library.items.filter(item => item.providerLinks.some(link => link.provider.toLowerCase() === provider.toLowerCase()) && (args.includeWatched || !latestWatch(library, item.id))).map(item => ({ id: item.id, title: item.title, kind: item.kind, seriesTitle: item.seriesTitle, season: item.season, episode: item.episode, runtimeMinutes: item.runtimeMinutes, links: item.providerLinks.filter(link => link.provider.toLowerCase() === provider.toLowerCase()) }))
    })).filter(group => group.items.length);
  }
  if (name === "recent_activity") {
    const library = readLibrary(); return (library.auditLog || []).slice(-(args.limit || 20)).reverse();
  }
  if (name === "undo_last_change") {
    acquireLock();
    try {
      if (!fs.existsSync(backupPath)) throw new Error("No backup is available to undo.");
      const current = fs.readFileSync(libraryPath); const backup = fs.readFileSync(backupPath);
      fs.writeFileSync(libraryPath, backup); fs.writeFileSync(backupPath, current);
      return { undone: true, note: "The previous library snapshot was restored. Call again to redo." };
    } finally { fs.rmSync(lockPath, { recursive: true, force: true }); }
  }
  throw new Error(`Unknown tool: ${name}`);
}

function response(idValue, result) { process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: idValue, result })}\n`); }
function errorResponse(idValue, error) { process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: idValue, error: { code: -32000, message: error.message || String(error) } })}\n`); }

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", async line => {
  if (!line.trim()) return;
  let message;
  try { message = JSON.parse(line); } catch (error) { return errorResponse(null, new Error("Invalid JSON")); }
  if (message.method?.startsWith("notifications/")) return;
  try {
    if (message.method === "initialize") {
      clientName = message.params?.clientInfo?.name || clientName;
      return response(message.id, { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "next-up", title: "Next Up", version: "1.1.0", description: "A private shared watch library" }, instructions: "Use read tools freely. Confirm meaningful writes with the user. Respect the library's rating reveal rule and never expose sealed scores." });
    }
    if (message.method === "ping") return response(message.id, {});
    if (message.method === "tools/list") return response(message.id, { tools });
    if (message.method === "tools/call") {
      const result = await callTool(message.params?.name, message.params?.arguments || {});
      return response(message.id, { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], structuredContent: result });
    }
    errorResponse(message.id, new Error(`Method not found: ${message.method}`));
  } catch (error) { errorResponse(message.id, error); }
});
