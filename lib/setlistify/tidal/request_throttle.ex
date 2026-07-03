defmodule Setlistify.Tidal.RequestThrottle do
  @moduledoc """
  Caps the number of in-flight Tidal HTTP requests.

  Tidal's real-world rate limit (measured in the Phase 0 spike, issue #137) is
  a ~8-request burst followed by ~2-3 sustained requests/sec with a flat
  `Retry-After: 4` on every 429. The LiveView search fan-out fires a request
  per song in a setlist, so a 20-song setlist would blow through the burst
  capacity without coordination.

  This is a small semaphore: `with_slot/2` blocks until one of
  `@max_concurrent` slots is free, runs the function in the caller's process,
  and releases the slot when it returns (or when the caller dies). Calls above
  the cap queue instead of firing-and-429ing. It is scoped to the Tidal
  subtree only — Spotify and Apple Music are not throttled here.

  Emits a `[:setlistify, :music_service, :request_throttle, :acquired]`
  telemetry event with a `queue_time` measurement (milliseconds spent waiting
  for a slot) and `%{music_service: "tidal"}` metadata, so Phase 2 (#146) can
  tell whether the cap is squeezing concurrency too tight.
  """

  use GenServer

  # Sized to stay inside the spike's measured burst capacity (8) with headroom.
  @max_concurrent 4

  @telemetry_event [:setlistify, :music_service, :request_throttle, :acquired]

  def start_link(opts \\ []) do
    {max_concurrent, opts} = Keyword.pop(opts, :max_concurrent, @max_concurrent)
    opts = Keyword.put_new(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, max_concurrent, opts)
  end

  @doc """
  Runs `fun` once an in-flight slot is free, releasing the slot afterwards.

  Blocks (without timeout) until a slot is available. The function runs in the
  caller's process, so concurrency is only limited — never serialized through
  this GenServer.
  """
  def with_slot(server \\ __MODULE__, fun) when is_function(fun, 0) do
    queued_at = System.monotonic_time()
    :ok = GenServer.call(server, :acquire, :infinity)

    queue_time =
      System.convert_time_unit(System.monotonic_time() - queued_at, :native, :millisecond)

    :telemetry.execute(@telemetry_event, %{queue_time: queue_time}, %{music_service: "tidal"})

    try do
      fun.()
    after
      GenServer.cast(server, {:release, self()})
    end
  end

  @impl true
  def init(max_concurrent) do
    {:ok, %{max_concurrent: max_concurrent, holders: %{}, queue: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag} = from, state) do
    if map_size(state.holders) < state.max_concurrent do
      {:reply, :ok, grant(state, pid)}
    else
      {:noreply, %{state | queue: :queue.in({from, pid}, state.queue)}}
    end
  end

  @impl true
  def handle_cast({:release, pid}, state) do
    {:noreply, release(state, pid)}
  end

  # A slot holder (or a queued waiter that was later granted a slot) died
  # without releasing — free its slot so the queue keeps draining.
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, release(state, pid)}
  end

  defp grant(state, pid) do
    ref = Process.monitor(pid)
    %{state | holders: Map.put(state.holders, pid, ref)}
  end

  defp release(state, pid) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {ref, holders} ->
        Process.demonitor(ref, [:flush])
        promote_next(%{state | holders: holders})
    end
  end

  defp promote_next(state) do
    case :queue.out(state.queue) do
      {{:value, {from, pid}}, queue} ->
        GenServer.reply(from, :ok)
        grant(%{state | queue: queue}, pid)

      {:empty, _queue} ->
        state
    end
  end
end
