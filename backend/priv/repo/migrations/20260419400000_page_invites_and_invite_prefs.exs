defmodule Hybridsocial.Repo.Migrations.PageInvitesAndInvitePrefs do
  use Ecto.Migration

  @moduledoc """
  Adds the page-invite table (mirroring `group_invites`) plus two
  per-identity preferences that gate invite delivery at the database
  level — not just in notification volume.

  Values for the prefs: "anyone" (default, today's behaviour),
  "only_follows" (only users the recipient follows can invite them),
  and "nobody" (no invites accepted at all). Stored as strings rather
  than enums so admins / users can tune without a migration if we
  add a fourth option later.
  """

  def change do
    alter table(:identities) do
      add :allow_group_invites, :string, default: "anyone", null: false
      add :allow_page_invites, :string, default: "anyone", null: false
    end

    create table(:page_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :page_id,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          null: false

      add :invited_by,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          null: false

      add :invited_id,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          null: false

      # pending → accepted | declined
      add :status, :string, default: "pending", null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:page_invites, [:page_id, :invited_id])
    create index(:page_invites, [:invited_id, :status])
  end
end
