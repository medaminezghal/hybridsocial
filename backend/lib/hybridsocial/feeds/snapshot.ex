defmodule Hybridsocial.Feeds.Snapshot do
  @moduledoc """
  Warm, viewer-independent snapshots of the expensive read feeds (the
  global timeline and popular hashtag timelines).

  The cost of these feeds is the query plus per-post serialization
  (link-preview cards, media, counts, tags) — seconds on a cold cache.
  None of that work depends on who is looking, so we compute it once for
  an anonymous viewer, cache the JSON-ready payload in Valkey, and reuse
  it for everyone. A logged-in viewer's interaction state (their likes,
  bookmarks, boosts, mutes, poll votes) is layered back on cheaply via
  `HybridsocialWeb.Serializers.PostSerializer.apply_viewer_state/2`.

  Snapshots are kept hot in the background by
  `Hybridsocial.Feeds.PrewarmWorker`, so a request almost never triggers
  the heavy path. A cold miss (worker disabled, cache flushed, or a
  long-tail hashtag that isn't trending) still computes and caches on
  demand, so the first visitor gets a correct — if not instant —
  response and everyone after them is warm for the TTL window.
  """

  alias Hybridsocial.{Cache, Config}

  # Interval defaults live here so the worker and the TTL math agree on
  # one source of truth. The TTL outlives the refresh interval by 3x so a
  # couple of missed cycles (worker restart, a transient error) don't
  # leave a feed cold and stall the next visitor.
  @default_interval_seconds 30
  @min_ttl_seconds 30

  @doc "Cache key for the anonymous global-timeline snapshot."
  def global_key(include_replies), do: "feed:global:ser:anon:#{include_replies}"

  @doc """
  Cache key for an anonymous hashtag-timeline snapshot. The tag is
  downcased so `#News` and `#news` share one entry — the underlying
  query matches case-insensitively anyway.
  """
  def hashtag_key(tag), do: "feed:tag:ser:anon:#{String.downcase(tag)}"

  @doc """
  Return the warm snapshot for `key`, computing and caching it via
  `compute_fun` on a cold miss. `compute_fun` must return the anonymously
  serialized (`current_identity_id: nil`) list of posts.
  """
  def fetch(key, compute_fun) do
    case safe_get(key) do
      nil -> compute_and_store(key, compute_fun)
      cached -> cached
    end
  end

  @doc "Force a recompute and cache. Used by the prewarm worker."
  def refresh(key, compute_fun), do: compute_and_store(key, compute_fun)

  defp compute_and_store(key, compute_fun) do
    serialized = compute_fun.()
    safe_set(key, serialized)
    # Round-trip through JSON so callers always receive the string-keyed
    # shape a cache hit would yield. Keeps `apply_viewer_state/2` a single
    # code path instead of branching on atom-vs-string keys.
    normalize(serialized)
  end

  defp normalize(data), do: Jason.decode!(Jason.encode!(data))

  @doc "Whether the background prewarm worker should run. Runtime-configurable."
  def enabled?, do: Config.get("global_feed_prewarm_enabled", true)

  @doc "Refresh interval in seconds. Runtime-configurable."
  def interval_seconds do
    case Config.get("global_feed_prewarm_interval_seconds", @default_interval_seconds) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_interval_seconds
    end
  end

  @doc "How many of the top trending hashtags to keep warm each cycle."
  def trending_tag_count do
    case Config.get("global_feed_prewarm_trending_tags", 12) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 12
    end
  end

  defp ttl_seconds, do: max(@min_ttl_seconds, interval_seconds() * 3)

  defp safe_get(key) do
    Cache.get(key)
  rescue
    _ -> nil
  end

  defp safe_set(key, value) do
    Cache.set(key, value, ttl_seconds())
  rescue
    _ -> :ok
  end
end
