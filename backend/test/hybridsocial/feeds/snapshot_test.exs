defmodule Hybridsocial.Feeds.SnapshotTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Feeds.Snapshot

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

  describe "keys" do
    test "global key varies by include_replies" do
      assert Snapshot.global_key(false) == "feed:global:ser:anon:false"
      assert Snapshot.global_key(true) == "feed:global:ser:anon:true"
    end

    test "hashtag key downcases the tag so casing variants share one entry" do
      assert Snapshot.hashtag_key("News") == Snapshot.hashtag_key("news")
      assert Snapshot.hashtag_key("News") == "feed:tag:ser:anon:news"
    end
  end

  describe "fetch/2" do
    test "computes once, then serves the cached (string-keyed) value" do
      key = "feed:global:ser:anon:test"
      calls = :counters.new(1, [])

      compute = fn ->
        :counters.add(calls, 1, 1)
        [%{id: "a", content: "hello"}]
      end

      first = Snapshot.fetch(key, compute)
      # Round-tripped to the string-keyed cache shape even on the cold miss.
      assert first == [%{"id" => "a", "content" => "hello"}]

      second = Snapshot.fetch(key, compute)
      assert second == first
      # compute ran only for the cold miss, not the warm hit.
      assert :counters.get(calls, 1) == 1
    end

    test "refresh/2 recomputes and overwrites the cached value" do
      key = "feed:global:ser:anon:test2"

      Snapshot.refresh(key, fn -> [%{id: "old"}] end)
      assert Snapshot.fetch(key, fn -> flunk("should be warm") end) == [%{"id" => "old"}]

      Snapshot.refresh(key, fn -> [%{id: "new"}] end)
      assert Snapshot.fetch(key, fn -> flunk("should be warm") end) == [%{"id" => "new"}]
    end
  end
end
