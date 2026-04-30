defmodule HybridsocialWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that gates admin endpoints on two things:

    1. The caller is staff (has at least one active role). Being
       the first account with `is_admin = true` is not enough on
       its own — a role row in `identity_roles` is what actually
       grants access.
    2. The caller has 2FA enabled on their account. Admin sessions
       are high-value and every staff account is required to harden
       with TOTP before the panel will serve them data.

  Per-action permission checks are handled elsewhere by
  RequirePermission or inline checks.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Accounts
  alias Hybridsocial.Auth.RBAC
  alias Hybridsocial.Auth.Webauthn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_identity] do
      %{id: identity_id} ->
        cond do
          not RBAC.staff?(identity_id) ->
            deny(conn, "auth.forbidden", "Admin access required")

          not second_factor_enabled?(identity_id) ->
            deny(
              conn,
              "admin.otp_required",
              "Two-factor authentication must be enabled to use the admin panel. " <>
                "Either an authenticator app (TOTP) or a security key (WebAuthn) satisfies this."
            )

          true ->
            conn
        end

      _ ->
        deny(conn, "auth.forbidden", "Admin access required")
    end
  end

  # A staff account satisfies the 2FA requirement with either an
  # authenticator app (TOTP) or at least one registered security key
  # (WebAuthn). Both are phishing-resistant enough for the admin gate.
  defp second_factor_enabled?(identity_id) do
    otp_enabled?(identity_id) or Webauthn.has_credentials?(identity_id)
  end

  defp otp_enabled?(identity_id) do
    case Accounts.get_user_by_identity(identity_id) do
      %{otp_enabled: true} -> true
      _ -> false
    end
  end

  defp deny(conn, error, message) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: error, message: message})
    |> halt()
  end
end
