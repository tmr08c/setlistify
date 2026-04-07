defmodule Setlistify.AppleMusic.API do
  @moduledoc """
  Interface module for Apple Music API operations.
  """

  @behaviour Setlistify.MusicService.API

  require OpenTelemetry.Tracer

  alias Setlistify.AppleMusic.UserSession

  @callback build_user_session(String.t(), String.t(), String.t()) ::
              {:ok, UserSession.t()}

  def build_user_session(user_token, storefront, user_id) do
    {:ok, %UserSession{user_token: user_token, storefront: storefront, user_id: user_id}}
  end

  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}
  def search_for_track(user_session, artist, track) do
    parent_ctx = OpenTelemetry.Ctx.get_current()
    parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

    :apple_music_track_cache
    |> Cachex.fetch({artist, track}, fn {artist, track} ->
      OpenTelemetry.Ctx.attach(parent_ctx)
      OpenTelemetry.Tracer.set_current_span(parent_span)

      impl().search_for_track(user_session, artist, track)
    end)
    |> elem(1)
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}
  def create_playlist(user_session, name, description),
    do: impl().create_playlist(user_session, name, description)

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
