defmodule Hybridsocial.Migration.PleromaImport do
  @moduledoc """
  Maps a local user row from a retired Pleroma/Rebased instance onto a
  HybridSocial `Identity`, preserving its ActivityPub identity so remote
  servers keep accepting it after the platform swap.

  The source is a decoded `users`-row map (string keys, as produced by
  `SELECT row_to_json(...)`), which keeps this decoupled from *how* the
  data is read — a JSONL export today, a direct DB read at cutover.

  Two things the source does NOT give us and we reconstruct:

    * Pleroma stores only the RSA **private** key (`keys`) for local
      users; the public key is derived from it here (same encoding our
      native key generation uses).
    * `inbox`/`shared_inbox` are often null because Pleroma computes them
      from the actor URL; we do the same.
  """

  import Ecto.Query
  require Logger

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Follow

  @doc """
  Import one Pleroma local-user map. Idempotent: an actor already present
  (matched on `ap_actor_url`) is returned untouched so a run can be
  resumed safely.
  """
  def import_user(%{} = u) do
    with {:ok, attrs} <- to_identity_attrs(u) do
      case Repo.get_by(Identity, ap_actor_url: attrs["ap_actor_url"]) do
        nil ->
          attrs
          |> Identity.import_changeset()
          |> Repo.insert()

        %Identity{} = existing ->
          {:ok, existing}
      end
    end
  end

  @doc "Import a list of Pleroma user maps, returning a summary of outcomes."
  def import_users(users) when is_list(users) do
    Enum.reduce(users, %{ok: 0, skipped: 0, failed: []}, fn u, acc ->
      case import_user(u) do
        {:ok, _} ->
          %{acc | ok: acc.ok + 1}

        {:error, reason} ->
          %{acc | failed: [{u["nickname"], summarize_error(reason)} | acc.failed]}
      end
    end)
  end

  @doc """
  Insert a remote (federated) actor referenced by a local user's follow
  graph, so the follow rows have both endpoints. Reuses the source UUID as
  the identity id (like local imports) so follows map by id. No key
  generation, no network fetch — the data comes straight from the source
  DB. Idempotent on ap_actor_url.
  """
  def import_remote_actor(%{"ap_id" => ap} = m) when is_binary(ap) do
    case Repo.get_by(Identity, ap_actor_url: ap) do
      nil ->
        %Identity{}
        |> Ecto.Changeset.cast(
          %{
            id: m["id"],
            type: map_actor_type(m["actor_type"]),
            handle: remote_handle(m["nickname"], ap),
            display_name: truncate(m["name"] || m["nickname"], 50),
            ap_actor_url: ap,
            is_local: false,
            public_key: m["public_key"],
            inbox_url: presence(m["inbox"]) || ap <> "/inbox",
            outbox_url: ap <> "/outbox",
            followers_url: m["follower_address"],
            avatar_url: extract_media_url(m["avatar"])
          },
          [
            :id,
            :type,
            :handle,
            :display_name,
            :ap_actor_url,
            :is_local,
            :public_key,
            :inbox_url,
            :outbox_url,
            :followers_url,
            :avatar_url
          ]
        )
        |> Ecto.Changeset.validate_required([:type, :handle, :ap_actor_url])
        |> Ecto.Changeset.unique_constraint(:handle)
        |> Ecto.Changeset.unique_constraint(:ap_actor_url)
        |> Repo.insert()

      %Identity{} = existing ->
        {:ok, existing}
    end
  rescue
    # DB-level failures (e.g. a stray over-long field) shouldn't abort the
    # whole batch — record and move on.
    e in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, Exception.message(e)}
  end

  def import_remote_actor(_), do: {:error, :missing_ap_id}

  def import_remote_actors(list) when is_list(list) do
    Enum.reduce(list, %{ok: 0, failed: 0}, fn m, acc ->
      case import_remote_actor(m) do
        {:ok, _} -> %{acc | ok: acc.ok + 1}
        _ -> %{acc | failed: acc.failed + 1}
      end
    end)
  end

  @doc """
  Import follow rows (`%{"follower_id","following_id","state"}` maps, using
  the source UUIDs which we preserved as identity ids). Both endpoints must
  already exist as identities (local imports + `import_remote_actors`);
  rows referencing a dropped/never-imported endpoint are skipped. Pleroma
  state 2 → accepted, 1 → pending, 3 (rejected) → skipped. Idempotent.
  """
  def import_follows(follows) when is_list(follows) do
    id_set = from(i in Identity, select: i.id) |> Repo.all() |> MapSet.new()

    Enum.reduce(follows, %{ok: 0, skipped: 0}, fn f, acc ->
      fid = f["follower_id"]
      gid = f["following_id"]

      status =
        case f["state"] do
          2 -> :accepted
          1 -> :pending
          _ -> nil
        end

      cond do
        is_nil(status) or fid == gid ->
          %{acc | skipped: acc.skipped + 1}

        not (MapSet.member?(id_set, fid) and MapSet.member?(id_set, gid)) ->
          %{acc | skipped: acc.skipped + 1}

        true ->
          %Follow{}
          |> Follow.changeset(%{follower_id: fid, followee_id: gid, status: status})
          |> Repo.insert(
            on_conflict: {:replace, [:status, :updated_at]},
            conflict_target: [:follower_id, :followee_id]
          )
          |> case do
            {:ok, _} -> %{acc | ok: acc.ok + 1}
            {:error, _} -> %{acc | skipped: acc.skipped + 1}
          end
      end
    end)
  end

  # --- mapping ---------------------------------------------------------

  defp to_identity_attrs(%{"ap_id" => ap_id} = u) when is_binary(ap_id) do
    case derive_public_key(u["keys"]) do
      {:ok, public_pem} ->
        origin = origin_of(ap_id)

        {:ok,
         %{
           "id" => u["id"],
           "type" => map_actor_type(u["actor_type"]),
           "handle" => u["nickname"],
           "display_name" => truncate(u["name"] || u["nickname"], 50),
           "bio" => truncate(u["raw_bio"] || strip_html(u["bio"]), 500),
           "ap_actor_url" => ap_id,
           "public_key" => public_pem,
           "private_key" => u["keys"],
           "inbox_url" => presence(u["inbox"]) || ap_id <> "/inbox",
           "outbox_url" => ap_id <> "/outbox",
           "followers_url" => u["follower_address"],
           "following_url" => u["following_address"],
           "featured_url" => u["featured_address"],
           "shared_inbox_url" => presence(u["shared_inbox"]) || origin <> "/inbox",
           "avatar_url" => extract_media_url(u["avatar"]),
           "header_url" => extract_media_url(u["banner"]),
           "is_locked" => u["is_locked"] || false,
           "discoverable" => u["is_discoverable"] || false,
           "also_known_as" => u["also_known_as"] || [],
           "birthday" => u["birthday"],
           "location" => u["location"],
           "metadata" => %{}
         }}

      {:error, reason} ->
        {:error, {:key_derivation, reason}}
    end
  end

  defp to_identity_attrs(_), do: {:error, :missing_ap_id}

  # Pleroma actor types → our internal types.
  defp map_actor_type("Service"), do: "bot"
  defp map_actor_type("Application"), do: "bot"
  defp map_actor_type("Group"), do: "group"
  defp map_actor_type("Organization"), do: "organization"
  defp map_actor_type(_), do: "user"

  @doc """
  Derive the SubjectPublicKeyInfo PEM from an RSA private-key PEM, matching
  the encoding our native key generation produces.
  """
  def derive_public_key(private_pem) when is_binary(private_pem) do
    case :public_key.pem_decode(private_pem) do
      [entry | _] ->
        priv = :public_key.pem_entry_decode(entry)
        # RSAPrivateKey: {:RSAPrivateKey, version, modulus, publicExponent, ...}
        rsa_public = {:RSAPublicKey, elem(priv, 2), elem(priv, 3)}
        pub_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
        {:ok, :public_key.pem_encode([pub_entry])}

      [] ->
        {:error, :empty_pem}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def derive_public_key(_), do: {:error, :no_private_key}

  # --- helpers ---------------------------------------------------------

  defp origin_of(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  # Remote handles must be globally unique in HybridSocial (unlike Pleroma,
  # where they're scoped by domain). Suffix the source nickname with a short
  # hash of the actor URL so two remotes named "bob" don't collide.
  defp remote_handle(nickname, ap_id) do
    base =
      (nickname || "user")
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.slice(0, 24)

    hash = :crypto.hash(:sha256, ap_id) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    "#{base}_#{hash}"
  end

  defp extract_media_url(%{"url" => [%{"href" => href} | _]}) when is_binary(href), do: href
  defp extract_media_url(%{"url" => href}) when is_binary(href), do: href
  defp extract_media_url(_), do: nil

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: s
  defp presence(_), do: nil

  defp strip_html(nil), do: ""
  defp strip_html(s) when is_binary(s), do: String.replace(s, ~r/<[^>]*>/, "")

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when is_binary(s), do: String.slice(s, 0, max)

  defp summarize_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, "; ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp summarize_error(other), do: inspect(other)

  @doc "How many local actors have already been imported."
  def imported_count do
    from(i in Identity, where: i.is_local == true and not is_nil(i.private_key))
    |> Repo.aggregate(:count)
  end
end
