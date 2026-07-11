defmodule Hybridsocial.Federation.RemoteMediaBackfill do
  @moduledoc """
  One-shot repair for remote media ingested before the content-type
  inference + inline-image stripping fixes landed:

    * attachments stored as `application/octet-stream` (→ "unknown" type,
      broken tiles) are re-typed from their `remote_url` extension;
    * remote posts whose `content_html` still carries inline `<img>`
      (duplicated with attachments, loaded off-proxy) are stripped.

  Idempotent — safe to run more than once. Invoke after deploy:

      bin/hybridsocial eval "Hybridsocial.Federation.RemoteMediaBackfill.run()"
  """
  import Ecto.Query
  require Logger

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Federation.ActivityMapper
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post

  @doc "Run both backfills. Returns a summary map of rows changed."
  def run do
    retyped = retype_attachments()
    stripped = strip_inline_images()
    Logger.info("[remote_media_backfill] retyped=#{retyped} stripped=#{stripped}")
    %{retyped: retyped, stripped: stripped}
  end

  @doc """
  Re-type remote attachments stuck at `application/octet-stream` using the
  file extension of their `remote_url`. Only rows whose type actually
  resolves to something better are touched.
  """
  def retype_attachments do
    MediaFile
    |> where([m], not is_nil(m.remote_url))
    |> where([m], is_nil(m.content_type) or m.content_type == "application/octet-stream")
    |> Repo.all()
    |> Enum.reduce(0, fn media, acc ->
      resolved = ActivityMapper.resolve_remote_content_type(nil, media.remote_url)

      if resolved != "application/octet-stream" and resolved != media.content_type do
        media
        |> Ecto.Changeset.change(content_type: resolved)
        |> Repo.update()

        acc + 1
      else
        acc
      end
    end)
  end

  @doc """
  Strip inline `<img>` from the `content_html` of posts authored by remote
  identities. Local posts are left alone — inline images are a legitimate
  full-markdown feature there.
  """
  def strip_inline_images do
    Post
    |> join(:inner, [p], i in Identity, on: i.id == p.identity_id)
    |> where([p, i], i.is_local == false)
    |> where([p], like(p.content_html, "%<img%"))
    |> Repo.all()
    |> Enum.reduce(0, fn post, acc ->
      stripped = ActivityMapper.strip_inline_images(post.content_html)

      if is_binary(stripped) and stripped != post.content_html do
        post
        |> Ecto.Changeset.change(content_html: stripped)
        |> Repo.update()

        acc + 1
      else
        acc
      end
    end)
  end
end
