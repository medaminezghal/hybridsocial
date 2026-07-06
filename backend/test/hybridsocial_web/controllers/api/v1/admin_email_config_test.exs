defmodule HybridsocialWeb.Api.V1.AdminEmailConfigTest do
  # async: false — these tests mutate process environment variables
  # (RESEND_API_KEY / SMTP_HOST), which are global, so they must not run
  # concurrently with other tests.
  use HybridsocialWeb.ConnCase, async: false

  # create_user/make_admin/admin_conn come from Hybridsocial.AccountsFixtures
  # (auto-imported by ConnCase). admin_conn/2 opens the sudo window.

  setup %{conn: conn} do
    # The DB-backed config GenServer isn't started in test env; the update
    # path writes through it, so start it here (async: false → shared
    # sandbox connection).
    start_supervised!(Hybridsocial.Config.Store)

    admin = create_user("emailadmin", "emailadmin@test.com") |> make_admin()

    System.delete_env("RESEND_API_KEY")
    System.delete_env("SMTP_HOST")

    on_exit(fn ->
      System.delete_env("RESEND_API_KEY")
      System.delete_env("SMTP_HOST")
    end)

    %{conn: admin_conn(conn, admin)}
  end

  describe "GET /api/v1/admin/email" do
    test "reports no env override by default", %{conn: conn} do
      body = conn |> get("/api/v1/admin/email") |> json_response(200)
      assert body["env_override"] == false
      assert body["env_provider"] == nil
    end

    test "reports a resend override when RESEND_API_KEY is set", %{conn: conn} do
      System.put_env("RESEND_API_KEY", "re_test_key")

      body = conn |> get("/api/v1/admin/email") |> json_response(200)
      assert body["env_override"] == true
      assert body["env_provider"] == "resend"
      # effective provider is reported, not the stale DB default
      assert body["provider"] == "resend"
    end

    test "reports an smtp override when SMTP_HOST is set", %{conn: conn} do
      System.put_env("SMTP_HOST", "smtp.example.com")

      body = conn |> get("/api/v1/admin/email") |> json_response(200)
      assert body["env_override"] == true
      assert body["env_provider"] == "smtp"
    end

    test "resend takes precedence over smtp", %{conn: conn} do
      System.put_env("RESEND_API_KEY", "re_test_key")
      System.put_env("SMTP_HOST", "smtp.example.com")

      body = conn |> get("/api/v1/admin/email") |> json_response(200)
      assert body["env_provider"] == "resend"
    end
  end

  describe "PUT /api/v1/admin/email" do
    test "persists provider + smtp settings when there is no env override", %{conn: conn} do
      body =
        conn
        |> put("/api/v1/admin/email", %{"provider" => "smtp", "smtp_host" => "smtp.foo.test"})
        |> json_response(200)

      assert body["provider"] == "smtp"
      assert body["smtp_host"] == "smtp.foo.test"
    end

    test "ignores locked fields but keeps from_address editable under env override", %{conn: conn} do
      System.put_env("RESEND_API_KEY", "re_test_key")

      body =
        conn
        |> put("/api/v1/admin/email", %{
          "provider" => "smtp",
          "smtp_host" => "attacker.example.com",
          "from_address" => "hello@bassam.social"
        })
        |> json_response(200)

      # provider is forced to the env transport; the SMTP host change is dropped
      assert body["env_override"] == true
      assert body["provider"] == "resend"
      refute body["smtp_host"] == "attacker.example.com"
      # from address is always editable (it's the From header)
      assert body["from_address"] == "hello@bassam.social"
    end
  end
end
