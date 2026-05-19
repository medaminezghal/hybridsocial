// External link trust + opt-out store. Two pieces of state, both
// localStorage-only (no server roundtrip — purely a UX preference):
//
//   1. A per-domain trust map: { "github.com": <epoch_ms> } — entries
//      auto-expire 24h after they're set.
//   2. A global on/off switch: when off, the warning modal never shows
//      regardless of the trust map.
//
// Both helpers are SSR-safe: outside the browser they degrade to
// "no trust, warning enabled" so the modal can render but never
// short-circuits during prerender.

const TRUST_KEY = 'hs:external_link_trust';
const DISABLED_KEY = 'hs:external_link_warning_disabled';
const TTL_MS = 24 * 60 * 60 * 1000;

// Built-in allowlist. Major, well-known platforms where the cost of
// the warning (annoyance, drop-off) outweighs the benefit (most users
// know these brands and would recognise a typo'd lookalike). Stored as
// root domains — `isKnownDomain` matches both the root and any
// subdomain. Kept short on purpose; phishing protection only works if
// the list is conservative.
const KNOWN_TRUSTED_DOMAINS: ReadonlySet<string> = new Set([
  // Code hosting / collaboration
  'github.com',
  'gitlab.com',
  'bitbucket.org',
  'codeberg.org',
  'sourcehut.org',
  'sr.ht',

  // Q&A and reference
  'stackoverflow.com',
  'stackexchange.com',
  'wikipedia.org',
  'wikimedia.org',
  'mdn.io',
  'developer.mozilla.org',

  // Search and big-tech roots (we match subdomains, so docs.*, mail.*,
  // etc. are all covered automatically)
  'google.com',
  'youtube.com',
  'youtu.be',
  'microsoft.com',
  'apple.com',
  'amazon.com',
  'cloudflare.com',
  'mozilla.org',

  // Major social platforms (so a link to a tweet / post doesn't get
  // interrupted on every click)
  'twitter.com',
  'x.com',
  'facebook.com',
  'instagram.com',
  'linkedin.com',
  'reddit.com',
  'youtube.com',
  'tiktok.com',
  'pinterest.com',
  'threads.net',
  'bsky.app',
  'mastodon.social',
  'mastodon.online',

  // Comms / productivity
  'discord.com',
  'discord.gg',
  'slack.com',
  'zoom.us',
  'notion.so',
  'dropbox.com',
  'figma.com',

  // Package registries and dev infrastructure
  'npmjs.com',
  'pypi.org',
  'rubygems.org',
  'crates.io',
  'hex.pm',
  'pkg.go.dev',
  'nodejs.org',
  'rust-lang.org',
  'python.org',
  'elixir-lang.org',
  'docker.com',

  // News / major media (a heuristic — extend per instance taste)
  'nytimes.com',
  'bbc.com',
  'bbc.co.uk',
  'reuters.com',
  'theguardian.com',
  'apnews.com',
  'aljazeera.com',
  'aljazeera.net',
  'arxiv.org',
]);

/**
 * Returns true if `hostname` matches any root domain in the built-in
 * allowlist. Matching is suffix-aware: `gist.github.com` matches
 * `github.com`, `mail.google.com` matches `google.com`. Exported so the
 * security settings page can show the user which roots are pre-trusted.
 */
export function isKnownDomain(hostname: string): boolean {
  if (!hostname) return false;
  const host = hostname.toLowerCase();
  for (const root of KNOWN_TRUSTED_DOMAINS) {
    if (host === root || host.endsWith('.' + root)) return true;
  }
  return false;
}

/** The full list of pre-trusted roots, exported so the UI can show it. */
export function knownTrustedDomains(): string[] {
  return [...KNOWN_TRUSTED_DOMAINS].sort();
}

type TrustMap = Record<string, number>;

function isBrowser(): boolean {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

function readTrust(): TrustMap {
  if (!isBrowser()) return {};
  try {
    const raw = window.localStorage.getItem(TRUST_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return {};
    return parsed as TrustMap;
  } catch {
    return {};
  }
}

function writeTrust(map: TrustMap): void {
  if (!isBrowser()) return;
  try {
    window.localStorage.setItem(TRUST_KEY, JSON.stringify(map));
  } catch {
    // Quota exceeded / disabled — silently drop. Worst case the user
    // sees the warning again, which is the safe default.
  }
}

function prune(map: TrustMap, now: number = Date.now()): TrustMap {
  const out: TrustMap = {};
  for (const [domain, expires] of Object.entries(map)) {
    if (typeof expires === 'number' && expires > now) {
      out[domain] = expires;
    }
  }
  return out;
}

/** Returns true if `domain` is currently trusted. Auto-prunes stale entries. */
export function isDomainTrusted(domain: string): boolean {
  if (!domain) return false;
  // Built-in allowlist always wins — checked before the per-user map
  // so adding a new well-known site doesn't depend on the user having
  // previously approved it.
  if (isKnownDomain(domain)) return true;
  const pruned = prune(readTrust());
  // Write-back the pruned copy so storage doesn't grow unbounded.
  writeTrust(pruned);
  return Object.prototype.hasOwnProperty.call(pruned, domain.toLowerCase());
}

/** Marks a domain as trusted for the next 24 hours. */
export function trustDomain(domain: string): void {
  if (!domain) return;
  const pruned = prune(readTrust());
  pruned[domain.toLowerCase()] = Date.now() + TTL_MS;
  writeTrust(pruned);
}

/** Drops every trusted entry. Used by the "Clear all trusted sites" button. */
export function clearTrustedDomains(): void {
  writeTrust({});
}

/** Returns true if the warning is globally disabled. */
export function isWarningDisabled(): boolean {
  if (!isBrowser()) return false;
  try {
    return window.localStorage.getItem(DISABLED_KEY) === '1';
  } catch {
    return false;
  }
}

/** Toggles the global on/off switch. */
export function setWarningDisabled(disabled: boolean): void {
  if (!isBrowser()) return;
  try {
    if (disabled) {
      window.localStorage.setItem(DISABLED_KEY, '1');
    } else {
      window.localStorage.removeItem(DISABLED_KEY);
    }
  } catch {
    // No-op
  }
}
