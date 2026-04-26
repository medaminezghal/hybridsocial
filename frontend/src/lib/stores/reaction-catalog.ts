// Shared, lazily-loaded premium-reaction catalog.
//
// Several components (PostActions stack, current-user mark, floating-
// emoji animation, reactions modal) need to render a reaction by its
// type string. Default reactions are a fixed map from type → emoji.
// Premium reactions are admin-curated and come from
// /api/v1/premium_reactions; without the catalog, premium types like
// "fire" render as their literal text.
//
// One module-level promise so every PostActions instance shares a
// single fetch instead of N parallel requests on a feed page.

import { writable, get } from 'svelte/store';
import { getPremiumReactions } from '$lib/api/conversations.js';

export interface PremiumReactionGlyph {
  shortcode: string;
  character: string | null;
  image_url: string | null;
}

const catalogStore = writable<Map<string, PremiumReactionGlyph>>(new Map());
let inflight: Promise<void> | null = null;

export function ensurePremiumCatalog(): Promise<void> {
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const res = await getPremiumReactions();
      const map = new Map<string, PremiumReactionGlyph>();
      for (const p of res.premium ?? []) {
        map.set(p.shortcode, {
          shortcode: p.shortcode,
          character: p.character,
          image_url: p.image_url,
        });
      }
      catalogStore.set(map);
    } catch {
      // Network / 401 — leave catalog empty so callers fall back to
      // the bare shortcode rather than blocking the feed render.
    }
  })();
  return inflight;
}

export function lookupPremium(shortcode: string): PremiumReactionGlyph | undefined {
  return get(catalogStore).get(shortcode);
}

export const premiumCatalog = catalogStore;
