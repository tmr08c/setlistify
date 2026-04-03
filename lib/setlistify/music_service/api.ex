defmodule Setlistify.MusicService.API do
  @moduledoc """
  Provider-agnostic public API for music service operations within the app.

  Dispatch is based on the type of the user_session struct, so callers do not
  need to reference a specific provider (e.g. Spotify) directly.
  """

  alias Setlistify.{AppleMusic, Spotify}

  @type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t()

  @callback search_for_track(user_session(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}

  @callback create_playlist(user_session(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}

  @callback add_tracks_to_playlist(user_session(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}

  defp impl(%Spotify.UserSession{}), do: Spotify.API
  defp impl(%AppleMusic.UserSession{}), do: AppleMusic.API

  def search_for_track(user_session, artist, track),
    do: impl(user_session).search_for_track(user_session, artist, track)

  def create_playlist(user_session, name, description),
    do: impl(user_session).create_playlist(user_session, name, description)

  def add_tracks_to_playlist(user_session, playlist_id, tracks),
    do: impl(user_session).add_tracks_to_playlist(user_session, playlist_id, tracks)

  def get_embed("spotify", url), do: Spotify.API.get_embed(url)
  def get_embed("apple_music", url), do: AppleMusic.API.get_embed(url)
end
