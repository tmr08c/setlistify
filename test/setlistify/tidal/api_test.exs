defmodule Setlistify.Tidal.APITest do
  use ExUnit.Case, async: true

  import Hammox

  alias Setlistify.Tidal.API
  alias Setlistify.Tidal.API.MockClient

  setup :verify_on_exit!

  describe "refresh_token/1" do
    test "delegates to the impl and returns the result" do
      expect(MockClient, :refresh_token, 1, fn "refresh-abc" ->
        {:ok, %{access_token: "new-access", expires_in: 14_400}}
      end)

      assert {:ok, %{access_token: "new-access", expires_in: 14_400}} =
               API.refresh_token("refresh-abc")
    end

    test "returns the error when impl returns an error" do
      expect(MockClient, :refresh_token, 1, fn _refresh_token ->
        {:error, :invalid_token}
      end)

      assert {:error, :invalid_token} = API.refresh_token("bad-token")
    end
  end
end
