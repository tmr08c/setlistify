defmodule SetlistifyWeb.Playlists.ShowLiveTest do
  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.Spotify.API.MockClient
  alias Setlistify.Spotify.{SessionManager, UserSession}

  setup :verify_on_exit!

  setup do
    # Start necessary services for authentication  
    start_supervised!({Registry, keys: :unique, name: Setlistify.Spotify.UserSessionRegistry})

    start_supervised!(
      {DynamicSupervisor, strategy: :one_for_one, name: Setlistify.Spotify.SessionSupervisor}
    )

    # Create a test user session
    user_id = "test-user-#{System.unique_integer()}"

    user_session = %UserSession{
      user_id: user_id,
      username: "Test User",
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: System.system_time(:second) + 3600
    }

    # Start the session manager
    {:ok, _pid} = SessionManager.start_link({user_id, user_session})

    # Create an authenticated connection
    conn = build_conn()
    authenticated_conn = authenticate_conn(conn, user_id)

    %{conn: authenticated_conn, user_id: user_id, user_session: user_session}
  end

  describe "playlists" do
    test "displays link to playlist", %{conn: conn} do
      external_url = "https://open.spotify.com/playlist/123"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(MockClient, :get_embed, 2, fn ^external_url ->
        {:ok, html}
      end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{external_url}")

      assert has_element?(view, "a[href='#{external_url}']", "here")
    end

    test "embeds Spotify player using oEmbed", %{conn: conn} do
      playlist_url = "https://open.spotify.com/playlist/123"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(MockClient, :get_embed, 2, fn ^playlist_url ->
        {:ok, html}
      end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{playlist_url}")

      # Check that the iframe with the correct src exists within the rendered HTML
      assert view |> element("iframe[src='spotify:embed:123']") |> has_element?()
    end

    test "handles oEmbed API errors gracefully", %{conn: conn} do
      playlist_url = "https://open.spotify.com/playlist/123"

      expect(MockClient, :get_embed, 2, fn ^playlist_url ->
        {:error, :failed_to_fetch}
      end)

      {:ok, _view, html} = live(conn, ~p"/playlists?provider=spotify&url=#{playlist_url}")

      assert html =~ "Failed to load Spotify embed"
    end

    test "handles URL encoding properly", %{conn: conn} do
      encoded_url = "https%3A%2F%2Fopen.spotify.com%2Fplaylist%2F123%3Fsi%3Dabc%26ref%3Dshare"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(MockClient, :get_embed, 2, fn ^encoded_url ->
        {:ok, html}
      end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{encoded_url}")

      # Check that the iframe with the correct src exists within the rendered HTML
      assert view |> element("iframe[src='spotify:embed:123']") |> has_element?()
    end
  end

  test "shows error for unsupported provider", %{conn: conn} do
    external_url = "https://music.apple.com/playlist/123"

    {:ok, _view, html} = live(conn, ~p"/playlists?provider=apple&url=#{external_url}")

    assert html =~ "Unsupported provider: apple"
  end

  test "shows error when required parameters are missing", %{conn: conn} do
    # Test with no parameters
    {:ok, _view, html} = live(conn, ~p"/playlists")
    assert html =~ "Missing required parameters"

    # Test with only provider
    {:ok, _view, html} = live(conn, ~p"/playlists?provider=spotify")
    assert html =~ "Missing required parameters"

    # Test with only URL
    {:ok, _view, html} = live(conn, ~p"/playlists?url=https://open.spotify.com/playlist/123")
    assert html =~ "Missing required parameters"
  end
end
