import { redirect } from '@sveltejs/kit';

// Blocks + Mutes were merged into a single "Blocked & muted" page.
export const load = () => {
  redirect(307, '/settings/blocks');
};
