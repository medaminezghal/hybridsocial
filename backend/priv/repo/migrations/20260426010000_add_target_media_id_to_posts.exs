defmodule Hybridsocial.Repo.Migrations.AddTargetMediaIdToPosts do
  use Ecto.Migration

  @moduledoc """
  Lets a reply target a specific media attachment on the parent post,
  not just the post as a whole. A multi-image post can now have a
  separate comment thread per image. Nullable: every reply that
  doesn't target a specific image leaves this null and behaves as
  before.

  on_delete: :nilify_all — if an admin or the author removes the
  attachment, replies that pointed at it survive but lose their
  per-image targeting (they fall back to the post-level thread).

  Index on (parent_id, target_media_id) supports the common query
  shape: "list replies for post X, optionally filtered by media".
  """

  def change do
    alter table(:posts) do
      add :target_media_id, references(:media, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:posts, [:parent_id, :target_media_id])
  end
end
