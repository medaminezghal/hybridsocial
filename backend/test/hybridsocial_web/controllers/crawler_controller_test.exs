defmodule HybridsocialWeb.CrawlerControllerTest do
  # async: false because the Config.Store GenServer needs the shared DB
  # sandbox connection to read instance settings during crawler rendering.
  use HybridsocialWeb.ConnCase, async: false

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  alias Hybridsocial.Accounts
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts

  @crawler_ua "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
  @browser_ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Chrome"

  defp register(handle) do
    uniq = :erlang.unique_integer([:positive])

    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => "#{handle}_#{uniq}",
        "email" => "#{handle}_#{uniq}@example.com",
        "display_name" => handle,
        "password" => "password1234567890",
        "password_confirmation" => "password1234567890"
      })

    identity
  end

  defp crawler_conn do
    build_conn() |> put_req_header("user-agent", @crawler_ua)
  end

  defp browser_conn do
    build_conn() |> put_req_header("user-agent", @browser_ua)
  end

  describe "GET /post/:id" do
    test "serves full OG for a public post to a crawler" do
      alice = register("alice_og")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "Hello, world — this is public"})

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      assert body =~ ~s(property="og:title")
      assert body =~ ~s(property="og:description")
      assert body =~ ~s(property="og:image")
      assert body =~ ~s(property="og:type" content="article")
      assert body =~ "Hello, world"
      # Author name surfaces in og:title
      assert body =~ "alice_og"
    end

    test "serves placeholder OG for a private (followers-only) post" do
      alice = register("alice_priv")

      {:ok, post} =
        Posts.create_post(alice.id, %{
          "content" => "secret message",
          "visibility" => "followers"
        })

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      assert body =~ "Private post on"
      refute body =~ "secret message"
    end

    test "returns 404 for unknown post id" do
      conn = get(crawler_conn(), "/post/#{Ecto.UUID.generate()}")
      assert response(conn, 404)
    end

    test "browser requests get a redirect shell, not OG content" do
      alice = register("alice_browser")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "public"})

      conn = get(browser_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      refute body =~ ~s(property="og:title")
      assert body =~ "window.location.replace"
    end

    test "uses the configured instance name, not a hardcoded value" do
      alice = register("alice_instance")
      {:ok, post} = Posts.create_post(alice.id, %{"content" => "hi"})

      :ok = Hybridsocial.Config.set("instance_name", "MyCustomInstance")

      conn = get(crawler_conn(), "/post/#{post.id}")
      body = response(conn, 200)

      assert body =~ "MyCustomInstance"
    end
  end

  describe "GET /@:handle" do
    test "serves full profile OG when allow_unfurl is true" do
      alice = register("alice_profile")

      conn = get(crawler_conn(), "/@#{alice.handle}")
      body = response(conn, 200)

      assert body =~ "alice_profile"
      assert body =~ ~s(property="og:type" content="profile")
    end

    test "serves placeholder OG when allow_unfurl is false" do
      alice = register("alice_optout")
      secret_bio = "my-highly-distinctive-secret-bio-xyz"
      secret_name = "Definitely Not In The URL Name"

      alice
      |> Ecto.Changeset.change(%{
        allow_unfurl: false,
        bio: secret_bio,
        display_name: secret_name
      })
      |> Repo.update!()

      conn = get(crawler_conn(), "/@#{alice.handle}")
      body = response(conn, 200)

      # Placeholder title and description — no display_name, no bio.
      assert body =~ ~s(og:title" content="User on)
      assert body =~ ~s(og:description" content="A member of)
      refute body =~ secret_bio
      refute body =~ secret_name
    end

    test "returns 404 for unknown handle" do
      conn = get(crawler_conn(), "/@definitelynotarealuser12345")
      assert response(conn, 404)
    end
  end

  describe "GET /sitemap.xml (index)" do
    test "returns a sitemapindex pointing at child sitemaps" do
      alice = register("smp_idx")
      {:ok, _post} = Posts.create_post(alice.id, %{"content" => "indexed"})

      conn = get(build_conn(), "/sitemap.xml")
      body = response(conn, 200)

      content_type = get_resp_header(conn, "content-type") |> hd()
      assert content_type =~ "application/xml"
      assert body =~ "<sitemapindex"
      assert body =~ "/sitemap/static"
      assert body =~ "/sitemap/posts/1"
      assert body =~ "/sitemap/profiles/1"
    end

    test "posts index entries reflect the actual post count" do
      # No posts at all → no /sitemap/posts/ entry in the index.
      conn = get(build_conn(), "/sitemap.xml")
      body = response(conn, 200)

      assert body =~ "/sitemap/static"
      refute body =~ "/sitemap/posts/"
    end
  end

  describe "GET /sitemap/static" do
    test "emits the static page URLs" do
      conn = get(build_conn(), "/sitemap/static")
      body = response(conn, 200)

      assert body =~ "<urlset"
      assert body =~ "/legal/about"
      assert body =~ "/legal/privacy"
      assert body =~ "/directory"
    end
  end

  describe "GET /sitemap/posts/:page" do
    test "returns page 1 with only public+local posts" do
      alice = register("smp_p_a")
      {:ok, public} = Posts.create_post(alice.id, %{"content" => "public hi"})

      {:ok, private} =
        Posts.create_post(alice.id, %{"content" => "shh", "visibility" => "followers"})

      conn = get(build_conn(), "/sitemap/posts/1")
      body = response(conn, 200)

      assert body =~ "<urlset"
      assert body =~ "/post/#{public.id}"
      refute body =~ "/post/#{private.id}"
    end

    test "page out of range returns an empty urlset (not 404)" do
      conn = get(build_conn(), "/sitemap/posts/999999")
      body = response(conn, 200)

      assert body =~ "<urlset"
      refute body =~ "<url>"
    end

    test "invalid page param normalizes to 1" do
      conn = get(build_conn(), "/sitemap/posts/not-a-number")
      assert response(conn, 200) =~ "<urlset"
    end
  end

  describe "GET /sitemap/profiles/:page" do
    test "lists discoverable+unfurl-allowed profiles" do
      alice = register("smp_pr_a")
      hidden = register("smp_pr_h")

      hidden
      |> Ecto.Changeset.change(%{allow_unfurl: false})
      |> Repo.update!()

      conn = get(build_conn(), "/sitemap/profiles/1")
      body = response(conn, 200)

      assert body =~ "/@#{alice.handle}"
      refute body =~ "/@#{hidden.handle}"
    end
  end

  describe "GET /robots.txt" do
    test "returns a robots.txt with the expected rules" do
      conn = get(build_conn(), "/robots.txt")
      body = response(conn, 200)

      assert body =~ "User-agent: *"
      assert body =~ "Allow: /post/"
      assert body =~ "Allow: /@"
      assert body =~ "Disallow: /messages"
      assert body =~ "Disallow: /settings"
      assert body =~ "Disallow: /admin"
      assert body =~ "Sitemap:"
    end
  end
end
