<script lang="ts">
  import { onMount } from 'svelte';

  interface Slide {
    url: string;
    alt?: string | null;
    /** Media attachment id — required for the per-image reply button. */
    id?: string;
    /** Server-reported reaction count for this image (Instagram-style). */
    reactionCount?: number;
    /** Whether the viewer has already reacted to this image. */
    reacted?: boolean;
  }

  let {
    images,
    index = $bindable(0),
    onclose,
    onreply,
    onreact,
  }: {
    images: Slide[];
    index?: number;
    onclose: () => void;
    /**
     * If supplied, the lightbox surfaces a "Reply to this image"
     * button. Receives the targeted media's id and its 1-based index
     * within the parent post's gallery so the composer can show a
     * thumbnail + label and submit `target_media_id`.
     */
    onreply?: (mediaId: string, mediaIndex: number) => void;
    /**
     * Instagram-style heart on the lightbox image. Receives the
     * targeted media's id and the next desired state. Caller is
     * expected to POST/DELETE /api/v1/statuses/:id/react with
     * target_media_id and update the slide's reactionCount /
     * reacted flag.
     */
    onreact?: (mediaId: string, next: boolean) => void;
  } = $props();

  let zoomed = $state(false);
  // Instagram-style double-tap-to-like: when the user taps the image
  // twice in quick succession AND the host wired up onreact, fire the
  // reaction and play a heart-burst animation tied to the image.
  let lastTapAt = $state(0);
  let burstAt = $state(0);

  let current = $derived(images[index] ?? images[0]);
  let hasPrev = $derived(index > 0);
  let hasNext = $derived(index < images.length - 1);

  function close() {
    onclose();
  }

  function prev() {
    if (hasPrev) {
      index = index - 1;
      zoomed = false;
    }
  }

  function next() {
    if (hasNext) {
      index = index + 1;
      zoomed = false;
    }
  }

  function toggleZoom() {
    zoomed = !zoomed;
  }

  function handleImageTap() {
    const now = performance.now();
    // 320ms is the standard double-tap window; longer than that and we
    // treat it as two separate single taps (which fall through to the
    // default zoom-toggle behaviour below).
    const isDoubleTap = now - lastTapAt < 320;
    lastTapAt = now;

    if (isDoubleTap && onreact && current?.id && !current.reacted) {
      onreact(current.id, true);
      burstAt = now;
      return;
    }

    if (!isDoubleTap) {
      toggleZoom();
    }
  }

  async function download() {
    // Same-origin images can be triggered via <a download>. Remote
    // images might be blocked by CORS or content-disposition; fall
    // back to opening in a new tab so the user can save manually.
    try {
      const res = await fetch(current.url, { mode: 'cors' });
      const blob = await res.blob();
      const objUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = objUrl;
      a.download = current.url.split('/').pop()?.split('?')[0] || 'image';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(objUrl), 1000);
    } catch {
      window.open(current.url, '_blank', 'noopener,noreferrer');
    }
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') prev();
    else if (e.key === 'ArrowRight') next();
    else if (e.key === ' ' || e.key.toLowerCase() === 'z') {
      e.preventDefault();
      toggleZoom();
    }
  }

  onMount(() => {
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', handleKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', handleKey);
    };
  });

  function handleBackdropClick(e: MouseEvent) {
    // Only close if the click was on the backdrop itself, not on a
    // descendant control (zoom/download buttons) or the image.
    if (e.target === e.currentTarget) close();
  }
</script>

<div
  class="lightbox"
  role="dialog"
  aria-modal="true"
  aria-label="Image viewer"
  onclick={handleBackdropClick}
