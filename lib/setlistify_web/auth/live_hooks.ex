defmodule SetlistifyWeb.Auth.LiveHooks do
  @moduledoc """
  LiveView authentication hooks for mounting protected views.
  """

  alias Setlistify.Spotify.SessionManager

  def on_mount(:default, _params, session, socket) do
    case fetch_user_session(session) do
      {:ok, user_id, user_session} ->
        assign_authenticated_user(socket, user_id, user_session)

      :error ->
        assign_unauthenticated_user(socket)
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case fetch_user_session(session) do
      {:ok, user_id, user_session} ->
        assign_authenticated_user(socket, user_id, user_session)

      :error ->
        redirect_socket_with_return_to(socket)
    end
  end

  # Helper to fetch user session from the session data
  defp fetch_user_session(session) do
    with {:ok, user_id} <- Map.fetch(session, "user_id"),
         {:ok, user_session} <- SessionManager.get_session(user_id) do
      {:ok, user_id, user_session}
    else
      _ -> :error
    end
  end

  # Helper to assign authenticated user data to socket
  defp assign_authenticated_user(socket, user_id, user_session) do
    # Subscribe to token refresh events for this user
    Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user_id}")

    socket =
      socket
      |> Phoenix.Component.assign_new(:user_id, fn -> user_id end)
      |> Phoenix.Component.assign_new(:user_session, fn -> user_session end)
      |> Phoenix.Component.assign(:redirect_to, nil)

    {:cont, socket}
  end

  # Helper to handle unauthenticated users
  defp assign_unauthenticated_user(socket) do
    # Only attach the hook if we're in a real LiveView context
    socket =
      if Map.has_key?(socket.private, :root_view) do
        socket
        |> Phoenix.LiveView.attach_hook(
          :track_redirect_to,
          :handle_params,
          &track_redirect_to/3
        )
      else
        socket
      end
      |> Phoenix.Component.assign(:user_id, nil)
      |> Phoenix.Component.assign(:user_session, nil)

    {:cont, socket}
  end

  # If the user is not logged in, we want to track the current URL so, if they
  # log in, we can redirect them back to where they came from.
  defp track_redirect_to(_params, uri, socket) do
    {:cont, Phoenix.Component.assign(socket, :redirect_to, uri)}
  end

  defp redirect_socket_with_return_to(socket) do
    # In LiveViews, the current URL is available through socket connect_info
    current_path = get_current_path(socket)

    redirect_url =
      if current_path do
        "/?redirect_to=#{current_path}"
      else
        "/"
      end

    socket =
      socket
      |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
      |> Phoenix.LiveView.push_navigate(to: redirect_url)

    {:halt, socket}
  end

  defp get_current_path(socket) do
    case socket.private[:connect_info] do
      %{request_path: path} -> path
      _ -> nil
    end
  end
end
