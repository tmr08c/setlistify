defmodule Setlistify.Auth.TokenSaltsTest do
  use ExUnit.Case, async: true

  alias Setlistify.Auth.TokenSalts

  describe "tidal_refresh_token/0" do
    test "returns the Tidal refresh token salt" do
      assert TokenSalts.tidal_refresh_token() == "tidal refresh token"
    end

    test "is distinct from the other providers' salts" do
      salts = [
        TokenSalts.spotify_refresh_token(),
        TokenSalts.apple_music_user_token(),
        TokenSalts.tidal_refresh_token()
      ]

      assert salts == Enum.uniq(salts)
    end
  end
end