>
  <div class="lightbox-tools-left">
    <button
      type="button"
      class="lightbox-btn"
      onclick={toggleZoom}
      aria-label={zoomed ? 'Fit to screen' : 'Zoom to full size'}
    >
      <span class="material-symbols-outlined">
        {zoomed ? 'zoom_out_map' : 'zoom_in'}
      </span>
    </button>
    <button
      type="button"
      class="lightbox-btn"
      onclick={download}
      aria-label="Download image"
    >
      <span class="material-symbols-outlined">download</span>
    </button>
    {#if onreact && current?.id}
      <button
        type="button"
        class="lightbox-btn lightbox-btn-react"
        class:lightbox-btn-reacted={current.reacted}
        onclick={() => onreact!(current.id!, !current.reacted)}
        aria-label={current.reacted ? 'Remove reaction' : 'React to this image'}
        title={current.reacted ? 'Remove reaction' : 'React to this image'}
      >
        <span class="material-symbols-outlined" class:material-symbols-filled={current.reacted}>
          favorite
        </span>
        {#if current.reactionCount && current.reactionCount > 0}
          <span class="lightbox-react-count">{current.reactionCount}</span>
        {/if}
      </button>
    {/if}
    {#if onreply && current?.id}
      <button
        type="button"
        class="lightbox-btn"
        onclick={() => onreply!(current.id!, index + 1)}
        aria-label="Reply to this image"
        title="Reply to this image"
      >
        <span class="material-symbols-outlined">comment</span>
      </button>
    {/if}
  </div>

  <button
    type="button"
    class="lightbox-btn lightbox-close"
    onclick={close}
    aria-label="Close"
  >
    <span class="material-symbols-outlined">close</span>
  </button>

  {#if hasPrev}
    <button type="button" class="lightbox-nav lightbox-nav-prev" onclick={prev} aria-label="Previous image">
      <span class="material-symbols-outlined">chevron_left</span>
    </button>
  {/if}
  {#if hasNext}
    <button type="button" class="lightbox-nav lightbox-nav-next" onclick={next} aria-label="Next image">
      <span class="material-symbols-outlined">chevron_right</span>
    </button>
  {/if}

  <div
    class="lightbox-stage"
    class:lightbox-stage-zoomed={zoomed}
    role="presentation"
    onclick={handleBackdropClick}
  >
    <img
      src={current.url}
      alt={current.alt || ''}
      class="lightbox-img"
      class:lightbox-img-zoomed={zoomed}
      draggable="false"
      onclick={(e) => { e.stopPropagation(); handleImageTap(); }}
    />
    {#if burstAt > 0}
      {#key burstAt}
        <span class="lightbox-burst" aria-hidden="true">
          <span class="material-symbols-outlined material-symbols-filled">favorite</span>
        </span>
      {/key}
    {/if}
  </div>

  {#if images.length > 1}
    <div class="lightbox-counter" aria-live="polite">
      {index + 1} / {images.length}
    </div>
  {/if}
</div>

<style>
  .lightbox {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.92);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
    z-index: 10000;
    display: flex;
    align-items: center;
    justify-content: center;
    animation: lightbox-fade 0.15s ease;
  }

  @keyframes lightbox-fade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .lightbox-stage {
    max-width: 100vw;
    max-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 40px;
  }

  .lightbox-stage-zoomed {
    overflow: auto;
    cursor: zoom-out;
    padding: 0;
    align-items: flex-start;
  }

  .lightbox-img {
    max-width: calc(100vw - 80px);
    max-height: calc(100vh - 80px);
    object-fit: contain;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
    user-select: none;
    cursor: zoom-in;
  }

  .lightbox-img-zoomed {
    max-width: none;
    max-height: none;
    cursor: zoom-out;
  }

  .lightbox-tools-left {
    position: fixed;
    top: 16px;
    left: 16px;
    display: flex;
    gap: 8px;
    z-index: 2;
  }

  .lightbox-close {
    position: fixed;
    top: 16px;
    right: 16px;
    z-index: 2;
  }

  .lightbox-btn {
    width: 40px;
    height: 40px;
    border-radius: 9999px;
    border: none;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: background 0.15s ease, transform 0.15s ease;
  }

  .lightbox-btn:hover {
    background: rgba(0, 0, 0, 0.8);
  }

  .lightbox-btn:active {
    transform: scale(0.96);
  }

  .lightbox-btn :global(.material-symbols-outlined) {
    font-size: 22px;
  }

  .lightbox-nav {
    position: fixed;
    top: 50%;
    transform: translateY(-50%);
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    border: none;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    z-index: 2;
  }

  .lightbox-nav:hover {
    background: rgba(0, 0, 0, 0.8);
  }

  .lightbox-nav-prev { left: 16px; }
  .lightbox-nav-next { right: 16px; }

  .lightbox-nav :global(.material-symbols-outlined) {
    font-size: 28px;
  }

  .lightbox-counter {
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0, 0, 0, 0.6);
    color: #fff;
    padding: 6px 12px;
    border-radius: 9999px;
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
    z-index: 2;
  }

  /* Heart button: round count chip when count > 0, otherwise just the
     icon. The reacted state colours the icon red and draws it filled. */
  .lightbox-btn-react {
    width: auto;
    min-width: 40px;
    padding-inline: 12px;
    gap: 6px;
  }

  .lightbox-btn-reacted {
    color: var(--color-danger, #f0506e);
  }

  .lightbox-btn-reacted :global(.material-symbols-outlined) {
    font-variation-settings: 'FILL' 1;
  }

  .lightbox-react-count {
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  /* Double-tap heart burst — pops above the image, fades out fast. */
  .lightbox-burst {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    z-index: 3;
    animation: lightbox-burst 0.85s cubic-bezier(0.22, 1, 0.36, 1) forwards;
  }

  .lightbox-burst :global(.material-symbols-outlined) {
    font-size: 140px;
    color: rgba(255, 255, 255, 0.95);
    text-shadow: 0 6px 30px rgba(0, 0, 0, 0.5);
    font-variation-settings: 'FILL' 1;
  }

  @keyframes lightbox-burst {
    0%   { opacity: 0; transform: scale(0.4); }
    25%  { opacity: 1; transform: scale(1.15); }
    60%  { opacity: 1; transform: scale(1); }
    100% { opacity: 0; transform: scale(0.95); }
  }
</style>
