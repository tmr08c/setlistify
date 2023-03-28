defmodule Setlistify.Spotify.API do
  @callback new(String.t()) :: Req.Request.t()
  def new(token), do: impl().new(token)

  @callback username(Req.Request.t()) :: String.t()
  def username(client), do: impl().username(client)

  # TODO Set response type
  @callback search_for_track(Req.Request.t(), String.t(), String.t()) ::
              nil | %{uri: String.t(), preview_url: String.t()}
  def search_for_track(client, artist, track) do
    :spotify_track_cache
    |> Cachex.fetch({artist, track}, fn {artist, track} ->
      impl().search_for_track(client, artist, track)
    end)
    |> elem(1)
  end

  defp impl do
    Application.get_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.ExternalClient)
  end
end
