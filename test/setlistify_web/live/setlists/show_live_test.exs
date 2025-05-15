defmodule SetlistifyWeb.Setlists.ShowLiveTest do
  use SetlistifyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.{SetlistFm, Spotify}

  # Cache fetching happens in another process, managed by Cachex. The process we
  # start in our application tree is a supervisor, so explictly `allow`ing with
  # that PID does not work. This will enable "global" mode which means  any
  # process will respect our `expect` at the cost of not being able to run with
  # `async: true`
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(:clear_cache, fn ->
      Cachex.clear!(:spotify_track_cache)
    end)
  end

  test "viewing a setlist when logged out shows list of songs", %{conn: conn} do
    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :get_setlist, 1, fn ^setlist_id ->
      %{
        artist: "The Beatles",
        venue: %{name: "Compaq Center"},
        date: Date.new!(2023, 01, 01),
        sets: [
          %{name: "Warm up", songs: [%{title: "a warm up song"}]},
          %{name: nil, songs: [%{title: "main set song1"}, %{title: "main set song2"}]},
          %{name: nil, encore: 1, songs: [%{title: "encore song1"}, %{title: "encore song2"}]}
        ]
      }
    end)

    {:ok, _view, html} = live(conn, ~p"/setlist/#{setlist_id}")

    assert html =~ "warm up"
    assert html =~ "a warm up song"

    assert html =~ "main set song1"
    assert html =~ "main set song2"

    assert html =~ "Encore 1"
    assert html =~ "encore song1"
    assert html =~ "encore song2"
  end

  test "viewing a setlist when authenticated with Spotify searches for songs", %{conn: conn} do
    conn = init_test_session(conn, %{access_token: "token", account_name: "username"})
    setlist_id = Ecto.UUID.generate()
    artist = "some artist"

    # Mock setlist reponse
    expect(SetlistFm.API.MockClient, :get_setlist, 1, fn ^setlist_id ->
      %{
        artist: artist,
        venue: %{name: "Compaq Center"},
        date: Date.utc_today(),
        sets: [%{name: nil, songs: [%{title: "song1"}, %{title: "song2"}]}]
      }
    end)

    # Mock searching for songs in setlist
    Spotify.API.MockClient
    |> expect(:new, 2, fn "token" -> %Req.Request{} end)
    |> expect(:search_for_track, fn _client, ^artist, "song1", "username" ->
      # We have a match for song
      %{uri: "spotify:track:123", preview_url: "http://www.example.com"}
    end)
    |> expect(:search_for_track, 2, fn _client, ^artist, "song2", "username" ->
      # We cannot find a match for the song
      #
      # Because we do not find a match, we will not cache it, resulting in
      # making the call twice for both mount calls
      nil
    end)

    {:ok, _view, html} = live(conn, ~p"/setlist/#{setlist_id}")

    assert html =~ "song1"
    assert html =~ "song2"

    assert_has_element(html, "[aria-label='found matching song']", count: 1)
    assert_has_element(html, "[aria-label='no matching song found']", count: 1)
  end

  test "creating a playlist redirects to playlist page", %{conn: conn} do
    conn = init_test_session(conn, %{access_token: "token", account_name: "username"})
    setlist_id = Ecto.UUID.generate()
    artist = "some artist"
    venue = "some venue"
    external_url = "https://www.open.spotify.com/playlist/playlist_123"

    # Mock setlist reponse
    expect(SetlistFm.API.MockClient, :get_setlist, 1, fn ^setlist_id ->
      %{
        artist: artist,
        venue: %{name: venue},
        date: Date.utc_today(),
        sets: [%{name: nil, songs: [%{title: "song1"}, %{title: "song2"}]}]
      }
    end)

    # Mock searching for songs in setlist
    Spotify.API.MockClient
    |> expect(:new, 2, fn "token" -> %Req.Request{} end)
    |> expect(:search_for_track, fn _client, ^artist, "song1", "username" ->
      # We have a match for song
      %{uri: "spotify:track:123", preview_url: "http://www.example.com"}
    end)
    |> expect(:search_for_track, 2, fn _client, ^artist, "song2", "username" ->
      # We cannot find a match for the song
      #
      # Because we do not find a match, we will not cache it, resulting in
      # making the call twice for both mount calls
      nil
    end)

    {:ok, view, _html} = live(conn, ~p"/setlist/#{setlist_id}")

    # Mock playlist creation
    Spotify.API.MockClient
    |> expect(:new, 1, fn "token" -> %Req.Request{} end)
    |> expect(:create_playlist, fn _client, name, description ->
      formatted_date = Date.utc_today() |> Date.to_iso8601()
      assert name =~ artist
      assert name =~ venue
      assert name =~ formatted_date

      assert description =~ "Setlistify"
      assert description =~ artist
      assert description =~ venue
      assert description =~ formatted_date

      %{id: "playlist_id_123", external_url: external_url}
    end)
    |> expect(:add_tracks_to_playlist, fn _client, "playlist_id_123", tracks ->
      assert tracks == ["spotify:track:123"]
      :ok
    end)

    result = view |> element("button", "Create Playlist") |> render_click()
    {:error, {:live_redirect, %{kind: :push, to: redirect_to}}} = result

    assert redirect_to == "/playlists?provider=spotify&url=" <> URI.encode_www_form(external_url)
  end
end