<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAdminSettings, updateAdminSettings } from '$lib/api/admin.js';

  // These identity fields live in the generic Config store (keys below),
  // not the theme_* namespace. They used to be edited on the Theme page;
  // this page owns them now and writes them through the settings API.
  let instanceName = $state('');
  let instanceDescription = $state('');
  let contactEmail = $state('');

  let loading = $state(true);
  let saving = $state(false);

  async function load() {
    try {
      const settings = await getAdminSettings();
      const map = new Map(settings.map((s) => [s.key, s.value]));
      instanceName = (map.get('instance_name') as string) ?? '';
      instanceDescription = (map.get('instance_description') as string) ?? '';
      contactEmail = (map.get('contact_email') as string) ?? '';
    } catch {
      addToast('Failed to load instance settings', 'error');
    } finally {
      loading = false;
    }
  }

  async function handleSave() {
    saving = true;
    try {
      await updateAdminSettings([
        { key: 'instance_name', value: instanceName },
        { key: 'instance_description', value: instanceDescription },
        { key: 'contact_email', value: contactEmail },
      ]);
      addToast('Instance settings saved', 'success');
    } catch {
      addToast('Failed to save instance settings', 'error');
    } finally {
      saving = false;
    }
  }

  onMount(load);
</script>

<svelte:head>
  <title>General - Admin</title>
</svelte:head>

<div class="general-page">
  <div class="general-header">
    <div>
      <h1 class="page-title">General</h1>
      <p class="general-subtitle">
        Your server's public identity. The name and description appear in the header,
        page titles, federation profile, and outgoing emails.
      </p>
    </div>
    <button class="btn btn-primary" onclick={handleSave} disabled={saving || loading}>
      {saving ? 'Saving…' : 'Save changes'}
    </button>
  </div>

  {#if loading}
    <div class="general-loading">Loading…</div>
  {:else}
    <div class="general-card card">
      <div class="general-field">
        <label class="field-label" for="instance-name">Instance name</label>
        <input
          id="instance-name"
          type="text"
          class="input"
          bind:value={instanceName}
          placeholder="HybridSocial"
        />
        <p class="field-hint">Shown in the header, browser tab titles, and emails.</p>
      </div>

      <div class="general-field">
        <label class="field-label" for="instance-desc">Description</label>
        <textarea
          id="instance-desc"
          class="textarea"
          rows="4"
          bind:value={instanceDescription}
          placeholder="A short description of what this server is about."
        ></textarea>
        <p class="field-hint">Used on the about page, link previews, and your federation profile.</p>
      </div>

      <div class="general-field">
        <label class="field-label" for="contact-email">Contact email</label>
        <input
          id="contact-email"
          type="email"
          class="input"
          bind:value={contactEmail}
          placeholder="admin@example.com"
        />
        <p class="field-hint">Where members and other servers can reach the operator.</p>
      </div>
    </div>
  {/if}
</div>

<style>
  .general-page {
    max-width: 720px;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .general-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin: 0 0 4px;
    color: var(--color-text);
  }

  .general-subtitle {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    max-width: 52ch;
    line-height: 1.5;
  }

  .general-loading {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    padding: var(--space-6) 0;
  }

  .general-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
    padding: var(--space-6);
  }

  .general-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .field-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .field-hint {
    margin: 0;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.4;
  }
</style>
