import { describe, expect, it } from "vitest";
import { collectionComplete, normalizeLibrary, revealedRatings, visibleCollections } from "./library";

const base = normalizeLibrary({
  setupComplete: true,
  profiles: ["A", "B"],
  collections: [{ id: "c", name: "Saga", subtitle: "", kind: "films", symbol: "film", accent: "6C63FF", position: 1, orders: [{ id: "o", name: "Order", itemIDs: ["a", "b"] }] }],
  items: [
    { id: "a", title: "A", kind: "movie", runtimeMinutes: 90, providerLinks: [], publicRating: 7 },
    { id: "b", title: "B", kind: "movie", runtimeMinutes: 100, providerLinks: [], queueStatus: "nextUp", publicRating: 8 }
  ]
});

describe("library model", () => {
  it("sorts pinned collections and separates completed sets", () => {
    expect(visibleCollections(base, "nextUp", "pinned")[0]?.id).toBe("c");
    expect(collectionComplete(base, base.collections[0])).toBe(false);
    const watched = { ...base, watchEvents: [
      { id: "wa", itemID: "a", watchedAt: 1, source: "test" },
      { id: "wb", itemID: "b", watchedAt: 2, source: "test" }
    ] };
    expect(collectionComplete(watched, watched.collections[0])).toBe(true);
    expect(visibleCollections(watched, "watched", "progress")).toHaveLength(1);
  });

  it("keeps group ratings hidden until every profile submits", () => {
    const watched = { ...base, watchEvents: [{ id: "w", itemID: "a", watchedAt: 1, source: "test" }] };
    const one = { ...watched, ratings: [{ id: "r", itemID: "a", watchEventID: "w", person: "A", stars: 4.5, ratedAt: 2 }] };
    expect(revealedRatings(one, "a").revealed).toBe(false);
    const both = { ...one, ratings: [...one.ratings, { id: "r2", itemID: "a", watchEventID: "w", person: "B", stars: 4, ratedAt: 3 }] };
    expect(revealedRatings(both, "a").revealed).toBe(true);
  });
});
