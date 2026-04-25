defmodule Hybridsocial.Repo.Migrations.AddLocationToIdentities do
  use Ecto.Migration

  @moduledoc """
  Adds `location` to identities so a user can publish their general
  location alongside birthday + bio. Custom profile fields (free-form
  key/value pairs, capped per tier via TierLimits.profile_fields)
  reuse the existing `metadata` JSONB column under
  `metadata['profile_fields']` — no new column needed for that.
  """

  def change do
    alter table(:identities) do
      add :location, :string
    end
  end
end
