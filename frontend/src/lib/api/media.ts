import { api } from './client.js';
import type { MediaAttachment } from './types.js';

export function uploadMedia(file: File, description?: string): Promise<MediaAttachment> {
  const fields: Record<string, string> = {};
  // Backend field is alt_text; the API serializer still exposes it
  // as both `description` and `alt_text` for Mastodon API compat.
  if (description) fields.alt_text = description;
  return api.upload('/api/v1/media', file, fields);
}

export function updateMedia(id: string, data: { description?: string }): Promise<MediaAttachment> {
  return api.put(`/api/v1/media/${id}`, { alt_text: data.description ?? '' });
}
