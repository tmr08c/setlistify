defmodule Setlistify.AppleMusic.UserSessionTest do
  use ExUnit.Case, async: true

  alias Setlistify.AppleMusic.UserSession

  test "creates a valid user session with required fields" do
    user_id = Ecto.UUID.generate()

    session = %UserSession{
      user_token: "test_user_token",
      user_id: user_id,
      storefront: "us"
    }

    assert session.user_token == "test_user_token"
    assert session.user_id == user_id
    assert session.storefront == "us"
  end

  test "enforces required keys" do
    complete_session_map = %{
      user_token: "test_user_token",
      user_id: Ecto.UUID.generate(),
      storefront: "us"
    }

    for key <- Map.keys(complete_session_map) do
      session_with_missing_key = Map.delete(complete_session_map, key)

      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(UserSession, session_with_missing_key)
      end
    end
  end
end
