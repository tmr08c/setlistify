defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  require Logger

  def new(token, endpoint \\ "https://api.spotify.com/v1/") do
    Logger.debug("Current Spotify API client token: #{token}")
    Req.new(base_url: endpoint, auth: {:bearer, token})
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
end
