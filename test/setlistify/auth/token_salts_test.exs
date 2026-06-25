defmodule Setlistify.Auth.TokenSaltsTest do
  use ExUnit.Case, async: true

  alias Setlistify.Auth.TokenSalts

  test "each provider's refresh-token salt is distinct" do
    salts = [
      TokenSalts.spotify_refresh_token(),
      TokenSalts.apple_music_user_token(),
      TokenSalts.tidal_refresh_token()
    ]

    assert salts == Enum.uniq(salts)
  end
end
