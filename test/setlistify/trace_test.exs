defmodule Setlistify.TraceTest do
  use ExUnit.Case, async: true

  describe "@trace decorator" do
    @tag :skip
    test "creates telemetry span for traced function" do
      defmodule TestTraceModule do
        use Setlistify.Trace

        @trace
        def test_function(arg) do
          {:ok, arg}
        end
      end

      # Register our test process to receive events directly
      Setlistify.Trace.set_test_receiver(self())

      # Call the traced function
      TestTraceModule.test_function("test_arg")

      # Verify the telemetry event was emitted
      assert_receive {:telemetry_event, [:test_trace_module, :test_function, :start], metadata}
      assert metadata.module == TestTraceModule
      assert metadata.function == :test_function
      
      # Clean up
      Setlistify.Trace.clear_test_receiver()
    end

    @tag :skip
    test "wraps function with telemetry span" do
      defmodule TestSpanModule do
        use Setlistify.Trace

        @trace
        def span_function(arg1, arg2) do
          {:success, arg1, arg2}
        end
      end

      # Register our test process to receive events directly
      Setlistify.Trace.set_test_receiver(self())

      # Call the traced function
      result = TestSpanModule.span_function("first", "second")
      
      # Verify the result is unchanged
      assert result == {:success, "first", "second"}
      
      # Verify both events were emitted with correct metadata
      assert_receive {:start_event, start_metadata}
      assert start_metadata.module == TestSpanModule
      assert start_metadata.function == :span_function
      
      assert_receive {:stop_event, stop_metadata}
      assert stop_metadata.module == TestSpanModule
      assert stop_metadata.function == :span_function
      
      # Clean up
      Setlistify.Trace.clear_test_receiver()
    end

    @tag :skip
    test "preserves function arity and handles default arguments" do
      defmodule TestArityModule do
        use Setlistify.Trace

        @trace
        def arity_function(required, optional \\ "default") do
          {required, optional}
        end
      end

      # Register our test process to receive events directly
      Setlistify.Trace.set_test_receiver(self())

      # Call with just required arg
      result1 = TestArityModule.arity_function("required")
      assert result1 == {"required", "default"}
      
      # Call with both args
      result2 = TestArityModule.arity_function("required", "custom")
      assert result2 == {"required", "custom"}
      
      # Verify events were captured with args
      assert_receive {:arity_event, metadata1}
      assert metadata1.module == TestArityModule
      assert metadata1.function == :arity_function
      
      # Clean up
      Setlistify.Trace.clear_test_receiver()
    end

    @tag :skip
    test "works with Hammox mocks" do
      defmodule TestAPIBehavior do
        @callback mocked_function(String.t()) :: {:ok, String.t()}
      end

      defmodule TestAPI do
        @behaviour TestAPIBehavior
        use Setlistify.Trace
        
        @trace
        @impl true
        def mocked_function(arg) do
          {:ok, "real: " <> arg}
        end
      end

      # Create a mock
      Hammox.defmock(TestAPIMock, for: TestAPIBehavior)
      
      # Set up mock expectation
      Hammox.expect(TestAPIMock, :mocked_function, fn arg ->
        {:ok, "mock: " <> arg}
      end)
      
      # Call the mock
      result = TestAPIMock.mocked_function("test")
      assert result == {:ok, "mock: test"}
    end
  end
end