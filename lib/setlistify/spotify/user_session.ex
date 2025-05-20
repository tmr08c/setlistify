defmodule Setlistify.Spotify.UserSession do
  @moduledoc """
  Represents an authenticated Spotify user session with tokens and profile data.
  """
  use Setlistify.Trace

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t(),
          expires_at: integer(),
          user_id: String.t(),
          username: String.t()
        }

  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :username]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :username]
end
