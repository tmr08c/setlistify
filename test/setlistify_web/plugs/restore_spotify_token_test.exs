defmodule SetlistifyWeb.Plugs.RestoreSpotifyTokenTest do
  use SetlistifyWeb.ConnCase, async: true
  alias SetlistifyWeb.Plugs.RestoreSpotifyToken
  alias Setlistify.Spotify.TokenManager

  @username "test_user"
  @refresh_token "test_refresh_token"

  setup do
    start_supervised!({Registry, keys: :unique, name: Setlistify.UserTokenRegistry})
    start_supervised!({DynamicSupervisor, name: Setlistify.UserTokenSupervisor})
    :ok
  end

  describe "call/2" do
    test "does nothing when no user in session", %{conn: conn} do
      conn = RestoreSpotifyToken.call(conn, [])
      refute conn.halted
    end

    test "does nothing when token process exists", %{conn: conn} do
      tokens = %{access_token: "test_token", refresh_token: @refresh_token, expires_in: 3600}
      {:ok, _pid} = TokenManager.start_link({@username, tokens})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("user", %{"username" => @username})
        |> RestoreSpotifyToken.call([])

      refute conn.halted
    end

    test "restores token process from valid refresh token", %{conn: conn} do
      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # TODO Change to be a mock of Spotify.ExternalClient
      # Mock successful token refresh
      expect(Req, :post, fn "https://accounts.spotify.com/api/token", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "new_token",
             "expires_in" => 3600
           }
         }}
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("user", %{"username" => @username})
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      refute conn.halted
      assert {:ok, "new_token"} = TokenManager.get_token(@username)
    end

    test "redirects and clears session on refresh failure", %{conn: conn} do
      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # Mock failed token refresh
      expect(Req, :post, fn "https://accounts.spotify.com/api/token", _opts ->
        {:ok, %{status: 401}}
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("user", %{"username" => @username})
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      assert conn.halted
      assert get_flash(conn, :error) =~ "session has expired"
      assert redirected_to(conn) == "/"
      assert {:error, :not_found} = TokenManager.get_token(@username)
    end
  end

  # Helper function to set up mocks
  defp expect(module, function, times, callback) do
    :ok = Application.put_env(:setlistify, :spotify_client_id, "test_client_id")
    :ok = Application.put_env(:setlistify, :spotify_client_secret, "test_client_secret")
    Mox.expect(module, function, times, callback)
  end
end
