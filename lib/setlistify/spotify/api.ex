defmodule Setlistify.Spotify.API do
  require OpenTelemetry.Tracer

  alias Setlistify.Spotify.UserSession

  # TODO Set response type
  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{uri: String.t(), preview_url: String.t()}
  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "spotify.api.search_for_track" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "spotify"},
        {"spotify.operation", "search_track"},
        {"spotify.artist", artist},
        {"spotify.track", track},
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
