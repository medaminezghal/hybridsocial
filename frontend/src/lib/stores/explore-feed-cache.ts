// In-memory snapshot of the explore feed (Local / Global / Trending) for
// the current session. Mirrors home-feed-cache.ts.
//
// The explore page re-mounts whenever the user navigates away and back
// (e.g. opens a post detail from the Global tab). Without this cache the
// page clears `posts`, re-fetches, and resets `activeId` to the first
// tab — so a back-nav from a Global post dropped the user on Local with
// the scroll position lost (issue #53).
//
// Hydrating from the cache on mount restores the active tab and the same
// DOM heights, which lets SvelteKit restore scroll cleanly. Session-
// scoped only — dropped on a full reload.

import type { Post } from '$lib/api/types.js';

export interface ExploreFeedSnapshot {
  posts: Post[];
  cursor: string | null;
  hasMore: boolean;
  tabId: string;
  scrollY?: number;
}

let snapshot: ExploreFeedSnapshot | null = null;

export function readExploreFeed(): ExploreFeedSnapshot | null {
  return snapshot;
}

export function writeExploreFeed(snap: ExploreFeedSnapshot): void {
  snapshot = snap;
}

export function clearExploreFeed(): void {
  snapshot = null;
}
