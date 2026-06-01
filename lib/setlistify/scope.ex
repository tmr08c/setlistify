defmodule Setlistify.Scope do
  @moduledoc """
  Wraps the current user's music-service session for use in LiveView assigns.

  Populated by `SetlistifyWeb.Auth.LiveHooks` as `:current_scope` and used to
  check authentication and reach the provider-specific `user_session` struct.
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

  Defined as a guard so callers can use it in function heads as well as
  ordinary expressions.
  """
  defguard authenticated?(scope)
           when is_struct(scope, __MODULE__) and not is_nil(scope.user_session)
end
