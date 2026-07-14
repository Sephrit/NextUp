import type { LibraryData, MediaCollection, MediaItem, QueueStatus, SidebarFilter, SidebarSort } from "./types";

export const uid = () => crypto.randomUUID();
export const now = () => Date.now() / 1000;

export function normalizeLibrary(input: Partial<LibraryData>): LibraryData {
  const profiles = (input.profiles ?? []).map(profile => String(profile).trim()).filter(Boolean);
  return {
    schemaVersion: Math.max(8, input.schemaVersion ?? 8),
    setupComplete: input.setupComplete ?? false,
    profiles: profiles.length ? profiles : ["You"],
    subscribedProviders: input.subscribedProviders ?? [],
    collections: input.collections ?? [],
    items: (input.items ?? []).map(item => ({ ...item, providerLinks: item.providerLinks ?? [], genres: item.genres ?? [] })),
    watchEvents: input.watchEvents ?? [],
    ratings: input.ratings ?? [],
    viewingSessions: input.viewingSessions ?? [],
    auditLog: input.auditLog ?? [],
    appSettings: { ratingReveal: "when-everyone-rates", spoilerProtection: true, aiEnabled: false, ...input.appSettings }
  };
}

export const itemsFor = (library: LibraryData, collection: MediaCollection) => {
  const ids = collection.orders[0]?.itemIDs ?? [];
  const byId = new Map(library.items.map(item => [item.id, item]));
  return ids.map(id => byId.get(id)).filter((item): item is MediaItem => Boolean(item));
};

export const isWatched = (library: LibraryData, itemID: string) => library.watchEvents.some(event => event.itemID === itemID);
export const watchCount = (library: LibraryData, itemID: string) => library.watchEvents.filter(event => event.itemID === itemID).length;
export const collectionComplete = (library: LibraryData, collection: MediaCollection) => {
  const items = itemsFor(library, collection);
  return items.length > 0 && items.every(item => isWatched(library, item.id));
};
export const collectionProgress = (library: LibraryData, collection: MediaCollection) => {
  const items = itemsFor(library, collection);
  const watched = items.filter(item => isWatched(library, item.id)).length;
  return { watched, total: items.length, percent: items.length ? watched / items.length : 0 };
};
export const effectiveStatus = (library: LibraryData, item: MediaItem): QueueStatus => isWatched(library, item.id) ? null : item.queueStatus ?? null;
export const collectionStatus = (library: LibraryData, collection: MediaCollection): QueueStatus => {
  const statuses = itemsFor(library, collection).map(item => effectiveStatus(library, item));
  return statuses.includes("watching") ? "watching" : statuses.includes("nextUp") ? "nextUp" : null;
};
export const latestWatch = (library: LibraryData, collection: MediaCollection) => {
  const ids = new Set(itemsFor(library, collection).map(item => item.id));
  return Math.max(0, ...library.watchEvents.filter(event => ids.has(event.itemID)).map(event => event.watchedAt));
};
export const collectionRating = (library: LibraryData, collection: MediaCollection) => {
  const values = itemsFor(library, collection).map(item => item.publicRating).filter((value): value is number => typeof value === "number");
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : -1;
};

export function visibleCollections(library: LibraryData, filter: SidebarFilter, sort: SidebarSort) {
  const matches = (collection: MediaCollection) => {
    const complete = collectionComplete(library, collection);
    const status = collectionStatus(library, collection);
    if (filter === "watching") return status === "watching";
    if (filter === "nextUp") return status === "nextUp";
    if (filter === "unwatched") return !complete;
    if (filter === "watched") return complete;
    return true;
  };
  const rank = (collection: MediaCollection) => collectionStatus(library, collection) === "watching" ? 0 : collectionStatus(library, collection) === "nextUp" ? 1 : 2;
  return library.collections.filter(matches).sort((left, right) => {
    const rankDiff = rank(left) - rank(right);
    if (rankDiff) return rankDiff;
    if (sort === "title") return left.name.localeCompare(right.name);
    if (sort === "progress") return collectionProgress(library, right).percent - collectionProgress(library, left).percent;
    if (sort === "rating") return collectionRating(library, right) - collectionRating(library, left);
    if (sort === "recent") return latestWatch(library, right) - latestWatch(library, left);
    return left.position - right.position;
  });
}

export function revealedRatings(library: LibraryData, itemID: string) {
  const event = library.watchEvents.filter(entry => entry.itemID === itemID).sort((a, b) => b.watchedAt - a.watchedAt)[0];
  if (!event) return { revealed: false, entries: [] };
  const entries = library.ratings.filter(rating => rating.watchEventID === event.id);
  const everyoneRated = library.profiles.every(profile => entries.some(entry => entry.person === profile));
  const revealed = library.appSettings?.ratingReveal === "immediate" || library.profiles.length === 1 || everyoneRated;
  return { revealed, entries };
}
