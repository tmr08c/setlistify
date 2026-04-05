defmodule SetlistifyWeb.Playlists.ShowLiveTest do
  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.Spotify.API.MockClient, as: SpotifyMock
  alias Setlistify.Spotify.{SessionManager, UserSession}
  alias Setlistify.AppleMusic.SessionManager, as: AppleMusicSessionManager
  alias Setlistify.AppleMusic.UserSession, as: AppleMusicUserSession

  setup :verify_on_exit!

  defp spotify_conn(conn) do
    user_id = "test-user-#{System.unique_integer()}"

    user_session = %UserSession{
      user_id: user_id,
      username: "Test User",
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: System.system_time(:second) + 3600
    }

    {:ok, _pid} = SessionManager.start_link({user_id, user_session})
    authenticated_conn = authenticate_conn(conn, user_id)
    {authenticated_conn, user_id}
  end

  defp apple_music_conn(conn) do
    user_id = "test-user-#{System.unique_integer()}"

    user_session = %AppleMusicUserSession{
      user_id: user_id,
      user_token: "test-user-token",
      storefront: "us"
    }

    {:ok, _pid} = AppleMusicSessionManager.start_link({user_id, user_session})

    authenticated_conn =
      Plug.Test.init_test_session(conn, user_id: user_id, auth_provider: "apple_music")

    {authenticated_conn, user_id}
  end

  describe "spotify playlists" do
    setup %{conn: conn} do
      {conn, _user_id} = spotify_conn(conn)
      %{conn: conn}
    end

    test "displays link to playlist", %{conn: conn} do
      external_url = "https://open.spotify.com/playlist/123"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(SpotifyMock, :get_embed, 2, fn ^external_url -> {:ok, html} end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{external_url}")

      assert has_element?(view, "a[href='#{external_url}']", "Open Playlist")
    end

    test "embeds Spotify player", %{conn: conn} do
      playlist_url = "https://open.spotify.com/playlist/123"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(SpotifyMock, :get_embed, 2, fn ^playlist_url -> {:ok, html} end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{playlist_url}")

      assert view |> element("iframe[src='spotify:embed:123']") |> has_element?()
    end

    test "handles embed errors gracefully", %{conn: conn} do
      playlist_url = "https://open.spotify.com/playlist/123"

      expect(SpotifyMock, :get_embed, 2, fn ^playlist_url -> {:error, :failed_to_fetch} end)

      {:ok, _view, html} = live(conn, ~p"/playlists?provider=spotify&url=#{playlist_url}")

      assert html =~ "Failed to load Spotify embed"
    end

    test "handles URL encoding properly", %{conn: conn} do
      encoded_url = "https%3A%2F%2Fopen.spotify.com%2Fplaylist%2F123%3Fsi%3Dabc%26ref%3Dshare"
      html = "<iframe src='spotify:embed:123'></iframe>"

      expect(SpotifyMock, :get_embed, 2, fn ^encoded_url -> {:ok, html} end)

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=spotify&url=#{encoded_url}")

      assert view |> element("iframe[src='spotify:embed:123']") |> has_element?()
    end
  end

  describe "apple music playlists" do
    setup %{conn: conn} do
      {conn, _user_id} = apple_music_conn(conn)
      %{conn: conn}
    end

    test "shows success message and link to Apple Music library", %{conn: conn} do
      # Apple Music library playlist IDs (p.) can't be linked or embedded directly.
      # The page links to the library root instead.
      playlist_url = "https://music.apple.com/library/playlist/p.abc123"

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=apple_music&url=#{playlist_url}")

      assert has_element?(view, "a[href='https://music.apple.com']", "Open Playlist")
    end

    test "does not show an embed player", %{conn: conn} do
      playlist_url = "https://music.apple.com/library/playlist/p.abc123"

      {:ok, view, _html} = live(conn, ~p"/playlists?provider=apple_music&url=#{playlist_url}")

      refute has_element?(view, "iframe")
    end
  end

  test "shows error for unsupported provider", %{conn: conn} do
    {conn, _} = spotify_conn(conn)
    external_url = "https://music.apple.com/playlist/123"

    {:ok, _view, html} = live(conn, ~p"/playlists?provider=apple&url=#{external_url}")

    assert html =~ "Unsupported provider: apple"
  end

  test "shows error when required parameters are missing", %{conn: conn} do
    {conn, _} = spotify_conn(conn)

    {:ok, _view, html} = live(conn, ~p"/playlists")
    assert html =~ "Missing required parameters"

    {:ok, _view, html} = live(conn, ~p"/playlists?provider=spotify")
    assert html =~ "Missing required parameters"

    {:ok, _view, html} = live(conn, ~p"/playlists?url=https://open.spotify.com/playlist/123")
    assert html =~ "Missing required parameters"
  end
end
