defmodule Setlistify.Scope do
  @moduledoc """
  Centralises request-scoped context for authenticated users.

  Populated from the session during `on_mount` and threaded through context
  functions to carry the current user's provider-specific session struct.

  Following the Phoenix 1.8 scopes convention so future cross-cutting context
  (permissions, feature flags, multi-provider metadata) has a natural home.
  """

  alias Setlistify.AppleMusic
  alias Setlistify.Spotify

  @type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t()

  @type t :: %__MODULE__{
          user_session: user_session() | nil
        }

  defstruct user_session: nil

  @doc """
  Builds a scope for an authenticated user session.

  Returns a populated `%Scope{}`. Callers with no active session should use
  `for_user_session(nil)` which returns a blank scope.
  """
  @spec for_user_session(user_session() | nil) :: t()
  def for_user_session(nil), do: %__MODULE__{}
  def for_user_session(%_{} = user_session), do: %__MODULE__{user_session: user_session}

  @doc """
  Returns true if the scope belongs to an authenticated user.

  Defined as a guard so it can be used in function heads, `case`/`cond`
  expressions, and HEEx templates alike.
  """
  defguard authenticated?(scope)
           when is_struct(scope, __MODULE__) and not is_nil(scope.user_session)
end
