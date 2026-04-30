defmodule HybridsocialWeb.Api.V1.Admin.SudoController do
  @moduledoc """
  Step-up auth (sudo) endpoints for the admin panel. Opens and closes
  a short-lived elevation window on the caller's access token —
  `RequireSudo` gates every other admin route behind it.

  These routes themselves do NOT pipe through `RequireSudo` (that would
  be a chicken-and-egg), only through `:admin` (auth + staff + 2FA).
  """
  use HybridsocialWeb, :controller

  alias Hybridsocial.{Accounts, Auth, Moderation}
  alias Hybridsocial.Auth.Webauthn

  @doc """
  POST /api/v1/admin/sudo
  Body: `{password, code}` (TOTP) or `{password, webauthn: assertion}`
  (security key). Re-verifies the caller's password plus *one* second
  factor — either is accepted, matching the RequireAdmin gate. On
  success, stamps `sudo_until = now + TTL` on the current token.

  GET /api/v1/admin/sudo/webauthn_challenge issues the assertion
  challenge the security-key flow uses.
  """
  def grant(conn, params) do
    identity = conn.assigns.current_identity
    token = conn.assigns.current_token

    password = params["password"]
    code = params["code"] || params["otp_code"]
    webauthn = params["webauthn"]

    cond do
      not is_binary(password) or password == "" ->
        bad_request(conn, "sudo.password_required")

      missing_second_factor?(code, webauthn) ->
        bad_request(conn, "sudo.otp_required")

      true ->
        with {:ok, _user} <- verify_password(identity, password),
             {:ok, _user} <- verify_second_factor(identity.id, code, webauthn),
             {:ok, until} <- Auth.grant_sudo(token) do
          Moderation.log(
            identity.id,
            "admin.sudo_granted",
            "identity",
            identity.id,
            %{ttl_seconds: Auth.sudo_ttl_seconds()},
            client_ip(conn)
          )

          conn
          |> put_status(:ok)
          |> json(%{
            status: "ok",
            expires_at: until,
            expires_in: Auth.sudo_ttl_seconds()
          })
        else
          {:error, :invalid_credentials} ->
            log_failure(identity, "invalid_password", conn)
            unauthorized(conn, "sudo.invalid_password")

          {:error, :invalid_code} ->
            log_failure(identity, "invalid_code", conn)
            unauthorized(conn, "sudo.invalid_code")

          {:error, :not_found} ->
            unauthorized(conn, "sudo.invalid_password")

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "sudo.failed"})
        end
    end
  end

  @doc """
  GET /api/v1/admin/sudo
  Reports whether the current token has an active sudo window, so the
  frontend can decide whether to show the challenge before rendering
  the admin UI. Does NOT extend the window — only `RequireSudo` does.
  """
  def status(conn, _params) do
    token = conn.assigns.current_token
    until = Auth.sudo_expires_at(token)
    now = DateTime.utc_now()

    active? =
      case until do
        nil -> false
        t -> DateTime.compare(t, now) == :gt
      end

    conn
    |> put_status(:ok)
    |> json(%{
      sudo: active?,
      expires_at: if(active?, do: until, else: nil)
    })
  end

  @doc """
  DELETE /api/v1/admin/sudo
  Clears the sudo flag on the current token (explicit lock, e.g. when
  leaving a shared machine).
  """
  def revoke(conn, _params) do
    identity = conn.assigns.current_identity
    token = conn.assigns.current_token
    :ok = Auth.revoke_sudo(token)

    Moderation.log(
      identity.id,
      "admin.sudo_revoked",
      "identity",
      identity.id,
      %{},
      client_ip(conn)
    )

    conn |> put_status(:ok) |> json(%{status: "ok"})
  end

  @doc """
  GET /api/v1/admin/sudo/webauthn_challenge

  Issues an assertion challenge so a user with a registered security
  key can clear the sudo step-up without entering a TOTP code. The
  signed assertion comes back via the `webauthn` field on POST
  /api/v1/admin/sudo.
  """
  def webauthn_challenge(conn, _params) do
    identity = conn.assigns.current_identity
    challenge = Webauthn.authentication_challenge(identity.id)
    json(conn, challenge)
  end

  defp missing_second_factor?(code, webauthn) do
    cond do
      is_binary(code) and code != "" -> false
      is_map(webauthn) -> false
      true -> true
    end
  end

  defp verify_second_factor(identity_id, code, webauthn) do
    cond do
      is_map(webauthn) ->
        case Webauthn.verify_authentication(identity_id, webauthn) do
          {:ok, _cred} -> {:ok, :webauthn}
          {:error, :challenge_expired} -> {:error, :invalid_code}
          {:error, :credential_not_found} -> {:error, :invalid_code}
          {:error, _} -> {:error, :invalid_code}
        end

      is_binary(code) and code != "" ->
        Accounts.verify_2fa(identity_id, code)

      true ->
        {:error, :invalid_code}
    end
  end

  defp verify_password(identity, password) do
    case Accounts.get_user_by_identity(identity.id) do
      nil ->
        {:error, :not_found}

      user ->
        Accounts.authenticate_user(user.email, password)
    end
  end

  defp log_failure(identity, reason, conn) do
    Moderation.log(
      identity.id,
      "admin.sudo_failed",
      "identity",
      identity.id,
      %{reason: reason},
      client_ip(conn)
    )
  end

  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp bad_request(conn, error) do
    conn |> put_status(:bad_request) |> json(%{error: error})
  end

  defp unauthorized(conn, error) do
    conn |> put_status(:unauthorized) |> json(%{error: error})
  end
end
