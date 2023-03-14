defmodule Setlistify.MusicAccount do
  @moduledoc """
  Reprsentation of user-accounts for music streaming services.

  Currently, we only support Spotify.
  """
  @type t() :: %__MODULE__{username: :string, access_token: :string}

  @enforce_keys [:username, :access_token]
  defstruct username: :string, access_token: :string
end
