defmodule SetlistifyWeb.SpotifyCallbackController do
  use SetlistifyWeb, :controller

  def show(conn, %{"code" => code, "state" => _todo}) do
    auth =
      :base64.encode(
        Application.fetch_env!(:setlistify, :spotify_client_id) <>
          ":" <> Application.fetch_env!(:setlistify, :spotify_client_secret)
      )

    resp =
      Req.new(
        url: "https://accounts.spotify.com/api/token",
        headers: %{authorization: "Basic #{auth}"}
      )
      |> Req.post!(
        form: %{
          grant_type: :authorization_code,
          code: code,
          redirect_uri: url(~p"/spotifyauthcallback")
        }
      )
      |> dbg()

    %{"access_token" => token} = resp.body

    conn = assign(conn, :access_token, token)

    conn |> redirect(to: "/")
  end
end
