defmodule Setlistify.Tidal.API do
  @moduledoc """
  Dispatch surface for Tidal token operations.

  Only the token-refresh seam needed by `Setlistify.Tidal.SessionManager` is
  defined here. The full music-service surface — `search_for_track/4`,
  `create_playlist/3`, `add_tracks_to_playlist/3`, OAuth `exchange_code/3` and
  the `Setlistify.MusicService.API` behaviour — lands with the
  `Setlistify.Tidal.API.ExternalClient` HTTP implementation in #140.
  """

  require OpenTelemetry.Tracer

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

  defp impl do
    Application.get_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.ExternalClient)
  end
end
