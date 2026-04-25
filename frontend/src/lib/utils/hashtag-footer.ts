// Post bodies sometimes end with a dump of hashtags — the Instagram
// pattern: a paragraph of content, then three or ten tags jammed
// at the bottom. Those tags belong in a separate pill row under the
// post, not inlined as blue text inside the body. Mid-sentence
// hashtags are meaningful ("I love #coffee in the morning") and stay
// where they are. This helper detects the trailing-tags-only pattern
// and returns a cleaned HTML body plus the original HTML unchanged
// when the pattern doesn't apply.
//
// All hashtags (trailing or inline) are still surfaced in the footer
// via `post.tags` from the API — this helper only decides whether to
// strip them from the inline body.

export interface SplitResult {
  html: string;
  trimmed: boolean;
}

/**
 * Strips a trailing run of hashtag links (possibly separated by
 * whitespace / &nbsp; / <br>) from the end of an HTML body.
 * Leaves mid-sentence hashtags untouched. Returns the original HTML
 * verbatim when no trailing block is detected, or when running
 * outside a browser (SSR safety — DOMParser is browser-only in
 * SvelteKit's default runtime).
 */
export function stripTrailingHashtags(html: string | null | undefined): SplitResult {
  if (!html) return { html: '', trimmed: false };
  if (typeof document === 'undefined') return { html, trimmed: false };

  const container = document.createElement('div');
  container.innerHTML = html;

  let trimmed = false;
  let guard = 50; // defensive: never loop more than 50 removals

  while (guard-- > 0) {
    const lastLeaf = deepestLastNode(container);
    if (!lastLeaf) break;

    if (isHashtagLink(lastLeaf)) {
      // Also absorb the whitespace/<br>/&nbsp; directly before it so
      // we don't leave a dangling "   " tail on the paragraph.
      removeNodeAndPrecedingWhitespace(lastLeaf);
      trimmed = true;
      continue;
    }

    if (isWhitespaceNode(lastLeaf)) {
      lastLeaf.parentNode?.removeChild(lastLeaf);
      continue;
    }

    // First non-whitespace, non-hashtag node wins — stop here so we
    // don't chew into actual content.
    break;
  }

  // Clean up paragraphs / containers that are now empty because we
  // stripped every child. They'd render as hollow vertical space.
  removeEmptyTrailingContainers(container);

  // Mid-body cleanup: any paragraph (or trimmable container) whose
  // only meaningful children are hashtag links is also dropped. The
  // rule users wanted: "if the hashtag is on a line by itself, show
  // it only in the footer; if it's part of a sentence, keep both."
  // Inline hashtags inside text-bearing paragraphs are untouched.
  if (removeHashtagOnlyParagraphs(container)) trimmed = true;

  return { html: container.innerHTML, trimmed };
}

// Walks every paragraph-ish element. For each, first prunes any
// internal <br>-delimited "lines" that are themselves hashtag-only
// — Earmark/CommonMark collapses single newlines into <br> rather
// than separate <p>s, so a tag on its own line lives inside the
// surrounding paragraph alongside real sentence lines. Then drops
// the whole paragraph if everything left in it is still hashtag-
// only. Returns true if anything was removed.
function removeHashtagOnlyParagraphs(root: HTMLElement): boolean {
  const trimmable = new Set(['P', 'DIV', 'BLOCKQUOTE', 'SECTION']);
  let removed = false;
  const candidates = Array.from(root.querySelectorAll('p, div, blockquote, section'));

  for (const el of candidates) {
    if (!el.parentNode || !trimmable.has(el.tagName)) continue;

    if (stripHashtagOnlyLines(el)) removed = true;

    if (isHashtagOnly(el)) {
      el.parentNode.removeChild(el);
      removed = true;
    }
  }
  return removed;
}

