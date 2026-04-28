// One-of-N popover coordinator: each PostActions instance writes its
// own id when it opens its ⋯ menu and clears when it closes. Other
// instances subscribe and close as soon as the active id stops being
// theirs, so two post menus can never be open at once. A `null` value
// means no menu is open — also the signal that a window-level click
// outside dismissed everything.

import { writable } from 'svelte/store';

export const openMenuId = writable<string | null>(null);
