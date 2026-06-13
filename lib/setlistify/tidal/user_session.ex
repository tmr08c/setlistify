defmodule Setlistify.Tidal.UserSession do
  @moduledoc """
  Represents an authenticated Tidal user session.

  Two ways this differs from `Setlistify.Spotify.UserSession` (per ADR-004 §1):

    * No `:username` — Tidal's `/me` username is just the user's email, which we
      never display. Mirrors `Setlistify.AppleMusic.UserSession`'s no-username
      shape.
    * Carries `:country_code` — required on essentially every Tidal catalog
      request (mirrors Apple Music's `:storefront`). It is derived from the
      access-token JWT at sign-in, not re-fetched on refresh.
  """

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t(),
          expires_at: integer(),
          user_id: String.t(),
          country_code: String.t()
        }

  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :country_code]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :country_code]
end
