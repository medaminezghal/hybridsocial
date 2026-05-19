defmodule Hybridsocial.Repo.Migrations.CreateBotWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:bot_webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # The bot identity that owns this delivery (not the user who
      # owns the bot). When the bot's identity is hard-deleted we
      # cascade these rows away since they'd have nothing to deliver to.
      add :bot_identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      # We snapshot the webhook URL on enqueue so a later URL change
      # doesn't redirect already-queued events to the new endpoint.
      add :webhook_url, :string, null: false

      # Event name. Free-form on purpose — adding a new event type
      # shouldn't require a schema migration.
      add :event, :string, null: false

      # The JSON body we'll POST. Snapshotted at enqueue time so we
      # never re-render from sources that have moved on.
      add :payload, :map, null: false, default: %{}

      # Lifecycle. "pending" → "delivered" on a 2xx, → "failed" after
      # @max_attempts non-2xx responses.
      add :status, :string, null: false, default: "pending"

      add :attempts, :integer, null: false, default: 0
      add :last_status_code, :integer
      add :last_error, :text

      # When the worker is allowed to retry. Starts at enqueue time so
      # the first attempt happens on the next tick.
      add :next_attempt_at, :utc_datetime_usec,
        null: false,
        default: fragment("now()")

      add :delivered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Worker query is "pending rows whose next_attempt_at is in the
    # past, oldest first" — this composite makes that a single
    # index scan.
    create index(:bot_webhook_deliveries, [:status, :next_attempt_at])

    # Per-bot history view in the Developer Tools UI — most-recent first.
    create index(:bot_webhook_deliveries, [:bot_identity_id, :inserted_at])
  end
end
