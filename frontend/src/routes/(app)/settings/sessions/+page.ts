import { redirect } from '@sveltejs/kit';

// Sessions was merged into the Security page.
export const load = () => {
  redirect(307, '/settings/security');
};
