defmodule Setlistify.Tidal.RequestThrottleTest do
  use ExUnit.Case, async: true

  alias Setlistify.Tidal.RequestThrottle

  # Each test starts its own uniquely-named throttle so tests can run async
  # without touching the globally-named singleton.
  setup context do
    name = Module.concat(__MODULE__, context.test)
    start_supervised!({RequestThrottle, name: name, max_concurrent: 2})
    {:ok, throttle: name}
  end

  defp acquire_and_hold(throttle, test_pid) do
    spawn_link(fn ->
      RequestThrottle.with_slot(throttle, fn ->
        send(test_pid, {:in_slot, self()})

        receive do
          :release -> :ok
        end
      end)
    end)
  end

  test "returns the function's result", %{throttle: throttle} do
    assert RequestThrottle.with_slot(throttle, fn -> {:ok, :result} end) == {:ok, :result}
  end

  test "queues calls above the cap until a slot frees up", %{throttle: throttle} do
    test_pid = self()

    acquire_and_hold(throttle, test_pid)
    acquire_and_hold(throttle, test_pid)

    assert_receive {:in_slot, first}
    assert_receive {:in_slot, _second}

    # Both slots are held — a third call must queue, not run.
    acquire_and_hold(throttle, test_pid)
    refute_receive {:in_slot, _third}, 100

    # Releasing one slot lets the queued call through.
    send(first, :release)
    assert_receive {:in_slot, _third}
  end

  test "releases the slot when the holder crashes", %{throttle: throttle} do
    test_pid = self()

    holder =
      spawn(fn ->
        RequestThrottle.with_slot(throttle, fn ->
          send(test_pid, {:in_slot, self()})

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive {:in_slot, ^holder}
    acquire_and_hold(throttle, test_pid)
    assert_receive {:in_slot, _second}

    # Both slots held; kill one holder mid-flight and the throttle should
    # recover the slot for the next caller.
    Process.exit(holder, :kill)
    acquire_and_hold(throttle, test_pid)
    assert_receive {:in_slot, _third}
  end

  test "releases the slot when the function raises", %{throttle: throttle} do
    assert_raise RuntimeError, fn ->
      RequestThrottle.with_slot(throttle, fn -> raise "boom" end)
    end

    assert RequestThrottle.with_slot(throttle, fn -> :still_works end) == :still_works
  end

  test "emits a queue-time telemetry event on acquire", %{throttle: throttle} do
    handler_id = {__MODULE__, :telemetry_test}
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:setlistify, :music_service, :request_throttle, :acquired],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    RequestThrottle.with_slot(throttle, fn -> :ok end)

    assert_receive {:telemetry, %{queue_time: queue_time}, %{music_service: "tidal"}}
    assert is_integer(queue_time) and queue_time >= 0
  end
end
