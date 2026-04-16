defmodule Setlistify.Scope do
  @moduledoc """
  Centralises request-scoped context for authenticated users.

  Populated from the session during `on_mount` and threaded through context
  functions to carry the current user's identity and provider-specific session
  struct. The `user_id` field is extracted from the session for convenience.
  """

  alias Setlistify.AppleMusic
  alias Setlistify.Spotify

  @type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t()

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          user_session: user_session() | nil
        }

  defstruct user_id: nil, user_session: nil

  @doc """
  Builds a scope for an authenticated user session.

  Returns a populated `%Scope{}`. Callers with no active session should use
  `for_user_session(nil)` which returns a blank scope.
  """
  @spec for_user_session(user_session() | nil) :: t()
  def for_user_session(nil), do: %__MODULE__{}

  def for_user_session(%_{user_id: user_id} = user_session) do
    %__MODULE__{
      user_id: user_id,
      user_session: user_session
    }
  end

  @doc """
  Returns true if the scope belongs to an authenticated user.
  """
  @spec authenticated?(t()) :: boolean()
  def authenticated?(%__MODULE__{user_session: nil}), do: false
  def authenticated?(%__MODULE__{user_session: _}), do: true
end
