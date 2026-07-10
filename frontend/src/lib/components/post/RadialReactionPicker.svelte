<script lang="ts">
  // Touch-only reaction dial. Lives as an overlay over the whole
  // viewport; PostActions owns the touch handlers and tells us where
  // the user's finger currently is. We figure out which emoji that
  // angle picks and bubble it back through `bind:highlightedType` so
  // the parent can commit it on touchend.

  interface RadialReaction {
    type: string;
    emoji: string;
    label: string;
    image?: string | null;
  }

  let {
    originX,
    originY,
    touchX,
    touchY,
    reactions,
    highlightedType = $bindable<string | null>(null),
    onpick = undefined,
  }: {
    originX: number;
    originY: number;
    touchX: number;
    touchY: number;
    reactions: RadialReaction[];
    highlightedType?: string | null;
    /** Called when an emoji is tapped directly on an already-open dial. */
    onpick?: (type: string) => void;
  } = $props();

  // Pixel distance the finger has to travel from the origin before
  // any emoji is considered "aimed at". Under this radius, releasing
  // cancels the reaction — same UX as the iOS message tapback dial.
  const DEAD_ZONE_PX = 36;
  // Safety gutter from each viewport edge — bubbles never sit closer
  // to the screen edge than `halfItem + EDGE_MARGIN` so the rounded
  // bubble graphic never gets clipped.
  const EDGE_MARGIN = 6;

  // ------------------------------------------------------------------
  // TWO-RING RADIAL LAYOUT
  //
  // A single arc wide enough to space N emojis is, on a phone, also wide
  // enough that its end items reach the screen edge — where clamping the
  // rendered position away from the true angle made the corner emojis
  // unpickable, and the low ends collided with the reply/repost row.
  //
  // Splitting the reactions across two concentric arcs keeps each arc's
  // angular spread small, so ends stay well above the action row, and
  // the whole dial fits on-screen. Hit-testing is by *nearest rendered
  // bubble* rather than by angle, which is inherently immune to the
  // clamp-vs-angle mismatch: whatever emoji the finger is closest to is
  // the one that highlights, and it naturally spans both rings.
  // ------------------------------------------------------------------

  let itemSize = $derived(reactions.length > 7 ? 40 : 46);
  let emojiSize = $derived(reactions.length > 7 ? 22 : 26);

  // Inner ring gets the first half, outer ring the rest.
  let ringCounts = $derived.by(() => {
    const n = reactions.length;
    if (n <= 1) return { inner: n, outer: 0 };
    const inner = Math.ceil(n / 2);
    return { inner, outer: n - inner };
  });

  const INNER_RADIUS = 82;
  const OUTER_RADIUS = 132;
  // Narrow inner sweep keeps its low items from splaying into the outer
  // ring or colliding once they clamp near a screen edge; the outer arc
  // can afford a wide, comfortable spread.
  let innerSweep = $derived(ringCounts.inner >= 6 ? 100 : ringCounts.inner >= 4 ? 120 : 96);
  let outerSweep = $derived(ringCounts.outer >= 4 ? 150 : 120);

  // The dial is a floating overlay and need not be centred on the button.
  // Clamp the arc origin into a safe horizontal band so a full-width arc
  // clears both viewport edges; the vertical origin stays on the button
  // so the dial still visually erupts from it.
  let safeOriginX = $derived.by(() => {
    if (typeof window === 'undefined') return originX;
    const vw = window.innerWidth;
    const pad = OUTER_RADIUS + EDGE_MARGIN + 10;
    return Math.max(pad, Math.min(vw - pad, originX));
  });

  function buildArc(
    items: RadialReaction[],
    startIdx: number,
    radius: number,
    sweep: number,
    vw: number,
    vh: number,
    margin: number,
  ) {
    const count = items.length;
    const arcStart = 270 - sweep / 2;
    const step = count > 1 ? sweep / (count - 1) : 0;
    return items.map((r, k) => {
      const deg = count === 1 ? 270 : arcStart + k * step;
      const rad = (deg * Math.PI) / 180;
      const rawX = safeOriginX + radius * Math.cos(rad);
      const rawY = originY + radius * Math.sin(rad);
      const x = Math.min(Math.max(rawX, margin), vw - margin);
      const y = Math.min(Math.max(rawY, margin), vh - margin);
      return { ...r, x, y, ring: radius === INNER_RADIUS ? 0 : 1, globalIndex: startIdx + k };
    });
  }

  let positions = $derived.by(() => {
    const n = reactions.length;
    if (n === 0) return [];
    const vw = typeof window !== 'undefined' ? window.innerWidth : 9999;
    const vh = typeof window !== 'undefined' ? window.innerHeight : 9999;
    const margin = itemSize / 2 + EDGE_MARGIN;
    const { inner } = ringCounts;
    const innerItems = reactions.slice(0, inner);
    const outerItems = reactions.slice(inner);
    const inArc = buildArc(innerItems, 0, INNER_RADIUS, innerSweep, vw, vh, margin);
    const outArc =
      outerItems.length > 0
        ? buildArc(outerItems, inner, OUTER_RADIUS, outerSweep, vw, vh, margin)
        : [];
    return [...inArc, ...outArc];
  });

  // Nearest-bubble hit-test. The finger highlights whichever rendered
  // bubble it is closest to, once it has left the dead zone around the
  // button and is actually near a bubble. Robust to the viewport
  // clamping above, and spans both rings without special-casing.
  let activeIdx = $derived.by(() => {
    if (positions.length === 0) return -1;
    // Dead zone measured from the *button* (touch origin): a resting
    // finger always reads as "cancel", wherever the arc was shifted to.
    if (Math.hypot(touchX - originX, touchY - originY) < DEAD_ZONE_PX) return -1;

    let best = -1;
    let bestDist = Infinity;
    for (let i = 0; i < positions.length; i++) {
      const d = Math.hypot(touchX - positions[i].x, touchY - positions[i].y);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    // Require the finger within ~1.5 bubble-widths of the nearest bubble,
    // so drifting into empty space (or below the dial) cancels rather
    // than sticking to the closest edge item.
    return bestDist <= itemSize * 1.5 ? best : -1;
  });

  $effect(() => {
    highlightedType = activeIdx >= 0 ? positions[activeIdx].type : null;
  });

  // Mild haptic each time the highlighted emoji changes — gives the
  // user tactile confirmation as their finger sweeps across the arc.
  // Gracefully no-ops on iOS Safari, which doesn't expose vibrate().
  let lastHaptic = -1;
  $effect(() => {
    if (activeIdx !== lastHaptic) {
      lastHaptic = activeIdx;
      if (activeIdx >= 0 && typeof navigator !== 'undefined' && navigator.vibrate) {
        navigator.vibrate(8);
      }
    }
  });

  // Label sits just past the arc in the direction the arc points
  // (i.e. opposite the trigger). Clamped to the viewport so a label
  // for a long reaction shortcode never bleeds off-screen.
  let labelPos = $derived.by(() => {
    const vw = typeof window !== 'undefined' ? window.innerWidth : 9999;
    const dist = OUTER_RADIUS + 34;
    const rawX = safeOriginX;
    const rawY = originY - dist;
    return {
      x: Math.min(Math.max(rawX, 70), vw - 70),
      y: Math.max(rawY, 16),
    };
  });
</script>

<div class="radial-overlay" aria-hidden="true">
  <!-- Soft scrim so the underlying post fades a touch — makes the
       dial easier to focus on without obscuring the post entirely. -->
  <div class="radial-scrim"></div>

  <!-- Faint guide rings (inner + outer) to anchor the eye. -->
  <div
    class="radial-ring"
    style="left: {safeOriginX}px; top: {originY}px; width: {INNER_RADIUS * 2}px; height: {INNER_RADIUS * 2}px;"
  ></div>
  {#if ringCounts.outer > 0}
    <div
      class="radial-ring"
      style="left: {safeOriginX}px; top: {originY}px; width: {OUTER_RADIUS * 2}px; height: {OUTER_RADIUS * 2}px;"
    ></div>
  {/if}

  {#each positions as p, i (p.type)}
    <button
      type="button"
      class="radial-item"
      class:radial-item-active={i === activeIdx}
      style="left: {p.x}px; top: {p.y}px; width: {itemSize}px; height: {itemSize}px; animation-delay: {30 * i}ms;"
      aria-label={p.label}
      onpointerup={(e) => { e.stopPropagation(); onpick?.(p.type); }}
    >
      {#if p.image}
        <img class="radial-image" src={p.image} alt="" style="width: {emojiSize}px; height: {emojiSize}px;" />
      {:else}
        <span class="radial-emoji" style="font-size: {emojiSize}px;">{p.emoji}</span>
      {/if}
    </button>
  {/each}

  <!-- Label tag at the top of the dial showing what the user is
       about to pick. Hidden when in the dead zone so the user clearly
       sees they're cancelling. Position keeps it out of the finger's
       path and is clamped inside the viewport. -->
  {#if activeIdx >= 0}
    {@const label = positions[activeIdx].label}
    <div
      class="radial-label"
      style="left: {labelPos.x}px; top: {labelPos.y}px;"
    >
      {label}
    </div>
  {/if}
</div>

<style>
  .radial-overlay {
    position: fixed;
    inset: 0;
    z-index: 10000;
    /* Don't intercept touches — the like button's touchmove handler
       is the source of truth for where the finger is, and we don't
       want this overlay to swallow that event. */
    pointer-events: none;
    /* Belt and braces only. Because of `pointer-events: none` above,
       this overlay is transparent to selection hit-testing, so these
       rules protect the dial's own glyphs, not the post text beneath
       it. The post text is protected by cancelling touchstart on the
       like button, which suppresses the OS long-press gesture. */
    user-select: none;
    -webkit-user-select: none;
    -webkit-touch-callout: none;
    touch-action: none;
  }

  .radial-scrim {
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.18);
    backdrop-filter: blur(1px);
    -webkit-backdrop-filter: blur(1px);
    animation: scrim-in 120ms ease forwards;
  }

  .radial-ring {
    position: absolute;
    transform: translate(-50%, -50%);
    /* width / height are set inline; they scale with reaction count. */
    border-radius: 50%;
    border: 1px dashed rgba(255, 255, 255, 0.18);
    pointer-events: none;
    animation: ring-in 220ms cubic-bezier(0.22, 1, 0.36, 1) forwards;
  }

  .radial-item {
    position: absolute;
    /* Re-enable taps on the items themselves; the overlay and scrim stay
       pointer-events:none so a drag still falls through to the button's
       touch handlers. This is what lets an already-open dial be picked
       by a tap without breaking drag-to-pick. */
    pointer-events: auto;
    border: none;
    padding: 0;
    cursor: pointer;
    transform: translate(-50%, -50%) scale(0);
    /* width / height are set inline; they scale with reaction count. */
    border-radius: 50%;
    background: var(--color-surface-container-lowest, #fff);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 6px 16px rgba(0, 0, 0, 0.18);
    /* `opacity` doesn't transition cleanly with the pop animation;
       set start state via animation and let `transition` handle the
       active-scale-up afterward. */
    animation: pop-in 220ms cubic-bezier(0.22, 1, 0.36, 1) both;
    transition: transform 120ms cubic-bezier(0.34, 1.56, 0.64, 1),
      background 120ms ease,
      box-shadow 120ms ease;
  }

  .radial-item-active {
    transform: translate(-50%, -50%) scale(1.5);
    background: var(--color-primary-soft, #e0f2fe);
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.32);
    z-index: 1;
  }

  .radial-emoji {
    /* font-size is set inline; it scales with reaction count. */
    line-height: 1;
  }

  .radial-image {
    /* width / height are set inline; they scale with reaction count. */
    object-fit: contain;
  }

  .radial-label {
    position: absolute;
    transform: translate(-50%, -50%);
    padding: 4px 10px;
    font-size: 13px;
    font-weight: 600;
    color: #fff;
    background: rgba(0, 0, 0, 0.7);
    border-radius: 9999px;
    pointer-events: none;
    white-space: nowrap;
  }

  @keyframes scrim-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes ring-in {
    from { opacity: 0; transform: translate(-50%, -50%) scale(0.6); }
    to { opacity: 1; transform: translate(-50%, -50%) scale(1); }
  }

  @keyframes pop-in {
    from { opacity: 0; transform: translate(-50%, -50%) scale(0); }
    60% { opacity: 1; transform: translate(-50%, -50%) scale(1.15); }
    to { opacity: 1; transform: translate(-50%, -50%) scale(1); }
  }
</style>
