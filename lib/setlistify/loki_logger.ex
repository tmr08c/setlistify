defmodule Setlistify.LokiLogger do
  @moduledoc """
  A simple Logger backend for Grafana Loki.
  Sends logs directly to Loki's HTTP API without external dependencies.
  """

  @behaviour :gen_event

  defstruct [
    :url,
    :labels,
    :level,
    :metadata,
    :max_buffer,
    :auth_header,
    buffer: [],
    buffer_size: 0,
    timer_ref: nil
  ]

  @default_url "http://localhost:3100/loki/api/v1/push"
  @default_max_buffer 100
  # 1 second
  @flush_interval 1000

  # Init callbacks
  def init(__MODULE__), do: init({__MODULE__, []})

  def init({__MODULE__, opts}) do
    config = configure([], opts)
    schedule_flush()
    {:ok, config}
  end

  # Handle configuration updates
  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(state, opts)}
  end

  # Handle log events
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    %{level: min_level} = state

    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      {:ok, buffer_event(level, msg, ts, md, state)}
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
    {:ok, flush(state)}
  end

  def handle_event(_, state), do: {:ok, state}

  # Handle timer-based flushing
  def handle_info(:flush, state) do
    schedule_flush()
    {:ok, flush(state)}
  end

  def handle_info(_, state), do: {:ok, state}

  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  def terminate(_reason, state) do
    flush(state)
    :ok
  end

  # Private functions
  defp configure(state, opts) do
    config =
      Keyword.merge(
        Application.get_env(:logger, __MODULE__, []),
        opts
      )

    url = Keyword.get(config, :url, @default_url)
    labels = Keyword.get(config, :labels, %{})
    level = Keyword.get(config, :level)
    metadata = Keyword.get(config, :metadata, [])
    max_buffer = Keyword.get(config, :max_buffer, @default_max_buffer)

    # For Grafana Cloud authentication
    username = Keyword.get(config, :username)
    password = Keyword.get(config, :password)

    auth_header =
      if username && password do
        {"Authorization", "Basic " <> Base.encode64("#{username}:#{password}")}
      else
        nil
      end

    # Handle both initial state (empty list) and existing state (struct)
    {buffer, buffer_size} =
      case state do
        %__MODULE__{buffer: b, buffer_size: s} -> {b, s}
        _ -> {[], 0}
      end

    struct!(
      __MODULE__,
      url: url,
      labels: labels,
      level: level,
      metadata: metadata,
      max_buffer: max_buffer,
      auth_header: auth_header,
      buffer: buffer,
      buffer_size: buffer_size
    )
  end

  defp buffer_event(level, msg, timestamp, metadata, state) do
    entry = format_entry(level, msg, timestamp, metadata, state)
    new_buffer = [entry | state.buffer]
    new_size = state.buffer_size + 1

    if new_size >= state.max_buffer do
      flush(%{state | buffer: new_buffer, buffer_size: new_size})
    else
      %{state | buffer: new_buffer, buffer_size: new_size}
    end
  end

  defp format_entry(level, msg, _timestamp, metadata, state) do
    # Take only requested metadata
    filtered_metadata = take_metadata(metadata, state.metadata)

    # Format timestamp as nanoseconds
    # Logger timestamps are in local time, so we need to use System.system_time
    # to get the current timestamp in nanoseconds
    unix_nano = System.system_time(:nanosecond) |> to_string()

    # Format the log message
    message = IO.iodata_to_binary(msg)

    # Build labels including metadata that should be indexed
    labels =
      Map.merge(state.labels, %{
        "level" => to_string(level)
      })

    # Add trace context if available
    labels =
      case Keyword.get(filtered_metadata, :trace_id) do
        nil -> labels
        trace_id -> Map.put(labels, "trace_id", to_string(trace_id))
      end

    labels =
      case Keyword.get(filtered_metadata, :span_id) do
        nil -> labels
        span_id -> Map.put(labels, "span_id", to_string(span_id))
      end

    # Build the log line with metadata
    log_line =
      if filtered_metadata == [] do
        message
      else
        metadata_str =
          filtered_metadata
          |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
          |> Enum.join(" ")

        "#{message} #{metadata_str}"
      end

    {labels, unix_nano, log_line}
  end

  defp take_metadata(metadata, :all), do: metadata

  defp take_metadata(metadata, keys) when is_list(keys) do
    Enum.filter(metadata, fn {k, _} -> k in keys end)
  end

  defp flush(%{buffer: []} = state), do: state

  defp flush(%{buffer: buffer} = state) do
    # Group by labels
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

    # Send async to not block logger
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

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
