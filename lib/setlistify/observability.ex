defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """

  require Logger

  def setup do
    # Ensure OpenTelemetry is started
    case Application.ensure_all_started(:opentelemetry) do
      {:ok, _apps} ->
        Logger.info("✅ OpenTelemetry applications started successfully")
      {:error, {app, reason}} ->
        Logger.error("❌ Failed to start OpenTelemetry app #{app}: #{inspect(reason)}")
    end
    
    # Set up OpenTelemetry handlers for telemetry events
    :ok = :opentelemetry_cowboy.setup()
    :ok = OpentelemetryPhoenix.setup(adapter: :cowboy2)
    
    # Set up logger metadata
    :ok = OpentelemetryLoggerMetadata.setup()

    Logger.info("✅ OpenTelemetry instrumentation initialized")
  end
end
