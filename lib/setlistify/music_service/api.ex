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

  def search_for_track(%Spotify.UserSession{} = s, artist, track),
    do: Spotify.API.search_for_track(s, artist, track)

  def search_for_track(%AppleMusic.UserSession{} = s, artist, track),
    do: AppleMusic.API.search_for_track(s, artist, track)

  def create_playlist(%Spotify.UserSession{} = s, name, desc),
    do: Spotify.API.create_playlist(s, name, desc)

  def create_playlist(%AppleMusic.UserSession{} = s, name, desc),
    do: AppleMusic.API.create_playlist(s, name, desc)

  def add_tracks_to_playlist(%Spotify.UserSession{} = s, id, tracks),
    do: Spotify.API.add_tracks_to_playlist(s, id, tracks)

  def add_tracks_to_playlist(%AppleMusic.UserSession{} = s, id, tracks),
    do: AppleMusic.API.add_tracks_to_playlist(s, id, tracks)

  def get_embed("spotify", url), do: Spotify.API.get_embed(url)
  def get_embed("apple_music", url), do: AppleMusic.API.get_embed(url)
end
