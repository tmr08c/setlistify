defmodule SetlistifyWeb.UserAuthTest do
  use SetlistifyWeb.ConnCase, async: false

  alias SetlistifyWeb.UserAuth

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "continues if user is authenticated", %{conn: conn} do
      user_id = "test-user-123"

      conn =
        conn
        |> init_test_session(user_id: user_id)
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "stores the path to redirect to on successful login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:request_path, "/foobar")
        |> Map.put(:query_string, "id=123")
        |> UserAuth.require_authenticated_user([])

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :redirect_to) == "/foobar?id=123"
    end
  end
end
