defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """

  require Logger

  def setup do
    :ok = :opentelemetry_cowboy.setup()
    :ok = OpentelemetryPhoenix.setup(adapter: :cowboy2)
    :ok = OpentelemetryLoggerMetadata.setup()
  end
end
