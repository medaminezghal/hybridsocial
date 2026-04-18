defmodule Hybridsocial.Repo.Migrations.AllowNilMediaStoragePath do
  use Ecto.Migration

  @moduledoc """
  `media.storage_path` was NOT NULL, but a remote attachment ingested
  via /inbox legitimately has no local path — it lives on the origin
  server until the media proxy caches it on first request. The insert
  was failing silently inside persist_remote_attachments/3, so every
  remote post's images/videos were dropped on ingest. Relaxing the
  constraint lets the row exist with storage_path = NULL; the media
  proxy + Media.media_url/1 already know how to handle that case.
  """

  def change do
    alter table(:media) do
      modify :storage_path, :string, null: true, from: {:string, null: false}
    end
  end
end
