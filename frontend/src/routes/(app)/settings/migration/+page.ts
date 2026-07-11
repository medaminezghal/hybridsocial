import { redirect } from '@sveltejs/kit';

// Migration was merged into the "Move / back up account" page (import-export).
export const load = () => {
  redirect(307, '/settings/import-export');
};
