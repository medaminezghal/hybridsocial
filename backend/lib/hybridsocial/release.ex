defmodule Hybridsocial.Release do
  @moduledoc """
  Tasks that can be run via `bin/hybridsocial eval`.
  """

  @app :hybridsocial

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Re-fetch remote actors to backfill the `emojis` and `profile_url` columns
  added after those actors were first federated (so already-known remote
  users stop showing raw `:shortcode:` and gain a "view on original" link).

  Run on the LIVE node so the Repo + HTTP client are already started:

      bin/hybridsocial rpc "Hybridsocial.Release.backfill_remote_emojis()"
      bin/hybridsocial rpc "Hybridsocial.Release.backfill_remote_emojis(all: true)"

  Default touches only rows plausibly predating the columns (no
  profile_url); `all: true` refreshes every remote identity. Sequential
  with a small delay so we don't hammer peers. Returns `{:ok, refreshed, total}`.
  """
  def backfill_remote_emojis(opts \\ []) do
    import Ecto.Query
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Federation.Inbox
    alias Hybridsocial.Repo

    all? = Keyword.get(opts, :all, false)
    base = from(i in Identity, where: i.is_local == false)
    query = if all?, do: base, else: from(i in base, where: is_nil(i.profile_url))

    ids = Repo.all(from(i in query, select: i.id))
    total = length(ids)
    IO.puts("[backfill] #{total} remote #{if all?, do: "(all)", else: "(missing)"} identities")

    # Concurrent with a hard per-identity budget: most of these 5000+ peers
    # are dead/slow, and a single unresponsive host would otherwise block a
    # sequential run for its full connect timeout. async_stream kills any
    # task past `timeout` (on_timeout: :kill_task) and isolates crashes, so
    # one bad actor can't stall or abort the batch.
    refreshed =
      ids
      |> Task.async_stream(
        fn id ->
          # Self-contained crash safety: a raise here (malformed actor,
          # TLS error) becomes a caught :error instead of an unhandled task
          # exit that async_stream would surface and abort the batch on.
          try do
            case Repo.get(Identity, id) do
              nil -> :error
              identity -> Inbox.reenrich_remote_identity(identity)
            end
          rescue
            _ -> :error
          catch
            _, _ -> :error
          end
        end,
        # Keep under the prod DB pool (POOL_SIZE, default 10) so concurrent
        # Repo.get/update don't starve the pool.
        max_concurrency: 8,
        timeout: 15_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce(0, fn
        {:ok, {:ok, _}}, acc -> acc + 1
        _other, acc -> acc
      end)

    IO.puts("[backfill] done: #{refreshed}/#{total} refreshed")
    {:ok, refreshed, total}
  end

  @doc """
  Backfill `post_hashtags` for remote posts ingested before federation
  extracted hashtags. New remote posts link tags at ingest time; this
  re-scans EXISTING remote posts so they gain the bottom-of-post hashtag
  chips and become eligible for trending without waiting to be re-ingested.

  Extraction is from the stored post body only (the original AP `tag`
  array isn't persisted), which covers the common case where remote
  instances render `#tags` inline — the same source local posts use.
  Idempotent: only touches remote posts with no `post_hashtags` rows yet.

  Run on the LIVE node:

      bin/hybridsocial rpc "Hybridsocial.Release.backfill_remote_post_hashtags()"
      bin/hybridsocial rpc "Hybridsocial.Release.backfill_remote_post_hashtags(limit: 1000)"

  Returns `{:ok, tagged_posts, scanned}`.
  """
  def backfill_remote_post_hashtags(opts \\ []) do
    import Ecto.Query
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Repo
    alias Hybridsocial.Social.{Post, Posts}

    limit = Keyword.get(opts, :limit)

    base =
      from p in Post,
        join: i in Identity,
        on: i.id == p.identity_id,
        where:
          i.is_local == false and not is_nil(p.content) and p.content != "" and
            is_nil(p.deleted_at),
        where: fragment("NOT EXISTS (SELECT 1 FROM post_hashtags ph WHERE ph.post_id = ?)", p.id),
        select: %{id: p.id, content: p.content}

    query = if is_integer(limit), do: from(q in base, limit: ^limit), else: base

    posts = Repo.all(query)
    total = length(posts)
    IO.puts("[backfill] scanning #{total} remote posts for hashtags")

    tagged =
      Enum.reduce(posts, 0, fn %{id: id, content: content}, acc ->
        case Posts.extract_hashtags(content) do
          [] ->
            acc

          tags ->
            Posts.link_hashtags(%Post{id: id}, tags)
            acc + 1
        end
      end)

    IO.puts("[backfill] done: linked hashtags on #{tagged}/#{total} remote posts")
    {:ok, tagged, total}
  end

  @doc """
  READ-ONLY audit: find LOCAL image uploads whose backing file is
  missing from storage — the `media` row still points at a
  `storage_path`, but the object no longer exists in the active
  backend (R2/S3/local). Those are the posts that render a broken
  image.

  Deletes nothing. Prints a per-post report and returns:

      %{broken_posts: [%{post_id, identity_id, inserted_at, media: [...]}],
        uncertain:    [%{media_id, storage_path, reason}],
        scanned:      n}

  `uncertain` rows are ones where the storage HEAD check errored
  (network/permission blip) — they are NEVER counted as broken and
  never deleted.

  Run on the LIVE node so Repo + Config + the storage backend are
  already started:

      bin/hybridsocial rpc "Hybridsocial.Release.report_broken_media()"
      bin/hybridsocial rpc "Hybridsocial.Release.report_broken_media(limit: 500)"
  """
  def report_broken_media(opts \\ []) do
    result = scan_broken_media(opts)
    print_broken_media_report(result)
    result
  end

  @doc """
  DESTRUCTIVE. Re-runs the broken-media scan and soft-deletes every
  post that has at least one confirmed-missing image, using the full
  deletion path (federation Delete, PubSub broadcast, reply-count
  fixup, moderation webhook) via `Social.Posts.delete_post/2`.

  Posts whose media only came back "uncertain" (storage HEAD errored)
  are left untouched. Requires `confirm: true` as a fat-finger guard:

      bin/hybridsocial rpc "Hybridsocial.Release.delete_broken_media_posts(confirm: true)"

  Returns `%{deleted: n, failed: [...]}`.
  """
  def delete_broken_media_posts(opts \\ []) do
    if Keyword.get(opts, :confirm) == true do
      alias Hybridsocial.Social.Posts

      %{broken_posts: broken_posts} = result = scan_broken_media(opts)
      print_broken_media_report(result)

      IO.puts("[broken-media] deleting #{length(broken_posts)} post(s) with missing images...")

      {deleted, failed} =
        Enum.reduce(broken_posts, {0, []}, fn post, {ok, bad} ->
          # Pass the post's own identity_id so the ownership check in
          # delete_post/2 passes — all candidates are local uploads and
          # thus locally-authored, so this reuses the correct deletion
          # side effects without an unauthenticated delete path.
          case Posts.delete_post(post.post_id, post.identity_id) do
            {:ok, _} ->
              IO.puts("    deleted post #{post.post_id}")
              {ok + 1, bad}

            error ->
              IO.puts("    FAILED post #{post.post_id}: #{inspect(error)}")
              {ok, [%{post_id: post.post_id, error: error} | bad]}
          end
        end)

      IO.puts("[broken-media] done: #{deleted} deleted, #{length(failed)} failed")
      %{deleted: deleted, failed: failed}
    else
      IO.puts(
        "Refusing to delete without `confirm: true`. Run report_broken_media/0 first, then re-run with confirm: true."
      )

      {:error, :not_confirmed}
    end
  end

  defp scan_broken_media(opts) do
    import Ecto.Query
    alias Hybridsocial.Media.{MediaFile, Storage}
    alias Hybridsocial.Repo
    alias Hybridsocial.Social.Post

    limit = Keyword.get(opts, :limit)

    base =
      from m in MediaFile,
        join: p in Post,
        on: p.id == m.post_id,
        where:
          is_nil(m.deleted_at) and is_nil(p.deleted_at) and
            not is_nil(m.storage_path) and m.storage_path != "" and
            ilike(m.content_type, "image/%"),
        order_by: [asc: p.inserted_at],
        select: %{
          media_id: m.id,
          storage_path: m.storage_path,
          content_type: m.content_type,
          post_id: m.post_id,
          identity_id: p.identity_id,
          inserted_at: p.inserted_at
        }

    query = if is_integer(limit), do: from(q in base, limit: ^limit), else: base
    rows = Repo.all(query)
    scanned = length(rows)
    IO.puts("[broken-media] checking #{scanned} local image attachment(s) against storage...")

    {broken_rows, uncertain} =
      rows
      |> Task.async_stream(
        fn row -> {row, Storage.exists?(row.storage_path)} end,
        max_concurrency: 8,
        timeout: 30_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {_row, {:ok, true}}}, acc ->
          acc

        {:ok, {row, {:ok, false}}}, {broken, uncertain} ->
          {[row | broken], uncertain}

        {:ok, {row, {:error, reason}}}, {broken, uncertain} ->
          {broken, [Map.put(row, :reason, reason) | uncertain]}

        # Timeout/crash during the HEAD check — treat as uncertain, never broken.
        {:exit, reason}, {broken, uncertain} ->
          {broken,
           [%{media_id: nil, storage_path: nil, reason: {:task_exit, reason}} | uncertain]}
      end)

    broken_posts =
      broken_rows
      |> Enum.group_by(& &1.post_id)
      |> Enum.map(fn {post_id, media_rows} ->
        first = hd(media_rows)

        %{
          post_id: post_id,
          identity_id: first.identity_id,
          inserted_at: first.inserted_at,
          media:
            Enum.map(
              media_rows,
              &%{id: &1.media_id, path: &1.storage_path, content_type: &1.content_type}
            )
        }
      end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    %{broken_posts: broken_posts, uncertain: uncertain, scanned: scanned}
  end

  defp print_broken_media_report(%{
         broken_posts: broken_posts,
         uncertain: uncertain,
         scanned: scanned
       }) do
    IO.puts("")
    IO.puts("=== Broken media audit ===")
    IO.puts("Scanned local image attachments : #{scanned}")
    IO.puts("Posts with missing image files  : #{length(broken_posts)}")
    IO.puts("Uncertain (storage unreachable) : #{length(uncertain)}")
    IO.puts("")

    Enum.each(broken_posts, fn post ->
      IO.puts("post #{post.post_id}  (identity #{post.identity_id}, #{post.inserted_at})")

      Enum.each(post.media, fn m ->
        IO.puts("    missing: #{m.path}  [#{m.content_type}]")
      end)
    end)

    if uncertain != [] do
      IO.puts("")
      IO.puts("Uncertain rows (NOT deleted — storage HEAD errored):")

      Enum.each(uncertain, fn u ->
        IO.puts("    #{u[:storage_path] || "?"}  (#{inspect(u[:reason])})")
      end)
    end

    IO.puts("")
    :ok
  end

  def setup do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _ -> :ok end)
    end

    migrate()
    seed()
  end

  # sobelow_skip ["RCE.CodeModule"]
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_file = Path.join([:code.priv_dir(@app), "repo", "seeds.exs"])

          if File.exists?(seed_file) do
            Code.eval_file(seed_file)
          end
        end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
