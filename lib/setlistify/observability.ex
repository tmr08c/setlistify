defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """

  require Logger

  def setup do
    # Set up OpenTelemetry handlers for telemetry events
    :ok = :opentelemetry_cowboy.setup()
    :ok = OpentelemetryPhoenix.setup(adapter: :cowboy2)

    Logger.debug("OpenTelemetry initialized for local development")
  end
end
