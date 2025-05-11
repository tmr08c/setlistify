defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  require Logger

  def new(token, endpoint \\ "https://api.spotify.com/v1/") do
    Logger.debug("Current Spotify API client token: #{token}")
    default_opts = [base_url: endpoint, auth: {:bearer, token}]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    Req.new(Keyword.merge(default_opts, config_opts))
  end

  def username(client) do
    resp = Req.get!(client, url: "/me")
    resp.body["display_name"] || resp.body["id"]
  end

  def search_for_track(client, artist, track) do
    resp =
      Req.get!(client,
        url: "/search",
        params: %{q: "artist:#{artist} track:#{track}", type: "track"}
      )

    items = resp.body |> Map.get("tracks", %{}) |> Map.get("items", [])

    with nil <- List.first(items) do
      Logger.warning("No search results for artist: #{artist}, track: #{track}")
      nil
    else
      track_info ->
        Logger.info("Found match for artist: #{artist}, track: #{track}")
        %{uri: track_info["uri"], preview_url: track_info["preview_url"]}
    end
  end

  def create_playlist(client, name, description) do
    # TODO Update to no longer user the `username` function
    #
    # 1. it would be preferable not to re-request this data while the user is logged in
    # 2. I probably don't want to use display name here and want to *always* use ID
    resp =
      Req.post!(client,
        url: "/users/#{username(client)}/playlists",
        json: %{
          name: name,
          description: description,
          public: false
        }
      )

    %{
      id: Map.fetch!(resp.body, "id"),
      external_url: resp.body |> Map.fetch!("external_urls") |> Map.fetch!("spotify")
    }
  end

  def add_tracks_to_playlist(_, _, []), do: :ok

  def add_tracks_to_playlist(client, playlist_id, tracks) do
    resp =
      Req.post!(client,
        url: "/playlists/#{playlist_id}/tracks",
        json: %{uris: tracks}
      )

    if resp.status == 201, do: :ok, else: :error
  end

  def get_embed(url) do
    resp =
      [base_url: Application.get_env(:setlistify, :oembed_endpoint, "https://open.spotify.com")]
      |> Keyword.merge(Application.get_env(:setlistify, :spotify_req_options, []))
      |> Req.get(url: "/oembed?url=#{URI.encode_www_form(url)}")

    case resp do
      {:ok, %{status: 200} = resp} ->
        case resp.body do
          %{"html" => html} -> {:ok, html}
          _ -> {:error, :invalid_response}
        end

      _ ->
        {:error, :failed_to_fetch}
    end
  end
end
