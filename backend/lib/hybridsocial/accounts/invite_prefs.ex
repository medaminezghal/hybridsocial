defmodule Hybridsocial.Accounts.InvitePrefs do
  @moduledoc """
  Enforces the per-identity "who can invite me into groups / pages"
  preference at the point of invite creation. Same gate powers the
  Groups.invite_to_group and Pages.invite_to_page paths so the policy
  is consistent — users don't need to know which scope they're
  refusing invites from.

  Returns `:ok` when the invite is allowed, `{:error, :invites_disabled}`
  when the recipient has set the pref to "nobody", or
  `{:error, :invites_restricted}` when the pref is "only_follows" and
  the inviter isn't followed by the recipient. Callers should surface
  those as distinct 403 responses so the inviter (if they're the
  recipient themselves in an API workflow) sees what's happening.

  Identities that the invited user hasn't set a pref on yet default
  to "anyone" via the DB default, so existing accounts see no
  behaviour change after the migration lands.
  """

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Follow

  import Ecto.Query

  @type scope :: :group | :page

  @spec check(String.t(), String.t(), scope()) ::
          :ok | {:error, :invites_disabled} | {:error, :invites_restricted} | {:error, :not_found}
  def check(invited_id, inviter_id, scope)
      when is_binary(invited_id) and is_binary(inviter_id) and scope in [:group, :page] do
    case Repo.get(Identity, invited_id) do
      nil ->
        {:error, :not_found}

      %Identity{} = invited ->
        policy = policy_for(invited, scope)
        evaluate(policy, invited_id, inviter_id)
    end
  end

  defp policy_for(%Identity{allow_group_invites: v}, :group), do: v || "anyone"
  defp policy_for(%Identity{allow_page_invites: v}, :page), do: v || "anyone"

  defp evaluate("anyone", _invited_id, _inviter_id), do: :ok
  defp evaluate("nobody", _invited_id, _inviter_id), do: {:error, :invites_disabled}

  defp evaluate("only_follows", invited_id, inviter_id) do
    # "Users I follow can invite me." That is, the INVITED identity
    # follows the INVITER. Self-invites (inviting yourself to
    # something you already manage) aren't blocked — Groups/Pages
    # already reject those at the membership layer.
    followed? =
      Follow
      |> where([f], f.follower_id == ^invited_id and f.followee_id == ^inviter_id)
      |> where([f], f.status == :accepted)
      |> Repo.exists?()

    if followed?, do: :ok, else: {:error, :invites_restricted}
  end

  defp evaluate(_unknown, _invited_id, _inviter_id) do
    # Future pref values we don't understand shouldn't silently
    # block — fall open to "anyone" so a bad value doesn't lock
    # anyone out of invites.
    :ok
  end
end
