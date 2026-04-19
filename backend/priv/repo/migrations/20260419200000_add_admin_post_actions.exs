defmodule Hybridsocial.Repo.Migrations.AddAdminPostActions do
  use Ecto.Migration

  @moduledoc """
  Two new admin moderation actions on posts:

    * Hide from public feeds — softer than deletion: the post stays
      (permalink still resolves, existing replies visible) but it
      drops out of /explore, local timelines, and the author's
      public profile feed. For borderline content where a full
      delete feels excessive.

    * Lock replies — prevent new replies to this post or thread
      without touching existing ones. For pile-on situations.

  Both track WHO and WHEN for the audit trail; timeline/reply checks
  only look at the timestamps. `hidden_by` / `replies_locked_by` are
  FK-free because we want them to outlive the admin's account if the
  admin is later deleted.
  """

  def change do
    alter table(:posts) do
      add :hidden_at, :utc_datetime_usec
      add :hidden_by, :binary_id
      add :replies_locked_at, :utc_datetime_usec
      add :replies_locked_by, :binary_id
    end

    # Feeds filter by `is_nil(hidden_at)` on every public timeline;
    # the partial index keeps the filter cheap even on very large
    # tables because the non-null rows are rare by construction.
    create index(:posts, [:hidden_at], where: "hidden_at IS NOT NULL")
  end
end
