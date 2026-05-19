<script lang="ts">
  // Per-bot outbound webhook panel. Mounted inside each bot card on
  // the Developer Tools page. Three states: collapsed, expanded-no-url,
  // expanded-with-url. Setting a URL returns the signing secret once;
  // we display it inline with a copy button and a warning that it
  // won't reappear after the panel is collapsed or the page navigates.

  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';

  interface Delivery {
    id: string;
    event: string;
    status: 'pending' | 'delivered' | 'failed';
    attempts: number;
    last_status_code: number | null;
    last_error: string | null;
    webhook_url: string;
    next_attempt_at: string;
    delivered_at: string | null;
    created_at: string;
  }

  let { botId }: { botId: string } = $props();

  let expanded = $state(false);
  let urlInput = $state('');
  let currentUrl = $state<string | null>(null);
  let secretJustShown = $state<string | null>(null);
  let saving = $state(false);
  let clearing = $state(false);
  let deliveries = $state<Delivery[]>([]);
  let deliveriesLoaded = $state(false);
  let deliveriesLoading = $state(false);

  // The bot listing endpoint doesn't include webhook_url today (the
  // schema field exists but is treated as private config). To keep
  // the change surface small we just probe on expand and treat an
  // empty list of deliveries as "probably no webhook configured" —
  // good enough for the UI's purposes.
  async function expand() {
    expanded = !expanded;
    if (expanded && !deliveriesLoaded) {
      await loadDeliveries();
    }
  }

  async function loadDeliveries() {
    deliveriesLoading = true;
    try {
      deliveries = await api.get<Delivery[]>(`/api/v1/bots/${botId}/webhook/deliveries`);
      deliveriesLoaded = true;
      // Snapshot the URL from the most recent delivery so the panel
      // can show "currently posting to <url>" without a separate
      // endpoint. Server-side that's the URL at enqueue time — if the
      // owner has since changed it, the next event will reveal the
      // new URL.
      if (deliveries.length > 0) {
        currentUrl = deliveries[0].webhook_url;
      }
    } catch {
      addToast('Could not load webhook deliveries', 'error');
    } finally {
      deliveriesLoading = false;
    }
  }

  async function saveUrl() {
    if (!urlInput.trim()) return;
    saving = true;
    try {
      const res = await api.put<{ webhook_url: string; signing_secret: string }>(
        `/api/v1/bots/${botId}/webhook`,
        { url: urlInput.trim() },
      );
      currentUrl = res.webhook_url;
      secretJustShown = res.signing_secret;
      urlInput = '';
      addToast('Webhook saved — copy the signing secret now', 'success');
      // Refresh delivery list (likely still empty but keeps state consistent).
      void loadDeliveries();
    } catch (err) {
      const msg = (err as { body?: { error?: string }; message?: string })?.body?.error
        || (err as { message?: string })?.message
        || 'Could not save webhook';
      addToast(msg, 'error');
    } finally {
      saving = false;
    }
  }

  async function clearWebhook() {
    if (!confirm('Remove this webhook? Pending deliveries will be cancelled.')) return;
    clearing = true;
    try {
      await api.delete(`/api/v1/bots/${botId}/webhook`);
      currentUrl = null;
      secretJustShown = null;
      addToast('Webhook removed', 'success');
    } catch {
      addToast('Could not remove webhook', 'error');
    } finally {
      clearing = false;
    }
  }

  function copyText(text: string) {
    navigator.clipboard.writeText(text).then(
      () => addToast('Copied', 'success'),
      () => addToast('Copy failed', 'error'),
    );
  }

  function statusLabel(s: Delivery['status']): string {
    return s === 'delivered' ? 'Delivered' : s === 'pending' ? 'Pending' : 'Failed';
  }
</script>

