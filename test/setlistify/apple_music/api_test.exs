defmodule Setlistify.AppleMusic.APITest do
  use Setlistify.DataCase, async: true

  alias Setlistify.AppleMusic.API
  alias Setlistify.AppleMusic.UserSession

  describe "build_user_session/3" do
    test "returns a UserSession struct with the given fields" do
      assert {:ok, %UserSession{} = session} =
               API.build_user_session("user_token", "us", "user-id-123")

      assert session.user_token == "user_token"
      assert session.storefront == "us"
      assert session.user_id == "user-id-123"
    end
  end
end
