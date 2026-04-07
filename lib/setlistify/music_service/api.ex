defmodule Setlistify.MusicService.API do
  @moduledoc """
  Provider-agnostic public API for music service operations within the app.

  Dispatch is based on the type of the user_session struct, so callers do not
  need to reference a specific provider (e.g. Spotify) directly.
  """

  require OpenTelemetry.Tracer

  alias Setlistify.{AppleMusic, Spotify}

  @type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t()

  @callback search_for_track(user_session(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}

  @callback create_playlist(user_session(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}

  @callback add_tracks_to_playlist(user_session(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}

  defp impl(%Spotify.UserSession{}) do
    OpenTelemetry.Tracer.set_attribute("peer.service", "spotify")
    Spotify.API
  end

  defp impl(%AppleMusic.UserSession{}) do
    OpenTelemetry.Tracer.set_attribute("peer.service", "apple_music")
    AppleMusic.API
  end

  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "Setlistify.MusicService.API.search_for_track" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id},
        {"music.artist", artist},
        {"music.track", track}
      ])

      impl(user_session).search_for_track(user_session, artist, track)
    end
  end

  def create_playlist(user_session, name, description) do
    OpenTelemetry.Tracer.with_span "Setlistify.MusicService.API.create_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id},
        {"playlist.name", name}
      ])

      impl(user_session).create_playlist(user_session, name, description)
    end
  end

  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    OpenTelemetry.Tracer.with_span "Setlistify.MusicService.API.add_tracks_to_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id},
        {"playlist.id", playlist_id},
        {"tracks.count", length(tracks)}
      ])

      impl(user_session).add_tracks_to_playlist(user_session, playlist_id, tracks)
    end
  end

  def get_embed("spotify", url), do: Spotify.API.get_embed(url)
end
