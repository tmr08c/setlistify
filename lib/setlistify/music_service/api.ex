defmodule Setlistify.MusicService.API do
  @moduledoc """
  Provider-agnostic public API for music service operations within the app.

  Dispatch is based on the type of the user_session struct, so callers do not
  need to reference a specific provider (e.g. Spotify) directly.
  """

  alias Setlistify.Spotify

  @type user_session :: Spotify.UserSession.t()

  @callback search_for_track(user_session(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}

  @callback create_playlist(user_session(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}

  @callback add_tracks_to_playlist(user_session(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}

  def search_for_track(%Spotify.UserSession{} = user_session, artist, track) do
    Spotify.API.search_for_track(user_session, artist, track)
  end

  def create_playlist(%Spotify.UserSession{} = user_session, name, description) do
    Spotify.API.create_playlist(user_session, name, description)
  end

  def add_tracks_to_playlist(%Spotify.UserSession{} = user_session, playlist_id, tracks) do
    Spotify.API.add_tracks_to_playlist(user_session, playlist_id, tracks)
  end
end
