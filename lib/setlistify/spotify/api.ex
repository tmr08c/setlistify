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

  @callback create_playlist(Req.Request.t(), String.t(), String.t()) :: %{
              id: String.t(),
              external_url: String.t()
            }
  def create_playlist(client, name, description) do
    impl().create_playlist(client, name, description)
  end

  @callback add_tracks_to_playlist(Req.Request.t(), String.t(), [String.t()]) :: :ok | :error
  def add_tracks_to_playlist(client, playlist_id, tracks) do
    impl().add_tracks_to_playlist(client, playlist_id, tracks)
  end

  @callback get_embed(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_embed(url) do
    impl().get_embed(url)
  end

  @callback refresh_token(String.t()) ::
              {:ok, %{access_token: String.t(), refresh_token: String.t(), expires_in: integer()}}
              | {:error, atom()}
  def refresh_token(refresh_token) do
    impl().refresh_token(refresh_token)
  end

  @callback exchange_code(String.t(), String.t()) ::
              {:ok, %{access_token: String.t(), refresh_token: String.t(), expires_in: integer()}}
              | {:error, atom()}
  def exchange_code(code, redirect_uri) do
    impl().exchange_code(code, redirect_uri)
  end

  defp impl do
    Application.get_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.ExternalClient)
  end
end
