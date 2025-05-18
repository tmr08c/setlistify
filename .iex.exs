# IEx helpers for development

alias Setlistify.Observability

# Helper function to test OpenTelemetry
defmodule OtelTest do
  def trace do
    Observability.test_trace()
  end

  def multiple_traces(count \\ 5) do
    Enum.map(1..count, fn i ->
      Process.sleep(100)
      IO.puts("Sending trace #{i}")
      Observability.test_trace()
    end)
  end
end

IO.puts("OpenTelemetry test helpers loaded. Try:")
IO.puts("  OtelTest.trace()")
IO.puts("  OtelTest.multiple_traces(10)")
IO.puts("")
