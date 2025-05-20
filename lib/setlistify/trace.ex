defmodule Setlistify.Trace do
  @moduledoc """
  Provides function decoration for automatic OpenTelemetry tracing.

  This module implements a `trace` macro that can be placed around function
  definitions to automatically wrap them in a telemetry span. The span will
  emit `:start` and `:stop` events that can be handled by telemetry handlers
  including OpenTelemetry.

  ## Usage

      defmodule Setlistify.Spotify.API.ExternalClient do
        use Setlistify.Trace

        trace def search_tracks(token, artist, track) do
          # Function body unchanged
        end
      end

  ## Features

  The `trace` decorator:
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
  """

  # Process that receives test events - used only in tests
  @test_process_name :trace_test_receiver

  defmacro __using__(_opts) do
    quote do
      import Setlistify.Trace, only: [trace: 1]
      Module.register_attribute(__MODULE__, :trace, accumulate: false)
      Module.register_attribute(__MODULE__, :traced_functions, accumulate: true)
      @on_definition {Setlistify.Trace, :on_definition}
      @before_compile Setlistify.Trace
    end
  end
  
  # This callback runs after each function is defined in the module
  def on_definition(env, _kind, fun_name, args, _guards, _body) do
    module = env.module
    trace = Module.get_attribute(module, :trace)
    
    if trace == true do
      # Store this function to be traced
      Module.put_attribute(module, :traced_functions, {fun_name, length(args || [])})
    end
  end
  
  defmacro __before_compile__(env) do
    module = env.module
    traced_functions = Module.get_attribute(module, :traced_functions) || []
    
    if traced_functions == [] do
      quote do
      end
    else
      traced_function_defs = for {fun_name, arity} <- traced_functions do
        args = for i <- 0..(arity - 1), do: {:"arg#{i}", [], nil}
        arg_vars = for i <- 0..(arity - 1), do: Macro.var(:"arg#{i}", nil)
        
        quote do
          # Override the original function to add tracing
          defoverridable [{unquote(fun_name), unquote(arity)}]
          
          def unquote(fun_name)(unquote_splicing(args)) do
            # Get short module name for event naming
            short_module = 
              __MODULE__
              |> Module.split()
              |> List.last()
              |> Macro.underscore()
              |> String.to_atom()

            # Create event name as [short_module, function_name]
            event_prefix = [short_module, unquote(fun_name)]
            
            # Prepare args map
            args_map = Enum.with_index([unquote_splicing(arg_vars)])
              |> Enum.map(fn {arg, idx} -> {:"arg_#{idx}", arg} end)
              |> Enum.into(%{})
              
            # Prepare metadata with module, function, args
            metadata = %{
              module: __MODULE__,
              function: unquote(fun_name),
              args: args_map
            }

            # Execute function within telemetry span
            :telemetry.span(event_prefix, metadata, fn ->
              # Call the original function
              result = super(unquote_splicing(arg_vars))
              
              # Return the result with enhanced metadata
              {result, Map.put(metadata, :result, result)}
            end)
          end
        end
      end
      
      quote do
        unquote_splicing(traced_function_defs)
      end
    end
  end
  
  @doc """
  Trace decorator that wraps functions with telemetry spans.
  
  Used as a macro directly preceding function definitions:
  
      defmodule MyModule do
        use Setlistify.Trace
        
        trace def my_function(arg1, arg2) do
          # Function body
        end
      end
  """
  defmacro trace({func_type, meta, [head | body]}) when func_type in [:def, :defp] do
    do_trace(func_type, meta, head, body)
  end
  
  # Helper function that implements the common tracing logic for both def and defp
  defp do_trace(func_type, _meta, head, body) do
    {fun_name, head_meta, args} = head
    
    # Create a new AST node for the function definition
    function_definition = {func_type, [], [{fun_name, head_meta, args}, [do: traced_body(fun_name, args, body[:do])]]}
    
    quote do
      @traced_functions {unquote(fun_name), unquote(length(args || []))}
      unquote(function_definition)
    end
  end
  
  # Generate the traced function body
  defp traced_body(fun_name, args, original_body) do
    quote do
      # Get short module name for event naming
      short_module = 
        __MODULE__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      # Create event name as [short_module, function_name]
      event_prefix = [short_module, unquote(fun_name)]
      
      # Prepare metadata with module, function, args
      args_map = unquote(create_args_map(args))
      metadata = %{
        module: __MODULE__,
        function: unquote(fun_name),
        args: args_map
      }

      # Execute function within telemetry span
      :telemetry.span(event_prefix, metadata, fn ->
        # Execute the original function body
        result = unquote(original_body)
        
        # Return the result with enhanced metadata
        {result, Map.put(metadata, :result, result)}
      end)
    end
  end
  
  # Helper to create a map of argument values at compile time
  defp create_args_map(args) do
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
end