defmodule Setlistify.Tidal.API do
  @moduledoc """
  Interface module for Tidal API operations.

  Implements the provider-agnostic `Setlistify.MusicService.API` behaviour and
  adds the Tidal-specific OAuth surface (`exchange_code/3` with a PKCE
  verifier, `refresh_token/1`, `refresh_to_user_session/1`).

  There is deliberately no `get_embed/1`: Setlistify-created Tidal playlists
  default to `UNLISTED`, which Tidal's embed player refuses to render, so the
  `/playlists` page links out to tidal.com instead (ADR-004 §4).
  """

  @behaviour Setlistify.MusicService.API

  alias Setlistify.Tidal.UserSession

  require OpenTelemetry.Tracer

  @callback search_for_track(UserSession.t(), String.t(), String.t(), String.t() | nil) ::
              nil | %{track_id: String.t()} | {:error, atom() | {atom(), term()}}
  def search_for_track(user_session, artist, track, cover_artist \\ nil) do
    Setlistify.Cache.fetch(
      :tidal_track_cache,
      {artist, track, cover_artist},
      fn _ -> impl().search_for_track(user_session, artist, track, cover_artist) end
    )
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}}
              | {:error, atom() | {atom(), term()}}
  def create_playlist(user_session, name, description), do: impl().create_playlist(user_session, name, description)

  @callback add_tracks_to_playlist(UserSession.t(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom() | {atom(), term()}}
  def add_tracks_to_playlist(user_session, playlist_id, tracks),
    do: impl().add_tracks_to_playlist(user_session, playlist_id, tracks)

  @doc """
  Exchanges an authorization code (plus the PKCE `code_verifier` generated at
  sign-in) for tokens and builds a `Setlistify.Tidal.UserSession`.
  """
  @callback exchange_code(String.t(), String.t(), String.t()) ::
              {:ok, UserSession.t()} | {:error, atom() | {atom(), term()}}
  def exchange_code(code, redirect_uri, code_verifier) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.exchange_code" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "tidal"},
        {"oauth.grant_type", "authorization_code"},
        {"oauth.redirect_uri", redirect_uri}
      ])

      impl().exchange_code(code, redirect_uri, code_verifier)
    end
  end

  @doc """
  Exchanges a Tidal refresh token for a fresh access token.

  Tidal does not rotate refresh tokens: the response carries only a new
  `access_token` and `expires_in`, so callers preserve the refresh token
  they already hold.
  """
  @callback refresh_token(String.t()) ::
              {:ok, %{access_token: String.t(), expires_in: non_neg_integer()}}
              | {:error, atom()}
  def refresh_token(refresh_token) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "tidal"},
        {"oauth.grant_type", "refresh_token"}
      ])

      impl().refresh_token(refresh_token)
    end
  end

  @doc """
  Rebuilds a full `Setlistify.Tidal.UserSession` from a stored refresh token,
  used when restoring a session from the cookie after the session process has
  gone away.
  """
  @callback refresh_to_user_session(String.t()) ::
              {:ok, UserSession.t()} | {:error, atom() | {atom(), term()}}
  def refresh_to_user_session(refresh_token) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.refresh_to_user_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "tidal"},
        {"oauth.grant_type", "refresh_token"}
      ])

      impl().refresh_to_user_session(refresh_token)
    end
  end

  defp impl do
    Application.get_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.ExternalClient)
  end
end
