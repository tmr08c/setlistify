defmodule Setlistify.AppleMusic.API do
  @moduledoc """
  Interface module for Apple Music API operations.
  """

  @behaviour Setlistify.MusicService.API

  alias Setlistify.AppleMusic.UserSession

  @callback build_user_session(String.t(), String.t(), String.t()) ::
              {:ok, UserSession.t()}

  def build_user_session(user_token, storefront, user_id) do
    {:ok, %UserSession{user_token: user_token, storefront: storefront, user_id: user_id}}
  end

  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{track_id: String.t()} | {:error, atom()}
  def search_for_track(user_session, artist, track) do
    Setlistify.Cache.fetch(:apple_music_track_cache, {artist, track}, fn {artist, track} ->
      impl().search_for_track(user_session, artist, track)
    end)
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}
  def create_playlist(user_session, name, description), do: impl().create_playlist(user_session, name, description)

  @callback add_tracks_to_playlist(UserSession.t(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}
  def add_tracks_to_playlist(user_session, playlist_id, tracks),
    do: impl().add_tracks_to_playlist(user_session, playlist_id, tracks)

  defp impl do
    Application.get_env(
      :setlistify,
      :apple_music_api_client,
      Setlistify.AppleMusic.API.ExternalClient
    )
  end
end
