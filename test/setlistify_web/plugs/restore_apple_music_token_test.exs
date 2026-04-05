defmodule SetlistifyWeb.Plugs.RestoreAppleMusicTokenTest do
  use SetlistifyWeb.ConnCase, async: true

  alias SetlistifyWeb.Plugs.RestoreAppleMusicToken
  alias Setlistify.AppleMusic.{SessionManager, UserSession}
  alias Setlistify.Auth.TokenSalts

  @user_token "test_apple_music_user_token"
  @storefront "us"

  setup do
    user_id = unique_user_id()
    {:ok, %{user_id: user_id}}
  end

  describe "call/2" do
    test "does nothing when auth_provider is absent", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert get_session(conn, :user_id) == nil
    end

    test "does nothing when auth_provider is spotify", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "spotify")
        |> put_session(:user_id, user_id)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert get_session(conn, :user_id) == user_id
    end

    test "does nothing when session process already exists", %{conn: conn, user_id: user_id} do
      user_session = %UserSession{
        user_token: @user_token,
        storefront: @storefront,
        user_id: user_id
      }

      {:ok, _pid} = SessionManager.start_link({user_id, user_session})

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "apple_music")
        |> put_session(:user_id, user_id)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
    end

    test "restores session process from valid encrypted user_token", %{
      conn: conn,
      user_id: user_id
    } do
      refute_in_registry({:apple_music, user_id})

      encrypted_token =
        Phoenix.Token.sign(
          SetlistifyWeb.Endpoint,
          TokenSalts.apple_music_user_token(),
          @user_token
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "apple_music")
        |> put_session(:user_id, user_id)
        |> put_session(:user_token, encrypted_token)
        |> put_session(:storefront, @storefront)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil

      {:ok, session} = SessionManager.get_session(user_id)
      assert %UserSession{} = session
      assert session.user_token == @user_token
      assert session.storefront == @storefront
      assert session.user_id == user_id
    end

    test "clears session when user_token is missing", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "apple_music")
        |> put_session(:user_id, user_id)
        |> put_session(:storefront, @storefront)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
      assert get_session(conn, :user_id) == nil
      assert get_session(conn, :storefront) == nil
    end

    test "clears session when user_token is invalid", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "apple_music")
        |> put_session(:user_id, user_id)
        |> put_session(:user_token, "not_a_valid_signed_token")
        |> put_session(:storefront, @storefront)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
      assert get_session(conn, :user_id) == nil
    end

    test "clears session when storefront is missing", %{conn: conn, user_id: user_id} do
      encrypted_token =
        Phoenix.Token.sign(
          SetlistifyWeb.Endpoint,
          TokenSalts.apple_music_user_token(),
          @user_token
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "apple_music")
        |> put_session(:user_id, user_id)
        |> put_session(:user_token, encrypted_token)
        |> RestoreAppleMusicToken.call([])

      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
      assert get_session(conn, :user_id) == nil
    end
  end
end
