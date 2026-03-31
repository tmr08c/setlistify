defmodule Setlistify.Spotify.API do
  @behaviour Setlistify.MusicService.API

  require OpenTelemetry.Tracer

  alias Setlistify.Spotify.UserSession

  # TODO Set response type
  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}
  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.search_for_track" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"music.artist", artist},
        {"music.track", track},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      # Cachex uses a separate process, so we need to propogate OpenTelemetry context
      # TODO: If we do this enough we should consider making a helper
      parent_ctx = OpenTelemetry.Ctx.get_current()
      parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

      :spotify_track_cache
      |> Cachex.fetch({artist, track}, fn {artist, track} ->
        OpenTelemetry.Ctx.attach(parent_ctx)
        OpenTelemetry.Tracer.set_current_span(parent_span)

        impl().search_for_track(user_session, artist, track)
      end)
      |> elem(1)
    end
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}
  def create_playlist(user_session, name, description) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.create_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"playlist.name", name},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      impl().create_playlist(user_session, name, description)
    end
  end

  @callback add_tracks_to_playlist(UserSession.t(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}
  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.API.add_tracks_to_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "spotify"},
        {"playlist.id", playlist_id},
        {"tracks.count", length(tracks)},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      impl().add_tracks_to_playlist(user_session, playlist_id, tracks)
    end
  end

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
              {:ok, Setlistify.Spotify.UserSession.t()}
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
              {:ok, Setlistify.Spotify.UserSession.t()}
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