// Splits the element's children at <br> boundaries and removes any
// segment that's entirely hashtag links + whitespace. The trailing
// <br> for a removed segment is also dropped so we don't leave a
// blank line behind.
function stripHashtagOnlyLines(el: Element): boolean {
  const children = Array.from(el.childNodes);
  // Collect segments: arrays of consecutive non-<br> nodes, plus the
  // <br> that terminates each (if any).
  const segments: { nodes: Node[]; terminator: Node | null }[] = [];
  let current: Node[] = [];

  for (const child of children) {
    if (child.nodeType === Node.ELEMENT_NODE && (child as Element).tagName === 'BR') {
      segments.push({ nodes: current, terminator: child });
      current = [];
    } else {
      current.push(child);
    }
  }
  if (current.length > 0) segments.push({ nodes: current, terminator: null });

  // Need at least 2 segments for a "standalone line" to even exist —
  // a paragraph with no <br> is handled by the whole-paragraph check.
  if (segments.length < 2) return false;

  let removed = false;
  for (const seg of segments) {
    if (isSegmentHashtagOnly(seg.nodes)) {
      for (const n of seg.nodes) n.parentNode?.removeChild(n);
      seg.terminator?.parentNode?.removeChild(seg.terminator);
      removed = true;
    }
  }
  return removed;
}

// Segment-level rule: treat the line as a tag dump if it has at
// least one hashtag link and no residue at all (whitespace doesn't
// count). This is intentionally stricter than the paragraph-level
// rule because a single line of "#foo" inside a paragraph is much
// more clearly a standalone tag than "#foo and other words".
function isSegmentHashtagOnly(nodes: Node[]): boolean {
  let sawHashtag = false;
  for (const n of nodes) {
    const counts = countSingleNode(n);
    if (counts.blocked) return false;
    sawHashtag = sawHashtag || counts.hashtagCount > 0;
    if (counts.residue.trim().length > 0) return false;
  }
  return sawHashtag;
}

interface NodeCounts {
  hashtagCount: number;
  residue: string;
  blocked: boolean;
}

function countSingleNode(node: Node): NodeCounts {
  if (isHashtagLink(node)) return { hashtagCount: 1, residue: '', blocked: false };
  if (isWhitespaceNode(node)) return { hashtagCount: 0, residue: '', blocked: false };
  if (node.nodeType === Node.TEXT_NODE) {
    return { hashtagCount: 0, residue: node.textContent || '', blocked: false };
  }
  if (node.nodeType !== Node.ELEMENT_NODE) {
    return { hashtagCount: 0, residue: '', blocked: false };
  }
  const el = node as HTMLElement;
  const tag = el.tagName;
  if (
    tag === 'IMG' ||
    tag === 'VIDEO' ||
    tag === 'IFRAME' ||
    tag === 'AUDIO' ||
    tag === 'BLOCKQUOTE' ||
    tag === 'PRE' ||
    tag === 'CODE'
  ) {
    return { hashtagCount: 0, residue: '', blocked: true };
  }
  if (tag === 'A') {
    // Non-hashtag <a> = real link → not a dump line.
    return { hashtagCount: 0, residue: '', blocked: true };
  }
  // Transparent wrappers — recurse over their children.
  const inner = countHashtagContent(el);
  return { hashtagCount: inner.hashtagCount, residue: inner.residue, blocked: false };
}

// "Hashtag-only" — true when the element's content is dominated by
// hashtag links and the rest is whitespace, emphasis-wrapped tag
// fragments (which is what happens when remote instances mis-render
// `#foo_bar_baz` and chew the underscores into <em>), or trivial
// punctuation that often sits between tags.
//
// We descend through transparent wrappers (em/strong/i/b/span) so
// federated content where Earmark or a similar engine ate hashtag
// underscores still gets recognised. The residue heuristic catches
// the case where the markup is broken: as long as the visible
// non-hashtag text is short and contains no sentence-ending
// punctuation, we treat the paragraph as a tag dump.
function isHashtagOnly(el: Element): boolean {
  const counts = countHashtagContent(el);
  if (counts.hashtagCount === 0) return false;
  // No non-hashtag, non-whitespace siblings at all → definitely a dump.
  if (counts.residue.length === 0) return true;

  // Federated mid-word emphasis bugs leave behind orphan word
  // fragments next to the anchors ("salat", "الصلاة", "إسلامي"…).
  // Strip the paragraph when:
  //   - 2+ hashtags
  //   - no sentence-ending punctuation in the residue
  //   - the number of residue word-tokens doesn't exceed the hashtag
  //     count (a real sentence with multiple hashtags carries more
  //     connective words than tags).
  const trimmed = counts.residue.trim();
  if (counts.hashtagCount < 2) return false;
  if (/[.!?،؛؟。！？]/.test(trimmed)) return false;
  if (!trimmed) return true;
  const tokens = trimmed.split(/\s+/u).filter(Boolean);
  return tokens.length <= counts.hashtagCount;
}

