defmodule SetlistifyWeb.TokenRefreshConsumerLive do
  @moduledoc """
  A minimal test-only LiveView used to exercise the `{:token_refreshed, _}`
  `handle_info/2` clause injected into every LiveView by `SetlistifyWeb.live_view/0`.

  It stands in for "any real LiveView" by reading the session straight out of
  `@current_scope` — the same assign every real consumer reads — and rendering
  the access token so a token refresh becomes observable.
  """
  use SetlistifyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    # layout: false — skip Layouts.app, which needs assigns LiveHooks would supply.
    # We are isolating the injected handle_info, not the layout.
    {:ok, assign(socket, :current_scope, Setlistify.Scope.for_user_session(session["user_session"])), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="access-token">{access_token(@current_scope)}</div>
    """
  end

  defp access_token(%{user_session: %{access_token: token}}), do: token
  defp access_token(_), do: "none"
end
