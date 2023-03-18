defmodule Setlistify.Spotify.API do
  @callback new(String.t()) :: Req.Request.t()
  def new(token), do: impl().new(token)

  @callback username(Req.Request.t()) :: String.t()
  def username(client), do: impl().username(client)

  defp impl do
    Application.get_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.ExternalClient)
  end
end
