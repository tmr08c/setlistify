defmodule Setlistify.Spotify.API do
  alias Setlistify.Spotify.UserSession

  @callback username(UserSession.t()) :: String.t()
  def username(user_session), do: impl().username(user_session)

  # TODO Set response type
  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{uri: String.t(), preview_url: String.t()}
  def search_for_track(user_session, artist, track) do
    :spotify_track_cache
    |> Cachex.fetch({artist, track}, fn {artist, track} ->
      impl().search_for_track(user_session, artist, track)
    end)
    |> elem(1)
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}
  def create_playlist(user_session, name, description) do
    impl().create_playlist(user_session, name, description)
  end

  @callback add_tracks_to_playlist(UserSession.t(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}
  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    impl().add_tracks_to_playlist(user_session, playlist_id, tracks)
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
              {:ok, Setlistify.Spotify.UserSession.t()}
              | {:error, atom()}
  def exchange_code(code, redirect_uri) do
    impl().exchange_code(code, redirect_uri)
  end

  @callback refresh_to_user_session(String.t()) ::
              {:ok, Setlistify.Spotify.UserSession.t()}
              | {:error, atom()}
  def refresh_to_user_session(refresh_token) do
    impl().refresh_to_user_session(refresh_token)
  end

  defp impl do
    Application.get_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.ExternalClient)
  end
end
