defmodule SetlistifyWeb.UserAuth do
  use SetlistifyWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Setlistify.Spotify.SessionManager

  def on_mount(:default, _params, session, socket) do
    with {:ok, user_id} <- Map.fetch(session, "user_id"),
         {:ok, user_session} <- SessionManager.get_session(user_id) do
      socket =
        socket
        |> Phoenix.Component.assign_new(:user_id, fn -> user_id end)
        |> Phoenix.Component.assign_new(:user_session, fn -> user_session end)
        |> Phoenix.Component.assign(:redirect_to, nil)

      {:cont, socket}
    else
      _ ->
        socket =
          socket
          |> Phoenix.LiveView.attach_hook(
            :track_redirect_to,
            :handle_params,
            &track_redirect_to/3
          )
          |> Phoenix.Component.assign(:user_id, nil)
          |> Phoenix.Component.assign(:user_session, nil)

        {:cont, socket}
    end
  end

  # If the user is not logged in, we want to track the current URL so, if they
  # log in, we can redirect them back to where they came from.
  defp track_redirect_to(_params, uri, socket) do
    {:cont, Phoenix.Component.assign(socket, :redirect_to, uri)}
  end

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def auth_user(conn, user_id) do
    # Get values we need to preserve before clearing session
    encrypted_refresh_token = get_session(conn, :refresh_token)
    redirect_to = get_session(conn, :redirect_to)

    conn
    |> renew_session()
    |> put_session(:user_id, user_id)
    |> put_session(:refresh_token, encrypted_refresh_token)
    |> put_session(:live_socket_id, "users_sessions:#{user_id}")
    |> redirect(external: redirect_to || url(~p"/"))
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn |> configure_session(renew: true) |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      SetlistifyWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn |> renew_session() |> redirect(to: ~p"/")
  end
end