interface HashtagCounts {
  hashtagCount: number;
  residue: string;
}

function countHashtagContent(node: Node): HashtagCounts {
  let hashtagCount = 0;
  let residue = '';

  for (const child of Array.from(node.childNodes)) {
    if (isHashtagLink(child)) {
      hashtagCount += 1;
      continue;
    }
    if (isWhitespaceNode(child)) continue;
    if (child.nodeType === Node.TEXT_NODE) {
      residue += child.textContent || '';
      continue;
    }
    if (child.nodeType === Node.ELEMENT_NODE) {
      const el = child as HTMLElement;
      // Hard-block: anything with structural / media meaning is a
      // signal of a real sentence. Bail out so the paragraph stays.
      const tag = el.tagName;
      if (
        tag === 'IMG' ||
        tag === 'VIDEO' ||
        tag === 'IFRAME' ||
        tag === 'AUDIO' ||
        tag === 'BLOCKQUOTE' ||
        tag === 'PRE' ||
        tag === 'CODE'
      ) {
        return { hashtagCount: 0, residue: child.textContent ?? '' };
      }
      // Non-hashtag <a> = real link inside the paragraph → treat the
      // paragraph as content.
      if (tag === 'A') {
        return { hashtagCount: 0, residue: child.textContent ?? '' };
      }
      // Transparent wrappers (em/strong/i/b/span/u) — recurse so we
      // see the hashtags hiding inside them after the federated
      // markdown bug.
      const inner = countHashtagContent(child);
      hashtagCount += inner.hashtagCount;
      residue += inner.residue;
    }
  }

  return { hashtagCount, residue };
}

// Walk to the deepest rightmost node in the tree — that's the actual
// "last thing the reader sees". Works regardless of how the content
// is wrapped (single <p>, nested <div>s, <blockquote>s etc.).
function deepestLastNode(root: HTMLElement): Node | null {
  let node: Node | null = root.lastChild;
  while (node && node.nodeType === Node.ELEMENT_NODE && (node as Element).lastChild) {
    node = (node as Element).lastChild;
  }
  return node;
}

function isHashtagLink(node: Node): boolean {
  if (node.nodeType !== Node.ELEMENT_NODE) return false;
  const el = node as HTMLElement;
  if (el.tagName !== 'A') return false;

  if (el.classList?.contains('hashtag')) return true;

  // Fallback: match by href shape. Remote content may not carry our
  // `class="hashtag"` attribute, but the href still points at a
  // /tags/... route.
  const href = el.getAttribute('href') || '';
  return /\/tags\/[^/?#]+$/.test(href);
}

function isWhitespaceNode(node: Node): boolean {
  if (node.nodeType === Node.TEXT_NODE) {
    const text = (node.textContent || '').replace(/\u00A0/g, ' ');
    return text.trim() === '';
  }
  if (node.nodeType === Node.ELEMENT_NODE && (node as Element).tagName === 'BR') {
    return true;
  }
  return false;
}

function removeNodeAndPrecedingWhitespace(node: Node): void {
  let prev = node.previousSibling;
  while (prev && isWhitespaceNode(prev)) {
    const toRemove: Node = prev;
    prev = prev.previousSibling;
    toRemove.parentNode?.removeChild(toRemove);
  }
  node.parentNode?.removeChild(node);
}

// After stripping, a <p>...</p> that only held hashtags becomes an
// empty paragraph. Walk trailing empty structural elements off the
// tree. Doesn't touch <hr>, <img>, self-closing media — only empty
// text containers.
function removeEmptyTrailingContainers(root: HTMLElement): void {
  const trimmable = new Set(['P', 'DIV', 'BLOCKQUOTE', 'SECTION']);
  let safety = 20;

  while (safety-- > 0) {
    const last = root.lastChild;
    if (!last) break;

    if (last.nodeType === Node.ELEMENT_NODE) {
      const el = last as HTMLElement;
      if (
        trimmable.has(el.tagName) &&
        !el.textContent?.trim() &&
        !el.querySelector('img, video, iframe, audio')
      ) {
        el.parentNode?.removeChild(el);
        continue;
      }
    } else if (last.nodeType === Node.TEXT_NODE && !last.textContent?.trim()) {
      last.parentNode?.removeChild(last);
      continue;
    }

    break;
  }
}
