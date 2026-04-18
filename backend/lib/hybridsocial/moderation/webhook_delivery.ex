defmodule Hybridsocial.Moderation.WebhookDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webhook_deliveries" do
    field :event, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :last_error, :string
    field :last_status_code, :integer
    field :delivered_at, :utc_datetime_usec

    belongs_to :webhook, Hybridsocial.Moderation.Webhook

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :webhook_id,
      :event,
      :payload,
      :status,
      :attempts,
      :next_attempt_at,
      :last_error,
      :last_status_code,
      :delivered_at
    ])
    |> validate_required([:webhook_id, :event, :payload, :next_attempt_at])
    |> validate_inclusion(:status, ~w(pending delivered failed))
  end
end
