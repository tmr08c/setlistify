defmodule SetlistifyWeb.OAuthCallbackController do
  use SetlistifyWeb, :controller

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => _todo}) do
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
          redirect_uri: url(~p"/oauth/callbacks/spotify")
        }
      )
      |> dbg()

    %{"access_token" => token} = resp.body

    resp = Req.get!("https://api.spotify.com/v1/me", auth: {:bearer, token}) |> dbg()
    spotify_username = resp.body["display_name"] || resp.body["id"]

    conn
    |> put_session(:access_token, token)
    |> put_session(:account_name, spotify_username)
    |> redirect(to: "/")
  end
end
