defmodule SetlistifyWeb.UserAuth do
  use SetlistifyWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  def on_mount(:default, _params, session, socket) do
    case session do
      %{"access_token" => access_token, "account_name" => account_name} ->
        account = %Setlistify.MusicAccount{access_token: access_token, username: account_name}
        {:cont, Phoenix.Component.assign_new(socket, :music_account, fn -> account end)}

      %{} ->
        socket =
          Phoenix.LiveView.attach_hook(
            socket,
            :track_redirect_to,
            :handle_params,
            &track_redirect_to/3
          )

        {:cont, Phoenix.Component.assign(socket, :music_account, nil)}
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
  def auth_user(conn, {username, token}) do
    conn
    |> renew_session()
    |> put_session(:access_token, token)
    |> put_session(:account_name, username)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> redirect(external: get_session(conn, :redirect_to) || url(~p"/"))
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
    IO.puts("UserAuth.log_out_user called")
    
    if live_socket_id = get_session(conn, :live_socket_id) do
      SetlistifyWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    # Clear entire session (including refresh token)
    new_conn = conn |> renew_session()
    
    # Return both the new conn and redirect
    new_conn |> redirect(to: ~p"/")
  end
end
