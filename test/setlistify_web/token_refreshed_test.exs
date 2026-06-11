defmodule SetlistifyWeb.TokenRefreshedTest do
  @moduledoc """
  Regression test for the `{:token_refreshed, new_session}` handle_info clause
  injected by `SetlistifyWeb.live_view/0`.

  Previously the handler wrote to a top-level `:user_session` assign, but after
  the Scope migration every consumer reads `@current_scope.user_session`. The
  refreshed session landed in a dead assign while the access token used by
  downstream API calls stayed stale.
  """

  use SetlistifyWeb.ConnCase, async: true

  alias Phoenix.LiveView.Socket
  alias Setlistify.Scope
  alias Setlistify.Spotify.UserSession
  alias SetlistifyWeb.HomeLive

  test "writes the refreshed session into current_scope" do
    old_session = %UserSession{
      user_id: "u1",
      username: "Test User",
      access_token: "old-access-token",
      refresh_token: "refresh",
      expires_at: 0
    }

    new_session = %{old_session | access_token: "new-access-token"}

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        current_scope: Scope.for_user_session(old_session)
      }
    }

    {:noreply, updated} = HomeLive.handle_info({:token_refreshed, new_session}, socket)

    assert updated.assigns.current_scope.user_session == new_session
    assert updated.assigns.current_scope.user_session.access_token == "new-access-token"
  end

  test "clears current_scope when refreshed session is nil" do
    old_session = %UserSession{
      user_id: "u1",
      username: "Test User",
      access_token: "old",
      refresh_token: "refresh",
      expires_at: 0
    }

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        current_scope: Scope.for_user_session(old_session)
      }
    }

    {:noreply, updated} = HomeLive.handle_info({:token_refreshed, nil}, socket)

    assert updated.assigns.current_scope.user_session == nil
  end
end
