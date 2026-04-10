defmodule Setlistify.UserSessionManager do
  @moduledoc """
  Provider-agnostic dispatch layer for user session management.

  Two dispatch patterns are used depending on whether the caller has the
  session in hand:

  - Session struct — used at session creation time, when the full
    `UserSession` struct is available. Dispatch is by struct type, so no
    provider argument is needed.

  - Provider key tuple — used for lookups and teardown, when the session
    hasn't been fetched yet and only the provider + user ID are known (e.g.
    from a session cookie). The tuple mirrors the Registry key format used
    internally.

    Provider key format: `{:provider, user_id}`
  """

  alias Setlistify.AppleMusic
  alias Setlistify.Spotify

  @type provider_key :: {:spotify, String.t()} | {:apple_music, String.t()}
  @type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t()

  @callback start_link({String.t(), user_session()}) :: GenServer.on_start()
  @callback get_session(String.t()) :: {:ok, user_session()} | {:error, :not_found}
  @callback stop(String.t()) :: :ok | {:error, :not_found}

  defp impl(%Spotify.UserSession{}), do: Spotify.SessionManager
  defp impl(%AppleMusic.UserSession{}), do: AppleMusic.SessionManager
  defp impl({:spotify, _}), do: Spotify.SessionManager
  defp impl({:apple_music, _}), do: AppleMusic.SessionManager

  def start(%_{user_id: uid} = session), do: impl(session).start_link({uid, session})
  def get_session({_, uid} = key), do: impl(key).get_session(uid)
  def stop({_, uid} = key), do: impl(key).stop(uid)
end
