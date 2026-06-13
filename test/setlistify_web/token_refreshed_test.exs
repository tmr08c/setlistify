defmodule SetlistifyWeb.TokenRefreshedTest do
  @moduledoc """
  Regression test for the `{:token_refreshed, new_session}` handle_info clause
  injected by `SetlistifyWeb.live_view/0`.

  Previously the handler wrote to a top-level `:user_session` assign, but after
  the Scope migration every consumer reads `@current_scope.user_session`. The
  refreshed session landed in a dead assign while the access token used by
  downstream API calls stayed stale.

  These tests drive the handler through a real (isolated) LiveView process via
  `TokenRefreshConsumerLive`, which reads the session from `@current_scope`
  exactly like the real LiveViews do — so a refresh is only "seen" if it lands
  where consumers actually look.
  """

  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Setlistify.Spotify.UserSession
  alias SetlistifyWeb.TokenRefreshConsumerLive

  defp old_session do
    %UserSession{
      user_id: "u1",
      username: "Test User",
      access_token: "old-access-token",
      refresh_token: "refresh",
      expires_at: 0
    }
  end

  test "a refresh is visible to a consumer reading @current_scope", %{conn: conn} do
    old = old_session()
    new = %{old | access_token: "new-access-token"}

    {:ok, view, html} =
      live_isolated(conn, TokenRefreshConsumerLive, session: %{"user_session" => old})

    assert html =~ "old-access-token"

    send(view.pid, {:token_refreshed, new})

    assert render(view) =~ "new-access-token"
    refute render(view) =~ "old-access-token"
  end

  test "a nil refresh clears the session a consumer reads", %{conn: conn} do
    {:ok, view, html} =
      live_isolated(conn, TokenRefreshConsumerLive, session: %{"user_session" => old_session()})

    assert html =~ "old-access-token"

    send(view.pid, {:token_refreshed, nil})

    assert render(view) =~ "none"
    refute render(view) =~ "old-access-token"
  end
end
