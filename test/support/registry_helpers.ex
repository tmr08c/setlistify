defmodule Setlistify.Test.RegistryHelpers do
  @moduledoc """
  Helper functions for working with Registry in tests.
  """

  @doc """
  Asserts that a process is registered with the Registry for the given user_id.

  Waits for the process to be registered, retrying up to max_attempts times with
  sleep_ms milliseconds between attempts. If the process is not registered after
  all attempts, the test fails with a helpful error message.

  ## Options

  * `max_attempts` - Maximum number of attempts to find the process (default: 3)
  * `sleep_ms` - Milliseconds to sleep between attempts (default: 1)
  * `fail_on_timeout` - Whether to fail the test if the process is not found (default: true)

  ## Returns

  * The PID of the registered process if found
  * `nil` if not found and fail_on_timeout is false

  ## Examples

  # Assert that a process is registered for "user_123"
  pid = assert_in_registry("user_123")

  # Wait longer with more attempts
  pid = assert_in_registry("user_123", max_attempts: 20, sleep_ms: 100)

  # Don't fail if not found (e.g., when testing process creation)
  pid = assert_in_registry("user_123", fail_on_timeout: false)
  if is_nil(pid), do: handle_not_found()
  """
  def assert_in_registry(user_id, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    sleep_ms = Keyword.get(opts, :sleep_ms, 1)
    fail_on_timeout = Keyword.get(opts, :fail_on_timeout, true)

    # Import ExUnit.Assertions for flunk
    import ExUnit.Assertions, only: [flunk: 1]

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _ ->
      case Registry.lookup(Setlistify.UserSessionRegistry, {:spotify, user_id}) do
        [{pid, _}] ->
          {:halt, pid}

        [] ->
          if attempt < max_attempts do
            Process.sleep(sleep_ms)
            {:cont, nil}
          else
            if fail_on_timeout do
              flunk(
                "Timed out waiting for process to be registered for user_id: #{user_id} after #{max_attempts} attempts"
              )
            else
              {:halt, nil}
            end
          end
      end
    end)
  end

  @doc """
  Refutes that a process is registered with the Registry for the given user_id.

  Waits for the process to be unregistered, retrying up to max_attempts times with
  sleep_ms milliseconds between attempts. If the process is still registered after
  all attempts, the test fails with a helpful error message.

  ## Options

  * `max_attempts` - Maximum number of attempts to check (default: 3)
  * `sleep_ms` - Milliseconds to sleep between attempts (default: 1)
  * `fail_on_timeout` - Whether to fail the test if the process is still found (default: true)

  ## Returns

  * `true` if no process is registered (refutation successful)
  * The PID of the registered process if found and fail_on_timeout is false

  ## Examples

  # Refute that a process is registered for "user_123"
  refute_in_registry("user_123")

  # Wait longer with more attempts
  refute_in_registry("user_123", max_attempts: 20, sleep_ms: 100)

  # Don't fail if still found (e.g., when testing process shutdown)
  result = refute_in_registry("user_123", fail_on_timeout: false)
  if is_pid(result), do: handle_still_exists(result)
  """
  def refute_in_registry(user_id, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    sleep_ms = Keyword.get(opts, :sleep_ms, 1)
    fail_on_timeout = Keyword.get(opts, :fail_on_timeout, true)

    # Import ExUnit.Assertions for flunk
    import ExUnit.Assertions, only: [flunk: 1]

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _ ->
      case Registry.lookup(Setlistify.UserSessionRegistry, {:spotify, user_id}) do
        [] ->
          {:halt, true}

        [{pid, _}] ->
          if attempt < max_attempts do
            Process.sleep(sleep_ms)
            {:cont, nil}
          else
            if fail_on_timeout do
              flunk(
                "Failed refutation: Process is still registered for user_id: #{user_id} after #{max_attempts} attempts"
              )
            else
              {:halt, pid}
            end
          end
      end
    end)
  end

  @doc """
  Generates a unique user ID suitable for tests.

  This helps prevent test interference when running tests in parallel.

  ## Example

  user_id = unique_user_id()
  """
  def unique_user_id, do: "user_#{System.unique_integer([:positive])}"
end