<div class="webhook-panel">
  <button
    type="button"
    class="webhook-toggle"
    aria-expanded={expanded}
    onclick={expand}
  >
    <span class="material-symbols-outlined" style="font-size: 18px">webhook</span>
    Webhook
    {#if currentUrl}
      <span class="webhook-pill">configured</span>
    {/if}
    <span class="material-symbols-outlined" style="font-size: 18px; margin-inline-start: auto">
      {expanded ? 'expand_less' : 'expand_more'}
    </span>
  </button>

  {#if expanded}
    <div class="webhook-body">
      <p class="webhook-help">
        Receive a signed HTTP POST whenever something happens to this bot —
        a mention, reply, reaction, new follower, or DM. See
        <a href="/help/developers#webhooks">the docs</a> for the payload
        shape and how to verify the signature.
      </p>

      {#if currentUrl}
        <div class="webhook-current">
          <span class="webhook-current-label">Posting to</span>
          <code class="webhook-current-url">{currentUrl}</code>
          <button
            type="button"
            class="btn btn-sm btn-danger-outline"
            disabled={clearing}
            onclick={clearWebhook}
          >
            {clearing ? '…' : 'Remove'}
          </button>
        </div>
      {/if}

      {#if secretJustShown}
        <div class="webhook-secret-card">
          <p class="webhook-secret-label">
            <span class="material-symbols-outlined" style="font-size: 18px; color: var(--color-warning)">warning</span>
            Save this signing secret now. It won't be shown again.
          </p>
          <div class="webhook-secret-row">
            <code class="webhook-secret-value">{secretJustShown}</code>
            <button type="button" class="copy-btn" onclick={() => copyText(secretJustShown!)}>
              <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
            </button>
          </div>
        </div>
      {/if}

      <form
        class="webhook-form"
        onsubmit={(e) => { e.preventDefault(); void saveUrl(); }}
      >
        <label class="webhook-label">
          {currentUrl ? 'Change URL' : 'Webhook URL'}
          <input
            type="url"
            class="input"
            placeholder="https://your-bot.example.com/webhooks/hybridsocial"
            bind:value={urlInput}
            required
          />
        </label>
        <button
          type="submit"
          class="btn btn-primary btn-sm"
          disabled={saving || !urlInput.trim()}
        >
          {saving ? 'Saving…' : currentUrl ? 'Update & rotate secret' : 'Save'}
        </button>
      </form>

      <h4 class="webhook-subtitle">Recent deliveries</h4>
      {#if deliveriesLoading}
        <p class="webhook-muted">Loading…</p>
      {:else if deliveries.length === 0}
        <p class="webhook-muted">No deliveries yet.</p>
      {:else}
        <ul class="webhook-deliveries">
          {#each deliveries as d (d.id)}
            <li class="webhook-delivery">
              <span class="status-pill status-{d.status}">{statusLabel(d.status)}</span>
              <span class="delivery-event">{d.event}</span>
              <span class="delivery-time">{new Date(d.created_at).toLocaleString()}</span>
              {#if d.status === 'delivered'}
                <span class="delivery-code">{d.last_status_code}</span>
              {:else if d.status === 'failed'}
                <span class="delivery-code">{d.last_status_code ?? '—'}</span>
                {#if d.last_error}
                  <span class="delivery-error" title={d.last_error}>{d.last_error}</span>
                {/if}
              {:else}
                <span class="delivery-code">attempt {d.attempts + 1}/3</span>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {/if}
</div>

<style>
  .webhook-panel {
    margin-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
    padding-block-start: var(--space-3);
  }

  .webhook-toggle {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-1) 0;
    background: transparent;
    border: none;
    color: var(--color-text);
    cursor: pointer;
    font: inherit;
    font-weight: 600;
  }

  .webhook-pill {
    padding: 2px 8px;
    border-radius: var(--radius-full);
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: var(--text-xs);
    font-weight: 600;
  }

  .webhook-body {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    padding-block-start: var(--space-3);
  }

  .webhook-help {
    margin: 0;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    line-height: 1.5;
  }

  .webhook-help a {
    color: var(--color-primary);
  }

  .webhook-current {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    flex-wrap: wrap;
  }

  .webhook-current-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .webhook-current-url {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.85rem;
  }

  .webhook-secret-card {
    padding: var(--space-3);
    background: color-mix(in srgb, var(--color-warning) 8%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-warning) 30%, transparent);
    border-radius: var(--radius-md);
  }

  .webhook-secret-label {
    margin: 0 0 var(--space-2) 0;
    display: flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .webhook-secret-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .webhook-secret-value {
    flex: 1;
    padding: var(--space-1) var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-sm);
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.8rem;
    word-break: break-all;
  }

  .copy-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: 1px solid var(--color-border);
    background: var(--color-surface-raised);
    border-radius: var(--radius-sm);
    cursor: pointer;
    color: var(--color-text-secondary);
  }

  .webhook-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .webhook-label {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .webhook-form .btn {
    align-self: flex-start;
  }

  .webhook-subtitle {
    margin: var(--space-3) 0 var(--space-1) 0;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .webhook-muted {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    margin: 0;
  }

  .webhook-deliveries {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .webhook-delivery {
    display: grid;
    grid-template-columns: auto 1fr auto auto;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-1) var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
  }

  .status-pill {
    padding: 2px 8px;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .status-delivered {
    background: color-mix(in srgb, var(--color-success) 18%, transparent);
    color: var(--color-success);
  }

  .status-pending {
    background: color-mix(in srgb, var(--color-text-secondary) 18%, transparent);
    color: var(--color-text-secondary);
  }

  .status-failed {
    background: color-mix(in srgb, var(--color-danger) 18%, transparent);
    color: var(--color-danger);
  }

  .delivery-event {
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.85em;
  }

  .delivery-time {
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
  }

  .delivery-code {
    color: var(--color-text-secondary);
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.85em;
  }

  .delivery-error {
    grid-column: 1 / -1;
    color: var(--color-danger);
    font-size: var(--text-xs);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
