<script lang="ts">
  // The old tab bar here duplicated navigation now handled by the grouped
  // admin sidebar (see $lib/admin-nav.ts), and it filed content catalogs
  // like Tiers/Badges under "User management" where they didn't belong.
  // These routes keep their URLs but are reached through the sidebar, so
  // this layout is now a plain pass-through. Pending Approvals/Appeals
  // counts moved to the sidebar rail.
  let { children } = $props();
</script>

{@render children()}
