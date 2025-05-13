defmodule SetlistifyWeb.Plugs.RestoreSpotifyToken do
  @moduledoc """
  A plug that restores Spotify token processes from encrypted session tokens.
  """
  import Plug.Conn
  require Logger

  alias Setlistify.Spotify.{TokenSupervisor, TokenManager, API}

  def init(opts), do: opts

  def call(conn, _opts) do
    with %{"username" => username} <- get_session(conn, "user"),
         {:error, :not_found} <- TokenManager.get_token(username),
         encrypted_token when not is_nil(encrypted_token) <- get_session(conn, :refresh_token),
         {:ok, refresh_token} <-
           Phoenix.Token.verify(SetlistifyWeb.Endpoint, "user auth", encrypted_token,
             max_age: 86400 * 30
           ) do
      # Attempt to refresh the token and start a new process
      case API.refresh_token(refresh_token) do
        {:ok, tokens} ->
          {:ok, _pid} = TokenSupervisor.start_user_token(username, tokens)
          conn

        {:error, _reason} ->
          # If refresh fails, clear the session
          conn
          |> clear_session()
          |> Phoenix.Controller.put_flash(
            :error,
            "Your Spotify session has expired. Please log in again."
          )
          |> Phoenix.Controller.redirect(to: "/")
          |> halt()
      end
    else
      nil -> conn
      {:error, _} -> conn
      _ -> conn
    end
  end
end
