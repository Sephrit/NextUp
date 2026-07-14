export type MediaKind = "movie" | "episode" | "special";
export type CollectionKind = "films" | "series" | "queue" | "placeholder";
export type QueueStatus = "watching" | "nextUp" | null;

export interface ProviderLink {
  id: string;
  provider: string;
  url: string;
  accessType?: "sub" | "free" | "rent" | "buy";
  price?: number | null;
  format?: string | null;
}

export interface MediaItem {
  id: string;
  title: string;
  kind: MediaKind;
  seriesTitle?: string | null;
  season?: number | null;
  episode?: number | null;
  releaseYear?: number | null;
  airDate?: string | null;
  runtimeMinutes: number;
  providerLinks: ProviderLink[];
  artworkURL?: string | null;
  backdropURL?: string | null;
  publicRating?: number | null;
  criticScore?: number | null;
  contentRating?: string | null;
  queueStatus?: QueueStatus;
  pinnedAt?: number | null;
  genres?: string[];
  overview?: string | null;
}

export interface WatchOrder { id: string; name: string; itemIDs: string[] }
export interface MediaCollection {
  id: string;
  name: string;
  subtitle: string;
  kind: CollectionKind;
  symbol: string;
  accent: string;
  position: number;
  orders: WatchOrder[];
  artworkURL?: string | null;
  externalSource?: { provider: string; id: number } | null;
}
export interface WatchEvent { id: string; itemID: string; watchedAt: number; source: string }
export interface ViewingSession {
  id: string; itemID: string; watchedAt: number; minutesWatched: number;
  endingPositionMinutes: number; note?: string | null; source: string; watchEventID?: string | null;
}
export interface RatingEntry {
  id: string; itemID: string; watchEventID: string; person: string; stars: number; ratedAt: number;
  review?: string | null; wouldRewatch?: boolean | null; favorite?: boolean; tags?: string[];
}
export interface AppSettings {
  aiEnabled?: boolean;
  ratingReveal?: "immediate" | "when-everyone-rates";
  spoilerProtection?: boolean;
}
export interface LibraryData {
  schemaVersion: number;
  setupComplete?: boolean | null;
  profiles: string[];
  subscribedProviders?: string[] | null;
  collections: MediaCollection[];
  items: MediaItem[];
  watchEvents: WatchEvent[];
  ratings: RatingEntry[];
  viewingSessions?: ViewingSession[] | null;
  auditLog: Array<{ id: string; timestamp: number; source: string; action: string }>;
  appSettings?: AppSettings;
}

export type MainView = "collection" | "moviedex" | "timeline" | "genres" | "watchable" | "settings";
export type SidebarFilter = "all" | "watching" | "nextUp" | "unwatched" | "watched";
export type SidebarSort = "pinned" | "title" | "progress" | "rating" | "recent";
