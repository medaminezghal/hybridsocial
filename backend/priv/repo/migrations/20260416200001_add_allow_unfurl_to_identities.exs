defmodule Hybridsocial.Repo.Migrations.AddAllowUnfurlToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      # Controls whether social crawlers (FacebookExternalHit, TelegramBot,
      # etc.) see full profile info when unfurling a /@handle link on
      # external platforms. Default true — opt-out, not opt-in.
      add :allow_unfurl, :boolean, null: false, default: true
    end
  end
end
