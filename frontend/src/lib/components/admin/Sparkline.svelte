<script lang="ts">
  // Hand-rolled SVG sparkline. No external dep — the data shape is
  // simple (1h × ~60 points × 22 series) and a real chart lib would
  // dwarf the payload it renders. If the dashboard grows beyond a
  // single tab of small charts we can swap to uPlot.

  type Point = { t: string; v: number };

  let {
    points = [],
    width = 120,
    height = 28,
    color = 'var(--color-primary)',
  }: {
    points?: Point[];
    width?: number;
    height?: number;
    color?: string;
  } = $props();

  // While the collector is still warming up (or a window happens to
  // catch a quiet period) a 2- or 3-point line gets drawn corner to
  // corner, which looks like noise. Suppress until we have enough
  // points to read as a trend.
  const MIN_POINTS = 5;

  let path = $derived.by(() => {
    if (!points || points.length < MIN_POINTS) return '';
    let min = Infinity;
    let max = -Infinity;
    for (const p of points) {
      if (p.v < min) min = p.v;
      if (p.v > max) max = p.v;
    }
    const range = max - min;

    // Y-axis padding: without it, any non-zero variation gets stretched
    // to the full sparkline height, so a 1-byte change in DB size
    // looks identical to a 10x spike. Floor the visible range at 5%
    // of |max| (or 1 if max is 0) so tiny noise reads as flat-ish.
    const headroom = Math.max(Math.abs(max) * 0.05, 1);
    const visibleRange = Math.max(range, headroom);
    const visibleMin = (min + max) / 2 - visibleRange / 2;

    const stepX = width / (points.length - 1);
    let d = '';
    for (let i = 0; i < points.length; i++) {
      const x = i * stepX;
      const norm = (points[i].v - visibleMin) / visibleRange;
      const y = height - norm * height;
      d += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ',' + y.toFixed(1) + ' ';
    }
    return d.trim();
  });

  let warmingUp = $derived(!!points && points.length > 0 && points.length < MIN_POINTS);
</script>

{#if path}
  <svg
    class="sparkline"
    {width}
    {height}
    viewBox="0 0 {width} {height}"
    preserveAspectRatio="none"
    aria-hidden="true"
  >
    <path d={path} fill="none" stroke={color} stroke-width="1.5" stroke-linejoin="round" />
  </svg>
{:else if warmingUp}
  <span class="sparkline-warmup" title="Collecting samples — needs ~5 minutes" aria-hidden="true">···</span>
{:else}
  <span class="sparkline-empty" aria-hidden="true">—</span>
{/if}

<style>
  .sparkline {
    display: block;
    overflow: visible;
  }

  .sparkline-empty {
    color: var(--color-text-tertiary);
    font-size: 0.75rem;
  }

  .sparkline-warmup {
    color: var(--color-text-tertiary);
    font-size: 1rem;
    letter-spacing: 2px;
    font-weight: 700;
  }
</style>
