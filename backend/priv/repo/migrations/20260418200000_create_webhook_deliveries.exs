defmodule Hybridsocial.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  @moduledoc """
  Persistent queue for webhook delivery attempts. Inserting a row is
  the admin API's only side-effect at fire time; a background worker
  drains the queue and retries with exponential backoff, so a
  flapping receiver doesn't silently lose events.
  """

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :webhook_id,
          references(:moderation_webhooks, type: :binary_id, on_delete: :delete_all),
          null: false

      add :event, :string, null: false
      add :payload, :map, null: false

      # pending → delivered | failed
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :last_error, :text
      add :last_status_code, :integer
      add :delivered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Worker pulls the oldest `pending` rows whose next_attempt_at has
    # passed. This index covers that hot query.
    create index(:webhook_deliveries, [:status, :next_attempt_at])
    create index(:webhook_deliveries, [:webhook_id, :inserted_at])
  end
end
