defmodule Hybridsocial.Media.InfectedTracker do
  @moduledoc """
  Records infected-upload attempts and escalates repeat offenders.

  Each call writes an audit-log row, bumps a per-identity counter in
  Valkey, and — once the identity crosses the configured threshold
  within the window — drops an item onto the moderation queue so a
  human can decide whether to suspend. We deliberately don't
  auto-suspend: a single antivirus false positive shouldn't lock
  anyone out.

  Window defaults to 1 hour; threshold defaults to 5 infected uploads
  within that window. Both are admin-configurable so operators with
  noisier scanners or stricter policies can tune without a deploy.
  """

  alias Hybridsocial.{Cache, Config, Moderation}
  require Logger

  @default_window_seconds 3_600
  @default_threshold 5

  @doc """
  Record one infected-upload attempt. Returns `:ok` in all success
  paths — this is fire-and-forget from the caller's perspective; the
  upload has already been rejected before we get here.

  Args:
    * `identity_id` — uploader's identity id, or `nil` for proxy hits
      (remote media) where we don't have one
    * `signature` — ClamAV signature string (e.g. `"Win.Test.EICAR_HDB-1"`)
    * `content_type` — sniffed content type of the rejected bytes
    * `file_size` — bytes
  """
  def record(identity_id, signature, content_type, file_size) do
    Moderation.log(
      identity_id,
      "media.infected_upload_rejected",
      "identity",
      identity_id,
      %{
        signature: signature,
        content_type: content_type,
        file_size: file_size
      }
    )

    if is_binary(identity_id) do
      bump_and_maybe_escalate(identity_id, signature, content_type)
    end

    :ok
  end

  defp bump_and_maybe_escalate(identity_id, signature, content_type) do
    window = Config.get("infected_upload_window_seconds", @default_window_seconds)
    threshold = Config.get("infected_upload_threshold", @default_threshold)
    counter_key = "infected_attempts:#{identity_id}"

    count =
      case Cache.get(counter_key) do
        nil ->
          Cache.set(counter_key, "1", window)
          1

        v when is_binary(v) ->
          next = (String.to_integer(v) || 0) + 1
          Cache.set(counter_key, Integer.to_string(next), window)
          next

        _ ->
          1
      end

    if count >= threshold do
      enqueue_review(identity_id, count, signature, content_type)
    end
  end

  defp enqueue_review(identity_id, count, signature, content_type) do
    case Moderation.queue_for_review(%{
           item_type: "identity",
           item_id: identity_id,
           source: "antivirus",
           severity: "high",
           reason:
             "Uploaded #{count} infected files within the configured window (latest: #{signature}, #{content_type}). Review for account action."
         }) do
      {:ok, _} ->
        :ok

      other ->
        Logger.warning("InfectedTracker: failed to queue review: #{inspect(other)}")
        :ok
    end
  end
end
