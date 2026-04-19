<script lang="ts">
  import { fly } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  // Floating "N new posts" pill that pops into view from above the
  // viewport when new posts arrive, regardless of scroll position.
  // Click scrolls back to top and flushes the queued posts into the
  // feed. Animated counter + water-ripple on every count bump.
  //
  // Position is `fixed` under the site header, horizontally centred.
  // Previously it was inline inside the page's sticky bar, which
  // meant a user scrolled halfway down the feed never saw it until
  // they scrolled back up — defeating the point of the alert.

  let {
    count = 0,
    onclick
  }: {
    count: number;
    onclick?: () => void;
  } = $props();

  // Display clamps to "10+" so the pill keeps a stable width even
  // when a burst of events fills the queue faster than the user can
  // click.
  let display = $derived(count >= 10 ? '10+' : String(count));
  let label = $derived(count === 1 ? 'post' : 'posts');

  // Ripple key increments on every display change and remounts the
  // ripple overlay via {#key}. That restarts the CSS animation from
  // t=0 so the effect fires fresh each time — perceived as a water
  // surface disturbed by the new digit landing.
  let rippleKey = $state(0);
  let firstRender = true;

  $effect(() => {
    display; // track
    if (firstRender) {
      firstRender = false;
      return;
    }
    rippleKey++;
  });
</script>

{#if count > 0}
  <!-- Fixed floater: always visible regardless of scroll. The
       parent element is the thing that enters/exits; the pill
       inside handles the per-count ripple. -->
  <div
    class="npb-floater"
    in:fly={{ y: -24, duration: 280, easing: cubicOut }}
    out:fly={{ y: -24, duration: 180, easing: cubicOut }}
  >
    <button type="button" class="npb" onclick={() => onclick?.()} aria-label="{display} new {label}. Scroll to top to view.">
      {#key rippleKey}
        <span class="npb-ripple" aria-hidden="true"></span>
      {/key}

      <span class="material-symbols-outlined npb-arrow" aria-hidden="true">arrow_upward</span>

      <span class="npb-num-slot" aria-hidden="true">
        {#each [display] as n (n)}
          <span
            class="npb-num"
            in:fly={{ y: 18, duration: 320, easing: cubicOut }}
            out:fly={{ y: -18, duration: 320, easing: cubicOut }}
          >{n}</span>
        {/each}
      </span>

      <span class="npb-label">new {label}</span>
    </button>
  </div>
{/if}

<style>
  .npb-floater {
    position: fixed;
    /* Sits just below the site header, horizontally centred. `left:
       50%` + `translateX(-50%)` keeps the pill width natural instead
       of stretching. z-index is above the sticky tab row so it
       floats over everything but stays below full-screen modals
       (those use 1000+). */
    inset-block-start: calc(var(--header-height) + 12px);
    inset-inline-start: 50%;
    transform: translateX(-50%);
    z-index: 50;
    pointer-events: none;
  }

  .npb {
    pointer-events: auto;
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 10px 22px;
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    border: none;
    border-radius: 9999px;
    font-size: var(--text-sm, 0.9rem);
    font-weight: 700;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22), 0 2px 6px rgba(0, 0, 0, 0.12);
    transition: transform 160ms ease, box-shadow 160ms ease;
  }

  .npb:hover {
    transform: translateY(-1px);
    box-shadow: 0 14px 34px rgba(0, 0, 0, 0.26), 0 3px 8px rgba(0, 0, 0, 0.14);
  }

  .npb:active {
    transform: translateY(0);
  }

  .npb-arrow {
    font-size: 18px;
    position: relative;
    z-index: 1;
  }

  .npb-num-slot {
    position: relative;
    display: inline-grid;
    grid-template-areas: 'n';
    min-width: 2.2ch;
    text-align: center;
    z-index: 1;
  }

  .npb-num {
    grid-area: n;
    font-variant-numeric: tabular-nums;
  }

  .npb-label {
    position: relative;
    z-index: 1;
  }

  .npb-ripple {
    position: absolute;
    inset: 50% 50% auto auto;
    width: 40px;
    height: 40px;
    margin: -20px -20px 0 0;
    border-radius: 50%;
    background: radial-gradient(
      circle,
      rgba(255, 255, 255, 0.6) 0%,
      rgba(255, 255, 255, 0.3) 40%,
      rgba(255, 255, 255, 0) 75%
    );
    pointer-events: none;
    transform-origin: center;
    animation: npb-ripple 700ms cubic-bezier(0.22, 0.8, 0.36, 1) forwards;
    z-index: 0;
  }

  @keyframes npb-ripple {
    0%   { transform: scale(0);   opacity: 0.9; }
    60%  { opacity: 0.6; }
    100% { transform: scale(9);   opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .npb,
    .npb-ripple,
    .npb-num {
      animation: none !important;
      transition: none !important;
    }
  }
</style>
