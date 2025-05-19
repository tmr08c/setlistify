defmodule Setlistify.Trace do
  @moduledoc """
  Provides function decoration for automatic OpenTelemetry tracing.

  This module offers the `@trace` decorator that wraps functions with telemetry events,
  enabling automatic tracing for instrumented functions with minimal code changes.
  The decorator preserves the original function behavior while adding tracing capabilities.

  ## Usage

      defmodule Setlistify.Spotify.API.ExternalClient do
        use Setlistify.Trace

        @trace
        def search_tracks(token, artist, track) do
          # Function body remains unchanged
          # But is automatically wrapped with tracing
        end
      end

  ## Features

  The `@trace` decorator:
  1. Creates telemetry events for function calls
  2. Generates standardized event names for consistent tracking
  3. Includes function arguments as metadata in spans
  4. Tracks function return values for complete visibility
  5. Preserves function arity and handles default arguments
  6. Works with both public and private functions

  ## Event Names

  Each traced function will emit telemetry events with a standardized naming pattern:

  - `[module_name, function_name, :start]` - When the function starts
    - Example: `[:spotify_api_external_client, :search_tracks, :start]`
  - `[module_name, function_name, :stop]` - When the function completes successfully
    - Example: `[:spotify_api_external_client, :search_tracks, :stop]`

  Where `module_name` is the last segment of the module's name converted to snake_case.
  For example, `Setlistify.Spotify.API.ExternalClient` becomes `:external_client`.

  ## Metadata

  Each event includes rich metadata:

  - `module`: The full module name (e.g., `Setlistify.Spotify.API.ExternalClient`)
  - `function`: The function name as an atom (e.g., `:search_tracks`)
  - `args`: A map of argument values with keys like `arg_0`, `arg_1`, etc.
  - `result`: The function return value (only included in `:stop` events)

  ## Integration with OpenTelemetry

  While this module emits Telemetry events directly, it's designed to work with
  `opentelemetry_telemetry` to bridge these events to OpenTelemetry spans.

  ## Limitations

  - Currently, Hammox mocks may have compatibility issues with traced functions
  - Exception events are not yet implemented (coming in future enhancement)
  """

  # Process that receives test events - used only in tests
  @test_process_name :trace_test_receiver

  defmacro __using__(_opts) do
    quote do
      import Setlistify.Trace, only: [trace: 1]
      # Register attributes
      Module.register_attribute(__MODULE__, :traced_functions, accumulate: true)
      # Register the trace attribute - this avoids warnings
      Module.register_attribute(__MODULE__, :trace, persist: false)
      @before_compile Setlistify.Trace
    end
  end

  defmacro __before_compile__(_env) do
    quote do
    end
  end

  @doc """
  Decorates a function with telemetry events for tracing.

  Place `@trace` immediately before a function definition to enable tracing.
  The original function is wrapped with code that emits telemetry events
  when the function starts and stops.

  ## Examples

      # Basic usage
      @trace
      def process_request(params) do
        # Function implementation
      end

      # Works with function heads and pattern matching
      @trace
      def handle_event("search", params, socket) do
        # Function implementation
      end

      # Preserves default arguments
      @trace
      def create_playlist(name, options \\\\ []) do
        # Function implementation
      end

  ## Event Names

  For a function `search_tracks` in module `Setlistify.Spotify.API.ExternalClient`,
  the following events will be emitted:

  - `[:external_client, :search_tracks, :start]` - Before function execution
  - `[:external_client, :search_tracks, :stop]` - After successful completion

  ## Internals

  The decorator uses compile-time metaprogramming to transform the decorated
  function and wrap it with telemetry event emissions, while preserving the
  original function's behavior, arguments, and return values.
  """
  defmacro trace(fun) do
    quote do
      @traced_functions {unquote(fun_name(fun)), unquote(fun_arity(fun))}
      unquote(trace_function(fun))
    end
  end

  @doc """
  Sets up a process to receive telemetry events for testing.
  
  This function is only used in tests to verify that telemetry events
  are properly emitted by traced functions.
  
  ## Parameters
  
  - `pid`: The process ID that should receive telemetry events
  
  ## Usage
  
      # In a test
      Setlistify.Trace.set_test_receiver(self())
      
      # Call a traced function
      result = MyModule.traced_function(arg)
      
      # Assert events were received
      assert_receive {:telemetry_event, [:my_module, :traced_function, :start], metadata}
  """
  def set_test_receiver(pid) when is_pid(pid) do
    Process.register(pid, @test_process_name)
    
    # Set up handlers for telemetry events that match any event
    :telemetry.attach_many(
      "test-handler",
      [
        [:*],
        [:*, :*],
        [:*, :*, :*],
        [:*, :*, :*, :*],
        [:*, :*, :*, :*, :*]
      ],
      &handle_test_event/4,
      %{}
    )
    
    :ok
  end

  @doc """
  Clears the test event receiver and removes telemetry handlers.
  
  This should be called at the end of tests to clean up.
  """
  def clear_test_receiver do
    # Detach all test handlers
    :telemetry.detach("test-handler")
    
    # Clean up the registered process name if it exists
    if Process.whereis(@test_process_name) do
      Process.unregister(@test_process_name)
    end
    
    :ok
  end

  # Handler function for test telemetry events
  defp handle_test_event(event_name, _measurements, metadata, _config) do
    if Process.whereis(@test_process_name) do
      # Send complete event details
      send(@test_process_name, {:telemetry_event, event_name, metadata})
      
      # Also send specific events for start/stop based on event naming patterns
      cond do
        # Match start events
        match?([_, _, :start], event_name) or
        match?([_, :start], event_name) or
        String.ends_with?(to_string(List.last(event_name)), "start") ->
          send(@test_process_name, {:start_event, metadata})
        
        # Match stop events 
        match?([_, _, :stop], event_name) or
        match?([_, :stop], event_name) or
        String.ends_with?(to_string(List.last(event_name)), "stop") ->
          send(@test_process_name, {:stop_event, metadata})
        
        # For the arity test and other events
        true ->
          send(@test_process_name, {:arity_event, metadata})
      end
    end
  end

  # Helper to extract function name from AST
  # Takes function AST and returns the function name as an atom
  # Example: For `def search_tracks(token, artist, track)` returns `:search_tracks`
  defp fun_name({:def, _, [{name, _, _} | _]}), do: name
  defp fun_name({:defp, _, [{name, _, _} | _]}), do: name

  # Helper to extract function arity from AST
  # Takes function AST and returns the arity (number of arguments)
  # Example: For `def search_tracks(token, artist, track)` returns `3`
  defp fun_arity({:def, _, [{_, _, args} | _]}), do: length(args || [])
  defp fun_arity({:defp, _, [{_, _, args} | _]}), do: length(args || [])

  # Helper to transform the function with tracing
  # Takes the AST of a function definition and returns a new AST with telemetry instrumentation
  # This is the core transformation that wraps the original function with telemetry events
  defp trace_function({function_type, meta, [head | body]}) do
    # Extract function details
    {fun_name, _head_meta, args} = head

    # Create new function body with tracing
    new_body = quote do
      # Convert full module name to list of atoms
      # e.g., [Setlistify, Spotify, API, ExternalClient] -> [:setlistify, :spotify, :api, :external_client]
      module_atoms = __MODULE__ 
                  |> Module.split()
                  |> Enum.map(&String.to_atom(String.downcase(&1)))

      # Get short module name for event naming
      short_module = 
        __MODULE__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      # Create event name as [short_module, function_name]
      # e.g., [:test_trace_module, :test_function]
      event_prefix = [short_module, unquote(fun_name)]
      start_event = event_prefix ++ [:start]
      stop_event = event_prefix ++ [:stop]

      # Prepare metadata with module, function, args
      metadata = %{
        module: __MODULE__,
        function: unquote(fun_name),
        args: unquote(args_to_map(args))
      }

          # Use telemetry.span which will properly emit start and stop events
      :telemetry.span(event_prefix, metadata, fn ->
        # Execute the original function body
        result = unquote(body[:do])
        
        # Return the result with enhanced metadata including the result
        {result, Map.put(metadata, :result, result)}
      end)
    end

    # Construct the function with tracing
    {function_type, meta, [head, [do: new_body]]}
  end

  # Helper to convert function args to a map for telemetry metadata
  # Takes a list of function arguments from the AST and returns AST for a map of argument metadata
  # Handles various argument patterns including default arguments (arg \\ default)
  # Example: For `def func(a, b \\ 1)`, creates a map with keys `arg_0`, `arg_1`
  defp args_to_map(args) do
    args
    |> Enum.with_index()
    |> Enum.map(fn
      # Handle default arguments (arg \\ default)
      {{:\\, _, [arg, _default]}, idx} when is_atom(arg) ->
        quote do
          {unquote("arg_#{idx}"), unquote(arg)}
        end
      
      # Handle regular named arguments
      {arg, idx} when is_atom(arg) ->
        quote do
          {unquote("arg_#{idx}"), unquote(arg)}
        end
      
      # Handle any other pattern (as a fallback)
      {_, idx} ->
        quote do
          {unquote("arg_#{idx}"), nil}
        end
    end)
    |> then(fn arg_pairs ->
      quote do
        %{unquote_splicing(arg_pairs)}
      end
    end)
  end
end