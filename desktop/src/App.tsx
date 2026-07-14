import { useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  collectionComplete, collectionProgress, collectionRating, collectionStatus, isWatched,
  itemsFor, normalizeLibrary, now, revealedRatings, uid, visibleCollections, watchCount
} from "./library";
import type {
  LibraryData, MainView, MediaCollection, MediaItem, QueueStatus, RatingEntry,
  SidebarFilter, SidebarSort
} from "./types";

const inTauri = () => "__TAURI_INTERNALS__" in window;
const serviceNames = ["Disney+", "Prime Video", "Peacock", "Paramount+", "Netflix", "Hulu", "Max", "Apple TV+", "Crunchyroll", "AMC+", "STARZ", "MGM+", "Shudder", "BritBox", "The Criterion Channel", "Tubi", "The Roku Channel", "Pluto TV", "Plex", "Kanopy", "Hoopla"];
const filters: Array<[SidebarFilter, string]> = [["all", "All"], ["watching", "Watching"], ["nextUp", "Next Up"], ["unwatched", "Unwatched"], ["watched", "Watched"]];
const sorts: Array<[SidebarSort, string]> = [["pinned", "Pinned / Added"], ["title", "Title"], ["progress", "Progress"], ["rating", "Rating"], ["recent", "Recently watched"]];

async function loadData() {
  if (inTauri()) return normalizeLibrary(await invoke<LibraryData>("load_library"));
  const saved = localStorage.getItem("next-up-preview");
  return normalizeLibrary(saved ? JSON.parse(saved) : {});
}
async function saveData(library: LibraryData) {
  if (inTauri()) await invoke("save_library", { library });
  else localStorage.setItem("next-up-preview", JSON.stringify(library));
}
const duration = (minutes: number) => `${Math.floor(minutes / 60) ? `${Math.floor(minutes / 60)}h ` : ""}${minutes % 60 ? `${minutes % 60}m` : ""}`.trim();
const dateText = (seconds: number) => new Date(seconds * 1000).toLocaleString([], { dateStyle: "medium", timeStyle: "short" });

