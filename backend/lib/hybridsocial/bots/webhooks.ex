defmodule Hybridsocial.Bots.Webhooks do
  @moduledoc """
  Per-bot outbound webhook configuration + delivery enqueue.

  A bot owner sets a URL via `set/2`. We generate a 256-bit signing
  secret, hash it with HMAC-SHA256 (keyed by the master secret) for
  storage, and return the plaintext to the caller exactly once so they
  can paste it into their server's environment.

  On every notification destined for a bot identity, the Notifications
  context calls `maybe_enqueue_for_notification/2`. If the bot has a
  URL configured, a `BotWebhookDelivery` row is inserted and the
  `WebhookDeliveryWorker` picks it up on the next tick.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Bot, BotWebhookDelivery, Identity}
  alias Hybridsocial.Notifications.Notification

  # 32 random bytes → 256-bit secret. Bcrypt-style hashing isn't a
  # good fit (we need to *use* the secret to sign every outgoing
  # request, not just compare), so we store the HMAC of the plaintext
  # under a server master key and re-derive the same value on every
  # send. Compromise of the DB without the master key is therefore
  # useless on its own.
  @secret_bytes 32

  @doc """
  Set or update a bot's webhook URL. Returns the plaintext signing
  secret on success — the only time the caller will see it.
  """
  def set(bot_identity_id, url) when is_binary(url) and url != "" do
    case Repo.get(Bot, bot_identity_id) do
      nil ->
        {:error, :not_found}

      bot ->
        secret = random_secret()
        hash = hash_secret(secret)

        bot
        |> Bot.webhook_changeset(%{webhook_url: url, webhook_secret_hash: hash})
        |> Repo.update()
        |> case do
          {:ok, _bot} -> {:ok, secret}
          error -> error
        end
    end
  end

  @doc "Clear the webhook URL + secret for a bot."
  def clear(bot_identity_id) do
    case Repo.get(Bot, bot_identity_id) do
      nil ->
        {:error, :not_found}

      bot ->
        bot
        |> Bot.webhook_changeset(%{webhook_url: nil, webhook_secret_hash: nil})
        |> Repo.update()
    end
  end

  @doc """
  Look at a freshly inserted notification and queue a webhook
  delivery if the recipient is a bot with a URL configured. No-ops
  for the common case where the recipient is a human user — keeps
  the call site in `Notifications.create_notification` cheap.
  """
  def maybe_enqueue_for_notification(%Notification{} = notification, attrs) do
    case Repo.get(Bot, notification.recipient_id) do
      %Bot{webhook_url: url, is_active: true} when is_binary(url) and url != "" ->
        enqueue(
          notification.recipient_id,
          url,
          notification.type,
          %{
            event: notification.type,
            notification_id: notification.id,
            recipient_id: notification.recipient_id,
            actor_id: notification.actor_id,
            target_type: attrs[:target_type] || attrs["target_type"],
            target_id: attrs[:target_id] || attrs["target_id"],
            created_at: notification.inserted_at
          }
        )

      _ ->
        :ok
    end
  end

  def maybe_enqueue_for_notification(_, _), do: :ok

  @doc """
  Insert a delivery row. Public so callers other than the notification
  hook (e.g. DM arrival, post engagement webhooks added later) can
  push events into the same queue without going through
  `Notifications.create_notification`.
  """
  def enqueue(bot_identity_id, url, event, payload) do
    %BotWebhookDelivery{}
    |> BotWebhookDelivery.changeset(%{
      bot_identity_id: bot_identity_id,
      webhook_url: url,
      event: event,
      payload: payload,
      status: "pending",
      next_attempt_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })
    |> Repo.insert()
  end

  @doc """
  HMAC-SHA256 signature for the given body, using the bot's stored
  signing secret. Returned as lowercase hex so the worker can stamp
  it into the `X-Webhook-Signature` header.

  Note: this re-hashes the bot's stored hash (which already is an
  HMAC of the plaintext). Doing so means we sign with a value the
  caller has, not with the plaintext secret, which they're expected
  to verify against on their end with the same scheme:

      hmac_sha256( hmac_sha256( master_secret, plaintext_secret ), body )

  In practice the bot owner does
  `expected = hmac_sha256(received_secret_hash, body)` after deriving
  `received_secret_hash` once on startup. Documented in
  /help/developers § Webhooks.
  """
  def sign(secret_hash, body) when is_binary(secret_hash) and is_binary(body) do
    :crypto.mac(:hmac, :sha256, secret_hash, body)
    |> Base.encode16(case: :lower)
  end

  @doc "Recent delivery history for the Developer Tools UI."
  def list_recent_deliveries(bot_identity_id, limit \\ 25) do
    BotWebhookDelivery
    |> where([d], d.bot_identity_id == ^bot_identity_id)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Look up the bot identity for permission checks in the controller."
  def get_bot_identity(bot_identity_id) do
    Identity
    |> where([i], i.id == ^bot_identity_id and i.type == "bot" and is_nil(i.deleted_at))
    |> Repo.one()
  end

  # ── Private ──────────────────────────────────────────────────────

  defp random_secret do
    :crypto.strong_rand_bytes(@secret_bytes)
    |> Base.url_encode64(padding: false)
  end

  defp hash_secret(secret) do
    master = master_key()

    :crypto.mac(:hmac, :sha256, master, secret)
    |> Base.encode16(case: :lower)
  end

  defp master_key do
    Application.get_env(:hybridsocial, :master_key) ||
      Application.get_env(:hybridsocial, HybridsocialWeb.Endpoint)[:secret_key_base] ||
      "fallback-master-key-do-not-use-in-prod"
  end
end
