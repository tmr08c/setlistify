defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  def new(token, endpoint \\ "https://api.spotify.com/v1/") do
    Req.new(base_url: endpoint, auth: {:bearer, token})
  end

  def username(client) do
    resp = Req.get!(client, url: "/me")
    resp.body["display_name"] || resp.body["id"]
  end
end