export default function App() {
  const [library, setLibrary] = useState<LibraryData>();
  const [selectedID, setSelectedID] = useState("");
  const [view, setView] = useState<MainView>("moviedex");
  const [filter, setFilter] = useState<SidebarFilter>("all");
  const [sort, setSort] = useState<SidebarSort>("pinned");
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState(false);
  const [ratingItem, setRatingItem] = useState<MediaItem>();
  const [error, setError] = useState("");
  const hydrated = useRef(false);

  useEffect(() => { loadData().then(data => { setLibrary(data); setSelectedID(data.collections[0]?.id ?? ""); hydrated.current = true; }).catch(error => setError(String(error))); }, []);
  useEffect(() => {
    if (!library || !hydrated.current) return;
    const timer = window.setTimeout(() => saveData(library).catch(error => setError(String(error))), 250);
    return () => window.clearTimeout(timer);
  }, [library]);

  const mutate = (action: string, change: (draft: LibraryData) => void) => setLibrary(current => {
    if (!current) return current;
    const draft = structuredClone(current);
    change(draft);
    draft.auditLog.push({ id: uid(), timestamp: now(), source: "Next Up", action });
    draft.auditLog = draft.auditLog.slice(-250);
    return draft;
  });

  if (!library) return <div className="loading"><div className="logo">▶</div><h1>Next Up</h1><p>{error || "Opening your library…"}</p></div>;
  if (library.setupComplete !== true) return <Onboarding library={library} complete={updated => { setLibrary(updated); setView("moviedex"); }} />;

  const collections = visibleCollections(library, filter, sort);
  const selected = library.collections.find(item => item.id === selectedID);
  const searchResults = query.trim() ? library.items.filter(item => `${item.title} ${item.seriesTitle ?? ""}`.toLowerCase().includes(query.toLowerCase())).slice(0, 60) : [];

  const openCollection = (collection: MediaCollection) => { setSelectedID(collection.id); setView("collection"); setQuery(""); };
  const setStatus = (itemID: string, status: QueueStatus) => mutate(status ? `Pinned title to ${status}` : "Removed title pin", draft => {
    const item = draft.items.find(candidate => candidate.id === itemID); if (!item || isWatched(draft, itemID)) return;
    item.queueStatus = status; item.pinnedAt = status ? now() : null;
  });
  const markWatched = (item: MediaItem) => {
    const eventID = uid(), timestamp = now();
    mutate(`Watched ${item.title}`, draft => {
      draft.watchEvents.push({ id: eventID, itemID: item.id, watchedAt: timestamp, source: "Next Up" });
      draft.viewingSessions ??= [];
      draft.viewingSessions.push({ id: uid(), itemID: item.id, watchedAt: timestamp, minutesWatched: item.runtimeMinutes, endingPositionMinutes: item.runtimeMinutes, source: "Next Up", watchEventID: eventID });
      const target = draft.items.find(candidate => candidate.id === item.id); if (target) { target.queueStatus = null; target.pinnedAt = null; }
    });
    setRatingItem(item);
  };
  const logProgress = (item: MediaItem) => mutate(`Logged progress for ${item.title}`, draft => {
    const previous = (draft.viewingSessions ?? []).filter(session => session.itemID === item.id && !session.watchEventID).reduce((sum, session) => sum + session.minutesWatched, 0);
    const minutes = Math.min(30, Math.max(1, item.runtimeMinutes - previous));
    draft.viewingSessions ??= [];
    draft.viewingSessions.push({ id: uid(), itemID: item.id, watchedAt: now(), minutesWatched: minutes, endingPositionMinutes: Math.min(item.runtimeMinutes, previous + minutes), source: "Next Up" });
    const target = draft.items.find(candidate => candidate.id === item.id); if (target) { target.queueStatus = "watching"; target.pinnedAt = now(); }
  });

  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><div className="brand-icon">▶</div><div><small>NEXT UP</small><strong>{library.profiles.join(" & ")}</strong><span>{moviedexPercent(library)}% Moviedex</span></div></div>
      <div className="sidebar-controls">
        <select aria-label="Filter collections" value={filter} onChange={event => setFilter(event.target.value as SidebarFilter)}>{filters.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select>
        <select aria-label="Sort collections" value={sort} onChange={event => setSort(event.target.value as SidebarSort)}>{sorts.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select>
      </div>
      <nav className="collection-nav">
        {(["series", "films", "queue"] as const).map(kind => {
          const entries = collections.filter(collection => collection.kind === kind && !collectionComplete(library, collection));
          if (!entries.length) return null;
          return <SidebarSection key={kind} title={kind === "series" ? "Shows" : kind === "films" ? "Movie Series" : "Single Movies"} library={library} collections={entries} selectedID={selectedID} choose={openCollection} />;
        })}
        {collections.some(collection => collectionComplete(library, collection)) && <SidebarSection title="Watched" library={library} collections={collections.filter(collection => collectionComplete(library, collection))} selectedID={selectedID} choose={openCollection} />}
        {!collections.length && <p className="empty-small">No collections match.</p>}
      </nav>
      <nav className="explore-nav">
        <button className={view === "moviedex" ? "active" : ""} onClick={() => setView("moviedex")}>✦ <span>Moviedex</span></button>
        <button className={view === "timeline" ? "active" : ""} onClick={() => setView("timeline")}>◷ <span>Timeline</span></button>
        <button className={view === "genres" ? "active" : ""} onClick={() => setView("genres")}>▦ <span>Genres</span></button>
        <button className={view === "watchable" ? "active" : ""} onClick={() => setView("watchable")}>◉ <span>Watchable</span></button>
        <button className={view === "settings" ? "active" : ""} onClick={() => setView("settings")}>⚙ <span>Settings</span></button>
      </nav>
    </aside>

    <main>
      <header className="topbar">
        <div className="search-wrap"><span>⌕</span><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search your library" /></div>
        <button className="primary" onClick={() => setAdding(true)}>＋ Add</button>
      </header>
      {error && <div className="error-banner">{error}<button onClick={() => setError("")}>×</button></div>}
      <div className="main-scroll">
        {query.trim() ? <SearchResults library={library} items={searchResults} open={item => { const collection = library.collections.find(entry => entry.orders.some(order => order.itemIDs.includes(item.id))); if (collection) openCollection(collection); }} />
          : view === "collection" && selected ? <CollectionPage library={library} collection={selected} setStatus={setStatus} markWatched={markWatched} logProgress={logProgress} rate={setRatingItem} />
          : view === "timeline" ? <Timeline library={library} />
          : view === "genres" ? <Genres library={library} open={item => { const collection = library.collections.find(entry => entry.orders.some(order => order.itemIDs.includes(item.id))); if (collection) openCollection(collection); }} />
          : view === "watchable" ? <Watchable library={library} />
          : view === "settings" ? <Settings library={library} mutate={mutate} setLibrary={setLibrary} setError={setError} />
          : <Moviedex library={library} open={openCollection} />}
      </div>
    </main>
    {adding && <AddTitle library={library} close={() => setAdding(false)} add={(collection, items) => { mutate(`Added ${collection.name}`, draft => { draft.items.push(...items); draft.collections.push(collection); }); setSelectedID(collection.id); setView("collection"); setAdding(false); }} setError={setError} />}
    {ratingItem && <RatingModal library={library} item={ratingItem} close={() => setRatingItem(undefined)} save={entry => mutate(`${entry.person} rated ${ratingItem.title}`, draft => { const event = draft.watchEvents.filter(candidate => candidate.itemID === ratingItem.id).sort((a, b) => b.watchedAt - a.watchedAt)[0]; if (!event) return; draft.ratings = draft.ratings.filter(rating => !(rating.watchEventID === event.id && rating.person === entry.person)); draft.ratings.push({ ...entry, itemID: ratingItem.id, watchEventID: event.id }); })} />}
  </div>;
}

function SidebarSection({ title, library, collections, selectedID, choose }: { title: string; library: LibraryData; collections: MediaCollection[]; selectedID: string; choose: (collection: MediaCollection) => void }) {
  return <section><h3>{title}</h3>{collections.map(collection => {
    const progress = collectionProgress(library, collection), status = collectionStatus(library, collection);
    return <button key={collection.id} className={`collection-link ${selectedID === collection.id ? "selected" : ""}`} onClick={() => choose(collection)} style={{ "--accent": `#${collection.accent || "6C63FF"}` } as React.CSSProperties}>
      <Poster url={collection.artworkURL} title={collection.name} small />
      <span><strong>{collection.name}</strong><small>{progress.watched}/{progress.total} watched</small></span>
      {status && <b className={`status-dot ${status}`}>{status === "watching" ? "▶" : "●"}</b>}
    </button>;
  })}</section>;
}

function CollectionPage({ library, collection, setStatus, markWatched, logProgress, rate }: { library: LibraryData; collection: MediaCollection; setStatus: (id: string, status: QueueStatus) => void; markWatched: (item: MediaItem) => void; logProgress: (item: MediaItem) => void; rate: (item: MediaItem) => void }) {
  const items = itemsFor(library, collection), progress = collectionProgress(library, collection);
  const remainingMinutes = items.filter(item => !isWatched(library, item.id)).reduce((sum, item) => sum + item.runtimeMinutes, 0);
  const active = items.filter(item => !isWatched(library, item.id)).sort((a, b) => statusRank(a.queueStatus) - statusRank(b.queueStatus) || (b.pinnedAt ?? 0) - (a.pinnedAt ?? 0));
  const watched = items.filter(item => isWatched(library, item.id));
  return <div className="page">
    <section className="collection-hero" style={{ "--accent": `#${collection.accent || "6C63FF"}` } as React.CSSProperties}>
      <Poster url={collection.artworkURL} title={collection.name} />
      <div><span className="eyebrow">{collection.kind === "series" ? "SERIES" : collection.kind === "films" ? "MOVIE SERIES" : "MOVIE"}</span><h1>{collection.name}</h1><p>{collection.subtitle}</p><div className="hero-stats"><b>{Math.round(progress.percent * 100)}%</b><span>{progress.watched} of {progress.total} watched</span>{remainingMinutes > 0 && <span>{duration(remainingMinutes)} remaining</span>}{collectionRating(library, collection) > 0 && <span>★ {collectionRating(library, collection).toFixed(1)}/10</span>}</div></div>
    </section>
    {collection.kind === "series" ? <SeasonSections items={items} library={library} setStatus={setStatus} markWatched={markWatched} logProgress={logProgress} rate={rate} /> : <>{active.length ? <ItemSection title="Watching & Next Up" subtitle={`${active.length} left to collect`} items={active} library={library} setStatus={setStatus} markWatched={markWatched} logProgress={logProgress} rate={rate} /> : <div className="completion"><b>🏆 Collection complete</b><span>This set is now archived in your Watched section.</span></div>}{watched.length > 0 && <ItemSection title="Watched" subtitle={`${watched.length} collected`} items={watched} library={library} setStatus={setStatus} markWatched={markWatched} logProgress={logProgress} rate={rate} />}</>}
  </div>;
}

function SeasonSections(props: { items: MediaItem[]; library: LibraryData; setStatus: (id: string, status: QueueStatus) => void; markWatched: (item: MediaItem) => void; logProgress: (item: MediaItem) => void; rate: (item: MediaItem) => void }) {
  const seasons = [...new Set(props.items.map(item => item.season ?? 0))].sort((a, b) => a - b);
  const firstIncomplete = seasons.find(season => props.items.some(item => (item.season ?? 0) === season && !isWatched(props.library, item.id)));
  return <section className="seasons"><div className="section-title"><h2>Seasons</h2><span>Click anywhere on a season to expand it</span></div>{seasons.map(season => { const items = props.items.filter(item => (item.season ?? 0) === season).sort((a, b) => (a.episode ?? 0) - (b.episode ?? 0)); const watched = items.filter(item => isWatched(props.library, item.id)).length; return <details className="season-block" key={season} open={season === firstIncomplete || firstIncomplete == null && season === seasons[0]}><summary><span><b>{season ? `Season ${season}` : "Specials"}</b><small>{watched} of {items.length} watched · {Math.round(watched / Math.max(1, items.length) * 100)}%</small></span><progress max={items.length} value={watched} /><i>⌄</i></summary><div className="item-grid">{items.map(item => <MediaCard key={item.id} item={item} {...props} />)}</div></details>; })}</section>;
}

function ItemSection(props: { title: string; subtitle: string; items: MediaItem[]; library: LibraryData; setStatus: (id: string, status: QueueStatus) => void; markWatched: (item: MediaItem) => void; logProgress: (item: MediaItem) => void; rate: (item: MediaItem) => void }) {
  return <section className="item-section"><div className="section-title"><h2>{props.title}</h2><span>{props.subtitle}</span></div><div className="item-grid">{props.items.map(item => <MediaCard key={item.id} item={item} {...props} />)}</div></section>;
}

function MediaCard({ item, library, setStatus, markWatched, logProgress, rate }: { item: MediaItem; library: LibraryData; setStatus: (id: string, status: QueueStatus) => void; markWatched: (item: MediaItem) => void; logProgress: (item: MediaItem) => void; rate: (item: MediaItem) => void }) {
  const watched = isWatched(library, item.id), rating = revealedRatings(library, item.id);
  return <article className={`media-card ${watched ? "watched" : ""}`}>
    <Poster url={item.artworkURL} title={item.title} />
    <div className="media-copy"><div className="media-heading"><div><span className="eyebrow">{item.season ? `S${item.season} E${item.episode}` : item.releaseYear || "MOVIE"}</span><h3>{item.title}</h3></div>{watched && <span className="watched-seal">✓</span>}</div>
      <p>{duration(item.runtimeMinutes)}{item.contentRating ? ` · ${item.contentRating}` : ""}{watchCount(library, item.id) > 1 ? ` · ${watchCount(library, item.id)} watches` : ""}</p>
      <div className="score-row">{item.publicRating != null && <span className="public-score">★ {item.publicRating.toFixed(1)}/10</span>}{item.criticScore != null && <span>{item.criticScore}% critics</span>}{rating.revealed && rating.entries.length > 0 && <span className="ours">Ours {(rating.entries.reduce((sum, entry) => sum + entry.stars, 0) / rating.entries.length).toFixed(1)}/5</span>}{!rating.revealed && rating.entries.length > 0 && <span>🔒 Ratings sealed</span>}</div>
      <div className="card-actions">{watched ? <><button onClick={() => rate(item)}>Rate / Review</button><button onClick={() => markWatched(item)}>Rewatch</button></> : <><select aria-label={`Priority for ${item.title}`} value={item.queueStatus ?? ""} onChange={event => setStatus(item.id, (event.target.value || null) as QueueStatus)}><option value="">Unpinned</option><option value="watching">Watching</option><option value="nextUp">Next Up</option></select><button onClick={() => logProgress(item)}>＋30m</button><button className="success" onClick={() => markWatched(item)}>✓ Watched</button></>}</div>
    </div>
  </article>;
}

function Moviedex({ library, open }: { library: LibraryData; open: (collection: MediaCollection) => void }) {
  const watched = new Set(library.watchEvents.map(event => event.itemID)).size, total = library.items.length, percent = total ? Math.round(watched / total * 100) : 0;
  const completed = library.collections.filter(collection => collectionComplete(library, collection));
  const milestones = [1, 5, 10, 25, 50, 100, 250, 500, 1000], level = milestones.filter(value => value <= watched).length + 1, next = milestones.find(value => value > watched) ?? 1000;
  const badges = [["Opening Night", watched >= 1, "🎟"], ["Double Feature", watched >= 2, "🎞"], ["Completionist", completed.length >= 1, "🏆"], ["Rewatcher", library.watchEvents.length > watched, "↻"], ["Marathon", watched >= 10, "🔥"], ["Curator", total >= 50, "✦"]] as const;
  const remaining = Math.max(0, next - watched);
  return <div className="page"><section className="moviedex-hero"><div><span className="eyebrow gold">YOUR MOVIEDEX</span><h1>Level {level} · {watched} titles collected</h1><p>Your personal history of everything worth watching. Fill the gaps, finish sets, and make it yours.</p><div className="level-track"><i style={{ width: `${Math.min(100, watched / next * 100)}%` }} /></div><small>{remaining} title{remaining === 1 ? "" : "s"} to the next milestone</small></div><div className="big-ring" style={{ "--value": `${percent * 3.6}deg` } as React.CSSProperties}><b>{percent}%</b><span>{watched}/{total}</span></div></section>
    <div className="badge-grid">{badges.map(([name, earned, icon]) => <div key={name} className={earned ? "earned" : "locked"}><b>{icon}</b><span>{name}</span><small>{earned ? "Unlocked" : "Locked"}</small></div>)}</div>
    <section className="item-section"><div className="section-title"><h2>Completed sets</h2><span>{completed.length} archived</span></div>{completed.length ? <div className="poster-rail">{completed.map(collection => <button key={collection.id} onClick={() => open(collection)}><Poster url={collection.artworkURL} title={collection.name} /><strong>{collection.name}</strong></button>)}</div> : <div className="empty-state"><b>Your first trophy is waiting.</b><span>Complete every title in a collection to archive the set here.</span></div>}</section>
  </div>;
}

function Timeline({ library }: { library: LibraryData }) {
  const events = [...library.watchEvents].sort((a, b) => b.watchedAt - a.watchedAt);
  const byID = new Map(library.items.map(item => [item.id, item]));
  const groupedEvents = events.reduce<Record<string, typeof events>>((groups, event) => {
    const month = new Date(event.watchedAt * 1000).toLocaleDateString([], {
      month: "long",
      year: "numeric",
    });
    (groups[month] ??= []).push(event);
    return groups;
  }, {});
  const groups = Object.entries(groupedEvents);
  return <div className="page"><div className="page-heading"><span className="eyebrow">YOUR HISTORY</span><h1>Watch timeline</h1><p>Every first watch and rewatch stays part of the story.</p></div>{groups.length ? groups.map(([month, entries]) => <section className="timeline" key={month}><h2>{month}</h2>{entries?.map(event => { const item = byID.get(event.itemID); if (!item) return null; const ratings = revealedRatings(library, item.id); return <article key={event.id}><i /><Poster url={item.artworkURL} title={item.title} small /><div><h3>{item.title}</h3><p>{dateText(event.watchedAt)} · {event.source}{watchCount(library, item.id) > 1 ? " · Rewatch" : ""}</p>{ratings.revealed && <span>★ {ratings.entries.map(rating => `${rating.person} ${rating.stars}`).join(" · ")}</span>}</div></article>; })}</section>) : <div className="empty-state"><b>Your timeline starts with your first watch.</b><span>Mark any movie or episode watched to add it here.</span></div>}</div>;
}

function Genres({ library, open }: { library: LibraryData; open: (item: MediaItem) => void }) {
  const names = [...new Set(library.items.flatMap(item => item.genres?.length ? item.genres : ["Unsorted"]))].sort();
  return <div className="page"><div className="page-heading"><span className="eyebrow">EXPLORE YOUR TASTE</span><h1>Genres</h1><p>See what your Moviedex says about the stories you choose.</p></div><div className="genre-grid">{names.map(name => { const items = library.items.filter(item => (item.genres?.length ? item.genres : ["Unsorted"]).includes(name)); const watched = items.filter(item => isWatched(library, item.id)).length; return <section key={name}><div><h2>{name}</h2><span>{watched}/{items.length} watched</span></div><div className="mini-posters">{items.slice(0, 5).map(item => <button key={item.id} onClick={() => open(item)}><Poster url={item.artworkURL} title={item.title} small /></button>)}</div><progress max={items.length} value={watched} /></section>; })}</div></div>;
}

function Watchable({ library }: { library: LibraryData }) {
  const selected = library.subscribedProviders ?? [];
  const groups = selected.map(provider => ({
    provider,
    items: library.items.filter(item => !isWatched(library, item.id) && item.providerLinks.some(link => link.provider.toLowerCase() === provider.toLowerCase()))
  }));
  return <div className="page"><div className="page-heading"><span className="eyebrow">YOUR SERVICES</span><h1>What’s watchable</h1><p>Confirmed links for unwatched titles already in your library. Availability comes from the metadata last saved for each title.</p></div>{selected.length ? <div className="watchable-groups">{groups.map(({ provider, items }) => <details key={provider} open={items.length > 0}><summary><span><b>{provider}</b><small>{items.length} unwatched title{items.length === 1 ? "" : "s"}</small></span><i>⌄</i></summary>{items.length ? <div className="watchable-list">{items.map(item => <article key={item.id}><Poster url={item.artworkURL} title={item.title} small /><span><strong>{item.title}</strong><small>{duration(item.runtimeMinutes)}{item.publicRating != null ? ` · ★ ${item.publicRating.toFixed(1)}` : ""}</small></span><div>{item.providerLinks.filter(link => link.provider.toLowerCase() === provider.toLowerCase()).map(link => <a key={link.id} href={link.url} target="_blank" rel="noreferrer" onClick={event => { if (inTauri()) { event.preventDefault(); openUrl(link.url); } }}>{link.accessType === "rent" || link.accessType === "buy" ? `${link.accessType}${link.price != null ? ` $${link.price.toFixed(2)}` : ""}` : "Watch"}</a>)}</div></article>)}</div> : <p className="provider-empty">No saved matches right now. Refreshing or importing metadata can add current links.</p>}</details>)}</div> : <div className="empty-state"><b>Choose your streaming services first.</b><span>Open Settings and select every service available to your household.</span></div>}</div>;
}

function SearchResults({ library, items, open }: { library: LibraryData; items: MediaItem[]; open: (item: MediaItem) => void }) {
  return <div className="page"><div className="page-heading"><span className="eyebrow">LIBRARY SEARCH</span><h1>{items.length} result{items.length === 1 ? "" : "s"}</h1></div><div className="search-results">{items.map(item => <button key={item.id} onClick={() => open(item)}><Poster url={item.artworkURL} title={item.title} small /><span><strong>{item.title}</strong><small>{item.seriesTitle || item.releaseYear || item.kind}</small></span>{isWatched(library, item.id) && <b>✓ Watched</b>}</button>)}</div>{!items.length && <div className="empty-state"><b>No saved titles found.</b><span>Use Add to search Watchmode or create one manually.</span></div>}</div>;
}

function Settings({ library, mutate, setLibrary, setError }: { library: LibraryData; mutate: (action: string, change: (draft: LibraryData) => void) => void; setLibrary: (library: LibraryData) => void; setError: (value: string) => void }) {
  const [key, setKey] = useState(""); const [hasKey, setHasKey] = useState(false);
  useEffect(() => { if (inTauri()) invoke<boolean>("has_watchmode_key").then(setHasKey); }, []);
  const addProfile = () => mutate("Added profile", draft => draft.profiles.push(`Person ${draft.profiles.length + 1}`));
  const exportJSON = () => { const link = document.createElement("a"); link.href = URL.createObjectURL(new Blob([JSON.stringify(library, null, 2)], { type: "application/json" })); link.download = "next-up-library.json"; link.click(); URL.revokeObjectURL(link.href); };
  return <div className="page settings"><div className="page-heading"><span className="eyebrow">PRIVATE BY DEFAULT</span><h1>Settings</h1><p>Everything stays local unless you deliberately export it or enable an integration.</p></div>
    <section><h2>Who is rating?</h2><p>Use one profile, a couple, a family, or a whole movie club.</p><div className="profile-list">{library.profiles.map((profile, index) => <div key={`${index}-${profile}`}><input defaultValue={profile} onBlur={event => { const next = event.currentTarget.value.trim(); const duplicate = library.profiles.some((candidate, candidateIndex) => candidateIndex !== index && candidate.toLowerCase() === next.toLowerCase()); if (!next || duplicate) { event.currentTarget.value = profile; setError(duplicate ? "Profile names must be different." : "Profile names cannot be empty."); return; } if (next !== profile) mutate("Renamed profile", draft => { const previous = draft.profiles[index]; draft.profiles[index] = next; draft.ratings.forEach(rating => { if (rating.person === previous) rating.person = next; }); }); }} /><button disabled={library.profiles.length === 1} onClick={() => mutate("Removed profile", draft => draft.profiles.splice(index, 1))}>Remove</button></div>)}</div><button disabled={library.profiles.length >= 12} onClick={addProfile}>＋ Add person</button>
      <label className="setting-row"><span><b>Group rating reveal</b><small>Hide everyone’s score until every profile submits.</small></span><select value={library.appSettings?.ratingReveal} onChange={event => mutate("Changed rating reveal", draft => { draft.appSettings ??= {}; draft.appSettings.ratingReveal = event.target.value as "immediate" | "when-everyone-rates"; })}><option value="when-everyone-rates">When everyone rates</option><option value="immediate">Immediately</option></select></label></section>
    <section><h2>Streaming metadata</h2><p>Watchmode is optional. It adds artwork, public scores, genres, runtimes, and availability.</p><div className="key-row"><input type="password" value={key} onChange={event => setKey(event.target.value)} placeholder={hasKey ? "API key securely stored" : "Paste Watchmode API key"} /><button onClick={async () => { try { await invoke("save_watchmode_key", { key }); setKey(""); setHasKey(true); } catch (error) { setError(String(error)); } }}>Save key</button>{hasKey && <button onClick={async () => { await invoke("remove_watchmode_key"); setHasKey(false); }}>Remove</button>}</div></section>
    <section><h2>Your streaming services</h2><p>Click anywhere on a service tile. Watchable only shows saved matches from the services you select.</p><div className="service-grid">{serviceNames.map(service => { const checked = (library.subscribedProviders ?? []).includes(service); return <label key={service} className={checked ? "selected" : ""}><input type="checkbox" checked={checked} onChange={() => mutate(`Changed ${service} subscription`, draft => { const providers = new Set(draft.subscribedProviders ?? []); checked ? providers.delete(service) : providers.add(service); draft.subscribedProviders = [...providers]; })} /><span>{service}</span><b>{checked ? "✓" : "+"}</b></label>; })}</div></section>
    <section><h2>Optional AI package</h2><p>The app works completely without AI. Enabling this only displays setup instructions for the local MCP package; it never uploads your library by itself.</p><label className="toggle"><input type="checkbox" checked={library.appSettings?.aiEnabled ?? false} onChange={event => mutate("Changed AI integration setting", draft => { draft.appSettings ??= {}; draft.appSettings.aiEnabled = event.target.checked; })} /><span>Show AI/MCP integration</span></label>{library.appSettings?.aiEnabled && <div className="code-card"><code>node MCP/mcp-server.mjs</code><p>See <b>AI_SETUP.md</b> for Codex, Claude, Hermes, and OpenClaw configuration.</p></div>}</section>
    <section><h2>Own your data</h2><div className="button-row"><button onClick={exportJSON}>Export JSON backup</button><label className="file-button">Import JSON<input type="file" accept="application/json" onChange={event => { const file = event.target.files?.[0]; if (!file) return; file.text().then(raw => setLibrary(normalizeLibrary(JSON.parse(raw)))).catch(error => setError(String(error))); }} /></label></div></section>
  </div>;
}

function AddTitle({ library, close, add, setError }: { library: LibraryData; close: () => void; add: (collection: MediaCollection, items: MediaItem[]) => void; setError: (value: string) => void }) {
  const [tab, setTab] = useState<"movies" | "shows" | "manual">("movies"), [query, setQuery] = useState(""), [results, setResults] = useState<any[]>([]), [busy, setBusy] = useState(false);
  const [manual, setManual] = useState({ title: "", year: new Date().getFullYear(), runtime: 120, genres: "", artworkURL: "" });
  const create = (item: MediaItem) => { const id = `single-movie-${item.id}`; add({ id, name: item.title, subtitle: `Standalone movie${item.releaseYear ? ` · ${item.releaseYear}` : ""}`, kind: "queue", symbol: "popcorn", accent: accentFor(item.title), position: Math.max(0, ...library.collections.map(entry => entry.position)) + 1, orders: [{ id: `${id}-order`, name: "Movie", itemIDs: [item.id] }], artworkURL: item.artworkURL }, [item]); };
  const search = async () => { setBusy(true); try { if (tab === "shows") { setResults(await invoke<any[]>("search_tvmaze", { query })); } else { const response = await invoke<{ results: any[] }>("search_watchmode", { query }); setResults((response.results ?? []).filter(result => result.type === "movie" || result.type === "tv_movie")); } } catch (error) { setError(String(error)); } finally { setBusy(false); } };
  const importMovie = async (result: any) => { setBusy(true); try { const details: any = await invoke("watchmode_details", { id: result.id }); create({ id: `watchmode-movie-${result.id}`, title: details.title, kind: "movie", releaseYear: details.year, runtimeMinutes: Math.max(1, details.runtime_minutes || 120), providerLinks: (details.sources ?? []).filter((source: any) => source.web_url).map((source: any) => ({ id: uid(), provider: source.name, url: source.web_url, accessType: source.type === "purchase" ? "buy" : source.type, price: source.price, format: source.format })), artworkURL: details.posterMedium || details.poster || details.posterLarge, backdropURL: details.backdrop, publicRating: details.user_rating, criticScore: details.critic_score, contentRating: details.us_rating, genres: details.genre_names ?? [], overview: details.plot_overview }); } catch (error) { setError(String(error)); } finally { setBusy(false); } };
  const importShow = async (result: any) => { const show = result.show ?? result; setBusy(true); try { const details: any = await invoke("tvmaze_show", { id: show.id }); const episodes = details._embedded?.episodes ?? []; if (!episodes.length) throw new Error("TVmaze has no announced episodes for this show yet."); const artwork = details.image?.original || details.image?.medium || null; const items: MediaItem[] = episodes.map((episode: any) => ({ id: `tvmaze-${details.id}-episode-${episode.id}`, title: episode.name || `Episode ${episode.number}`, kind: "episode", seriesTitle: details.name, season: episode.season || 0, episode: episode.number || 0, releaseYear: episode.airdate ? Number(episode.airdate.slice(0, 4)) : null, airDate: episode.airdate || null, runtimeMinutes: Math.max(1, episode.runtime || details.averageRuntime || 24), providerLinks: [], artworkURL: episode.image?.original || episode.image?.medium || artwork, genres: details.genres ?? [], overview: episode.summary ? String(episode.summary).replace(/<[^>]+>/g, "") : null })); const id = `tvmaze-series-${details.id}`; add({ id, name: details.name, subtitle: `${items.length} episodes${details.premiered ? ` · ${String(details.premiered).slice(0, 4)}` : ""}`, kind: "series", symbol: "play.rectangle.on.rectangle", accent: accentFor(details.name), position: Math.max(0, ...library.collections.map(entry => entry.position)) + 1, orders: [{ id: `${id}-order`, name: "Episode Order", itemIDs: items.map(item => item.id) }], artworkURL: artwork, externalSource: { provider: "TVmaze", id: details.id } }, items); } catch (error) { setError(String(error)); } finally { setBusy(false); } };
  return <div className="modal-backdrop"><div className="modal add-modal"><button className="close" onClick={close}>×</button><span className="eyebrow">GROW YOUR MOVIEDEX</span><h1>Add movies or shows</h1><div className="tabs"><button className={tab === "movies" ? "active" : ""} onClick={() => { setTab("movies"); setResults([]); }}>Movies</button><button className={tab === "shows" ? "active" : ""} onClick={() => { setTab("shows"); setResults([]); }}>Shows</button><button className={tab === "manual" ? "active" : ""} onClick={() => setTab("manual")}>Manual movie</button></div>{tab !== "manual" ? <><div className="search-add"><input autoFocus value={query} onChange={event => setQuery(event.target.value)} onKeyDown={event => event.key === "Enter" && search()} placeholder={tab === "shows" ? "Search shows, anime, and series" : "Search movies"} /><button className="primary" disabled={busy || !query.trim()} onClick={search}>{busy ? "Working…" : "Search"}</button></div>{tab === "movies" ? <div className="catalog-results">{results.map(result => <button key={result.id} onClick={() => importMovie(result)} disabled={busy || library.items.some(item => item.id === `watchmode-movie-${result.id}`)}><Poster url={result.image_url} title={result.name} small /><span><strong>{result.name}</strong><small>{result.year || "Year unknown"}</small></span><b>{library.items.some(item => item.id === `watchmode-movie-${result.id}`) ? "Added" : "＋ Add"}</b></button>)}</div> : <div className="catalog-results">{results.map(result => { const show = result.show; const added = library.collections.some(collection => collection.id === `tvmaze-series-${show.id}`); return <button key={show.id} onClick={() => importShow(result)} disabled={busy || added}><Poster url={show.image?.medium} title={show.name} small /><span><strong>{show.name}</strong><small>{show.premiered?.slice(0, 4) || "Year unknown"} · {show.type || "Series"}</small></span><b>{added ? "Added" : "＋ Import episodes"}</b></button>; })}</div>}</> : <div className="form-grid"><label>Title<input autoFocus value={manual.title} onChange={event => setManual({ ...manual, title: event.target.value })} /></label><label>Year<input type="number" value={manual.year} onChange={event => setManual({ ...manual, year: Number(event.target.value) })} /></label><label>Runtime in minutes<input type="number" value={manual.runtime} onChange={event => setManual({ ...manual, runtime: Number(event.target.value) })} /></label><label>Genres, comma separated<input value={manual.genres} onChange={event => setManual({ ...manual, genres: event.target.value })} /></label><label className="wide">Poster URL, optional<input value={manual.artworkURL} onChange={event => setManual({ ...manual, artworkURL: event.target.value })} /></label><button className="primary wide" disabled={!manual.title.trim()} onClick={() => create({ id: `movie-${slug(manual.title)}-${uid().slice(0, 6)}`, title: manual.title.trim(), kind: "movie", releaseYear: manual.year, runtimeMinutes: Math.max(1, manual.runtime), providerLinks: [], artworkURL: manual.artworkURL || null, genres: manual.genres.split(",").map(value => value.trim()).filter(Boolean) })}>Add movie</button></div>}</div></div>;
}

function RatingModal({ library, item, close, save }: { library: LibraryData; item: MediaItem; close: () => void; save: (entry: RatingEntry) => void }) {
  const existing = revealedRatings(library, item.id).entries;
  const sealed = library.profiles.length > 1 && library.appSettings?.ratingReveal !== "immediate";
  const firstPending = library.profiles.find(profile => !existing.some(entry => entry.person === profile)) ?? library.profiles[0];
  const [person, setPerson] = useState(firstPending);
  const [stars, setStars] = useState(3);
  const [review, setReview] = useState("");
  const [wouldRewatch, setWouldRewatch] = useState(true);
  const [favorite, setFavorite] = useState(false);
  const submitted = existing.some(entry => entry.person === person);
  const choose = (profile: string) => {
    setPerson(profile);
    const prior = existing.find(entry => entry.person === profile);
    const mayReveal = !sealed || revealedRatings(library, item.id).revealed;
    setStars(mayReveal && prior ? prior.stars : 3);
    setReview(mayReveal && prior ? prior.review ?? "" : "");
    setWouldRewatch(mayReveal && prior ? prior.wouldRewatch ?? true : true);
    setFavorite(mayReveal && prior ? prior.favorite ?? false : false);
  };
  const lockedSubmission = sealed && submitted && !revealedRatings(library, item.id).revealed;
  return <div className="modal-backdrop"><div className="modal rating-modal"><button className="close" onClick={close}>×</button><span className="eyebrow">YOUR VERDICT</span><h1>{item.title}</h1><p>{sealed ? "Choose your profile, rate privately, then pass the device along. Scores reveal only after everyone submits." : "Build a rating that means more than a number."}</p><div className="profile-chooser">{library.profiles.map(profile => <button key={profile} className={person === profile ? "active" : ""} onClick={() => choose(profile)}><strong>{profile}</strong><small>{existing.some(entry => entry.person === profile) ? "✓ Submitted" : "Waiting"}</small></button>)}</div>{lockedSubmission ? <div className="sealed-card"><b>🔒 {person}’s rating is sealed.</b><span>Choose a profile still waiting, or close this and pass the device along.</span></div> : <section><h2>{person}</h2><div className="rating-line"><input aria-label={`${person} stars`} type="range" min="0.5" max="5" step="0.5" value={stars} onChange={event => setStars(Number(event.target.value))} /><b>{stars.toFixed(1)} ★</b></div><textarea value={review} onChange={event => setReview(event.target.value)} placeholder="A quick thought, favorite moment, or hot take…" /><div className="rating-toggles"><label><input type="checkbox" checked={wouldRewatch} onChange={event => setWouldRewatch(event.target.checked)} /> Would rewatch</label><label><input type="checkbox" checked={favorite} onChange={event => setFavorite(event.target.checked)} /> Favorite</label></div><button className="primary full" onClick={() => { save({ id: uid(), itemID: item.id, watchEventID: "", person, stars, ratedAt: now(), review: review || null, wouldRewatch, favorite }); close(); }}>Seal rating for {person}</button></section>}</div></div>;
}

function Onboarding({ library, complete }: { library: LibraryData; complete: (library: LibraryData) => void }) {
  const [profiles, setProfiles] = useState(library.profiles.length ? library.profiles : ["You"]); const [name, setName] = useState("My Moviedex");
  const invalidProfiles = profiles.some(profile => !profile.trim()) || new Set(profiles.map(profile => profile.trim().toLowerCase())).size !== profiles.length;
  return <div className="onboarding"><div className="onboarding-card"><div className="logo large">▶</div><span className="eyebrow gold">WELCOME TO NEXT UP</span><h1>Build a Moviedex that is actually yours.</h1><p>Track alone, with a partner, as a family, or with a movie club. Your library stays on this computer.</p><label>Library name<input value={name} onChange={event => setName(event.target.value)} /></label><h2>Who is watching and rating?</h2>{profiles.map((profile, index) => <div className="profile-entry" key={index}><input autoFocus={index === 0} value={profile} onChange={event => setProfiles(profiles.map((value, entry) => entry === index ? event.target.value : value))} /><button disabled={profiles.length === 1} onClick={() => setProfiles(profiles.filter((_, entry) => entry !== index))}>×</button></div>)}<button disabled={profiles.length >= 12} onClick={() => setProfiles([...profiles, `Person ${profiles.length + 1}`])}>＋ Add another person</button>{invalidProfiles && <small>Use a different, non-empty name for each profile.</small>}<button className="primary full" disabled={invalidProfiles || !name.trim()} onClick={() => complete({ ...library, setupComplete: true, profiles: profiles.map(profile => profile.trim()), appSettings: { ...library.appSettings, aiEnabled: false }, auditLog: [...library.auditLog, { id: uid(), timestamp: now(), source: "Next Up", action: `Created ${name.trim()}` }] })}>Start my Moviedex</button><small>AI integrations are off by default and can be enabled later.</small></div></div>;
}

function Poster({ url, title, small = false }: { url?: string | null; title: string; small?: boolean }) { return <div className={`poster ${small ? "small" : ""}`}>{url ? <img src={url} alt="" /> : <span>{title.slice(0, 2).toUpperCase()}</span>}</div>; }
const statusRank = (status: QueueStatus | undefined) => status === "watching" ? 0 : status === "nextUp" ? 1 : 2;
const moviedexPercent = (library: LibraryData) => library.items.length ? Math.round(new Set(library.watchEvents.map(event => event.itemID)).size / library.items.length * 100) : 0;
const slug = (value: string) => value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const accentFor = (value: string) => ["6C63FF", "D9548E", "2786C5", "DC7132", "3CAB70", "8C5BC6"][value.split("").reduce((sum, character) => sum + character.charCodeAt(0), 0) % 6];
