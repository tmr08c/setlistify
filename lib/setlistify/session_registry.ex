defmodule Setlistify.SessionRegistry do
  @moduledoc """
  Shared registry helpers for provider session managers.

  Both `Spotify.SessionManager` and `AppleMusic.SessionManager` register
  processes in `Setlistify.UserSessionRegistry` under a `{provider, user_id}`
  key. This module centralises the `via_tuple` and `lookup` logic so each
  provider doesn't duplicate it.
  """

  @registry Setlistify.UserSessionRegistry

  @doc """
  Returns a `:via` tuple for registering or naming a process.

  ## Examples

      iex> Setlistify.SessionRegistry.via_tuple(:spotify, "user_1")
      {:via, Registry, {Setlistify.UserSessionRegistry, {:spotify, "user_1"}}}
  """
  @spec via_tuple(atom(), binary()) :: {:via, Registry, {module(), {atom(), binary()}}}
  def via_tuple(provider, user_id) do
    {:via, Registry, {@registry, {provider, user_id}}}
  end

  @doc """
  Looks up a session manager process by provider and user ID.

  Returns `{:ok, pid}` if found, `:error` otherwise.

  ## Examples

      iex> Setlistify.SessionRegistry.lookup(:spotify, "nonexistent")
      :error
  """
  @spec lookup(atom(), binary()) :: {:ok, pid()} | :error
  def lookup(provider, user_id) do
    case Registry.lookup(@registry, {provider, user_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
