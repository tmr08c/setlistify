defmodule SetlistifyWeb.UserAuth do
  @moduledoc """
  Authentication functions for regular HTTP controllers and plug pipeline.

  For LiveView authentication hooks, see SetlistifyWeb.Auth.LiveHooks.
  """

  @behaviour Plug

  use SetlistifyWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    require_authenticated_user(conn, opts)
  end

  @doc """
  Used for HTTP routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if get_session(conn, :user_id) do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  # Store the path to redirect to on successful login
  defp store_return_to(conn) do
    put_session(conn, :redirect_to, get_current_path_from_conn(conn))
  end

  defp get_current_path_from_conn(conn) do
    query_string =
      case conn.query_string do
        "" -> ""
        qs -> "?" <> qs
      end

    conn.request_path <> query_string
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
    auth_provider = get_session(conn, :auth_provider)
    user_token = get_session(conn, :user_token)
    storefront = get_session(conn, :storefront)
    redirect_to = get_session(conn, :redirect_to)

    conn
    |> renew_session()
    |> put_session(:user_id, user_id)
    |> put_session(:auth_provider, auth_provider)
    |> put_session(:refresh_token, encrypted_refresh_token)
    |> put_session(:user_token, user_token)
    |> put_session(:storefront, storefront)
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
