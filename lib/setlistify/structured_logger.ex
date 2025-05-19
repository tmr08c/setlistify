defmodule Setlistify.StructuredLogger do
  @moduledoc """
  Provides structured logging with OpenTelemetry trace context.
  """
  
  require Logger
  
  def setup do
    # Add OpenTelemetry Logger metadata handler
    result = :logger.add_handler_filter(:default, :add_trace_context, {&add_trace_context/2, []})
    require Logger
    Logger.info("StructuredLogger setup completed with result: #{inspect(result)}")
    result
  end
  
  @doc """
  Filter function that adds trace context to log metadata.
  """
  def add_trace_context(log_event, _config) do
    # Get current span context
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    
    metadata = case span_ctx do
      :undefined -> 
        %{}
      {:span_ctx, trace_id, span_id, _, _, _, _, _, _} -> 
        # Extract and format trace and span IDs
        %{
          trace_id: format_id(trace_id, 32),
          span_id: format_id(span_id, 16)
        }
    end
    
    # Merge with existing metadata
    updated_meta = Map.merge(log_event.meta || %{}, metadata)
    Map.put(log_event, :meta, updated_meta)
  end
  
  defp format_id(id, padding) do
    # Convert integer ID to hex string
    Integer.to_string(id, 16)
    |> String.downcase()
    |> String.pad_leading(padding, "0")
  end
  
  @doc """
  Log at info level with structured metadata.
  """
  defmacro info(message, metadata \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), unquote(metadata))
    end
  end
  
  @doc """
  Log at error level with structured metadata and automatic exception handling.
  """
  defmacro error(message, metadata \\ []) do
    quote do
      require Logger
      metadata = unquote(metadata)
      
      # If this is in a rescue block, try to extract exception info
      metadata = cond do
        Map.has_key?(metadata, :error) -> metadata
        Process.get(:current_stacktrace) != nil ->
          Map.merge(metadata, %{
            error: Process.get(:current_exception),
            stacktrace: Process.get(:current_stacktrace)
          })
        true -> metadata
      end
      
      Logger.error(unquote(message), metadata)
    end
  end
  
  @doc """
  Log at warning level with structured metadata.
  """
  defmacro warning(message, metadata \\ []) do
    quote do
      require Logger
      Logger.warning(unquote(message), unquote(metadata))
    end
  end
  
  @doc """
  Log at debug level with structured metadata.
  """
  defmacro debug(message, metadata \\ []) do
    quote do
      require Logger
      Logger.debug(unquote(message), unquote(metadata))
    end
  end
end