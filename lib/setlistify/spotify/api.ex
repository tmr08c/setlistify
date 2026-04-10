defmodule Setlistify.Spotify.API do
  @moduledoc false
  @behaviour Setlistify.MusicService.API

  alias Setlistify.Spotify.UserSession

  require OpenTelemetry.Tracer

  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{track_id: String.t()} | {:error, atom()}
  def search_for_track(user_session, artist, track) do
    Setlistify.Cache.fetch(:spotify_track_cache, {artist, track}, fn {artist, track} ->
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

  @callback get_embed(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_embed(url) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.get_embed" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"embed.url", url}
      ])

      impl().get_embed(url)
    end
  end

  @callback refresh_token(String.t()) ::
              {:ok, %{access_token: String.t(), refresh_token: String.t(), expires_in: integer()}}
              | {:error, atom()}
  def refresh_token(refresh_token) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"oauth.grant_type", "refresh_token"}
      ])

      impl().refresh_token(refresh_token)
    end
  end

  @callback exchange_code(String.t(), String.t()) ::
              {:ok, UserSession.t()}
              | {:error, atom()}
  def exchange_code(code, redirect_uri) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.exchange_code" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"oauth.grant_type", "authorization_code"},
        {"oauth.redirect_uri", redirect_uri}
      ])

      impl().exchange_code(code, redirect_uri)
    end
  end

  @callback refresh_to_user_session(String.t()) ::
              {:ok, UserSession.t()}
              | {:error, atom()}
  def refresh_to_user_session(refresh_token) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.refresh_to_user_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"oauth.grant_type", "refresh_token"}
      ])

      impl().refresh_to_user_session(refresh_token)
    end
  end

  defp impl do
    Application.get_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.ExternalClient)
  end
end
