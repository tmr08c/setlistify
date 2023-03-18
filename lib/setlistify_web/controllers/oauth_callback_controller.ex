defmodule SetlistifyWeb.OAuthCallbackController do
  alias SetlistifyWeb.UserAuth
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

    %{"access_token" => token} = resp.body

    resp = Req.get!("https://api.spotify.com/v1/me", auth: {:bearer, token})
    username = resp.body["display_name"] || resp.body["id"]

    UserAuth.auth_user(conn, {username, token})
  end

  # TODO Move to separate controller
  def sign_in(conn, params) do
    uri =
      "https://accounts.spotify.com/authorize"
      |> URI.new!()
      |> URI.append_query(
        URI.encode_query(%{
          client_id: Application.fetch_env!(:setlistify, :spotify_client_id),
          response_type: "code",
          redirect_uri: url(~p"/oauth/callbacks/spotify"),
          state: "TODO",
          scope: "playlist-modify-private",
          show_dialog: true
        })
      )
      |> URI.to_string()
      |> IO.inspect(label: "redirect URI")

    conn |> maybe_put_redirect_to(params) |> redirect(external: uri)
  end

  defp maybe_put_redirect_to(conn, %{"redirect_to" => to}) when to != "" do
    put_session(conn, :redirect_to, to)
  end

  defp maybe_put_redirect_to(conn, _) do
    conn
  end

  def sign_out(conn, _) do
    UserAuth.log_out_user(conn)
  end
end
