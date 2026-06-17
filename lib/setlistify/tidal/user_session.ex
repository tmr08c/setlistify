defmodule Setlistify.Tidal.UserSession do
  @moduledoc """
  Represents an authenticated Tidal user session.

  Carries `:country_code`, which is required on essentially every Tidal catalog
  request. Like `Setlistify.AppleMusic.UserSession`, it has no `:username`
  field.
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
