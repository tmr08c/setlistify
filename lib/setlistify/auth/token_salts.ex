defmodule Setlistify.Auth.TokenSalts do
  @moduledoc """
  Salt constants for Phoenix.Token sign/verify pairs.

  Each salt must be identical at the sign site and the verify site.
  Centralising them here prevents silent mismatches from typos.
  """

  def spotify_refresh_token, do: "user auth"
  def apple_music_user_token, do: "apple music user token"
end
