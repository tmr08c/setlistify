defmodule Setlistify.LokiLogger do
  @moduledoc """
  An Erlang `:logger` handler for Grafana Loki.

  Sends logs to Loki's HTTP API. The handler's `log/2` callback sends
  messages to a dedicated `GenServer` process that buffers entries and
  flushes them on a timer or when the buffer is full.

  ## Configuration

  Configuration is passed via `:logger.add_handler/3` in the `:config` key:

      :logger.add_handler(:loki, Setlistify.LokiLogger, %{
        config: %{
          url: "http://localhost:3100/loki/api/v1/push",
          level: :info,
          metadata: [:request_id, :trace_id, :span_id],
          max_buffer: 100,
          labels: %{"application" => "setlistify"},
          username: "user_id",
          password: "api_key"
        }
      })
  """

  use GenServer

  @default_url "http://localhost:3100/loki/api/v1/push"
  @default_max_buffer 100
  @flush_interval 1000

  # -- Erlang :logger handler callbacks --

  @doc false
  def adding_handler(%{config: config} = handler_config) do
    auth_header = build_auth_header(config)

    state = %{
      url: Map.get(config, :url, @default_url),
      labels: Map.get(config, :labels, %{}),
      level: Map.get(config, :level),
      metadata: Map.get(config, :metadata, []),
      max_buffer: Map.get(config, :max_buffer, @default_max_buffer),
      auth_header: auth_header,
      buffer: [],
      buffer_size: 0,
      timer_ref: nil
    }

    case GenServer.start_link(__MODULE__, state, name: __MODULE__) do
      {:ok, pid} ->
        {:ok, Map.put(handler_config, :config, Map.put(config, :pid, pid))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def adding_handler(handler_config) do
    adding_handler(Map.put(handler_config, :config, %{}))
  end

  @doc false
  def removing_handler(%{config: %{pid: pid}}) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  def removing_handler(_config), do: :ok

  @doc false
  def changing_config(:set, _old_config, new_config) do
    {:ok, new_config}
  end

  def changing_config(:update, old_config, new_config) do
    {:ok, Map.merge(old_config, new_config)}
  end

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, %{config: config}) do
    min_level = Map.get(config, :level)

    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      pid = Map.get(config, :pid)

      if pid && Process.alive?(pid) do
        GenServer.cast(pid, {:log, level, msg, meta})
      end
    end

    :ok
  end

  def log(_event, _config), do: :ok

  # -- GenServer callbacks --

  @impl GenServer
  def init(state) do
    timer_ref = schedule_flush()
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl GenServer
  def handle_cast({:log, level, msg, meta}, state) do
    {:noreply, buffer_event(level, msg, meta, state)}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    timer_ref = schedule_flush()
    {:noreply, flush(%{state | timer_ref: timer_ref})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    flush(state)
    :ok
  end

  defp buffer_event(level, msg, meta, state) do
    entry = format_entry(level, msg, meta, state)
    new_buffer = [entry | state.buffer]
    new_size = state.buffer_size + 1

    if new_size >= state.max_buffer do
      flush(%{state | buffer: new_buffer, buffer_size: new_size})
    else
      %{state | buffer: new_buffer, buffer_size: new_size}
    end
  end

  defp format_entry(level, msg, meta, state) do
    filtered_metadata = take_metadata(meta, state.metadata)
    unix_nano = :nanosecond |> System.system_time() |> to_string()
    message = format_message(msg)

    labels = Map.put(state.labels, "level", to_string(level))

    labels =
      case Map.get(filtered_metadata, :trace_id) do
        nil -> labels
        trace_id -> Map.put(labels, "trace_id", to_string(trace_id))
      end

    labels =
      case Map.get(filtered_metadata, :span_id) do
        nil -> labels
        span_id -> Map.put(labels, "span_id", to_string(span_id))
      end

    log_line =
      if filtered_metadata == %{} do
        message
      else
        metadata_str =
          Enum.map_join(filtered_metadata, " ", fn {k, v} -> "#{k}=#{inspect(v)}" end)

        "#{message} #{metadata_str}"
      end

    {labels, unix_nano, log_line}
  end

  defp format_message({:string, msg}), do: IO.iodata_to_binary(msg)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, args}) when is_list(args) do
    format |> :io_lib.format(args) |> IO.iodata_to_binary()
  end

  defp format_message(other), do: inspect(other)

  defp take_metadata(meta, :all), do: meta

  defp take_metadata(meta, keys) when is_list(keys) do
    Map.take(meta, keys)
  end

  defp take_metadata(_meta, _), do: %{}

  defp flush(%{buffer: []} = state), do: state

  defp flush(%{buffer: buffer} = state) do
    streams =
      buffer
      |> Enum.reverse()
      |> Enum.group_by(&elem(&1, 0), fn {_, ts, msg} -> [ts, msg] end)
      |> Enum.map(fn {labels, values} ->
        %{
          "stream" => labels,
          "values" => values
        }
      end)

    payload = %{"streams" => streams}

    Task.start(fn ->
      send_to_loki(state.url, payload, state.auth_header)
    end)

    %{state | buffer: [], buffer_size: 0}
  end

  defp send_to_loki(url, payload, auth_header) do
    headers = [{"content-type", "application/json"}]
    headers = if auth_header, do: [auth_header | headers], else: headers

    body = Jason.encode!(payload)

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        IO.puts(
          :stderr,
          "[LokiLogger] Failed to send logs. Status: #{status}, Body: #{inspect(body)}"
        )

      {:error, reason} ->
        IO.puts(:stderr, "[LokiLogger] Failed to send logs: #{inspect(reason)}")
    end
  rescue
    error ->
      IO.puts(:stderr, "[LokiLogger] Error sending logs: #{inspect(error)}")
  end

  defp build_auth_header(%{username: username, password: password}) when is_binary(username) and is_binary(password) do
    {"Authorization", "Basic " <> Base.encode64("#{username}:#{password}")}
  end

  defp build_auth_header(_), do: nil

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
