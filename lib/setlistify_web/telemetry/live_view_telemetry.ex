defmodule SetlistifyWeb.Telemetry.LiveViewTelemetry do
  @moduledoc """
  Creates a new span for LiveView processes since they don't inherit HTTP trace context.
  """

  import Phoenix.LiveView
  require Logger
  require OpenTelemetry.Tracer

  def on_mount(:default, _params, _session, socket) do
    # Since LiveView processes don't naturally inherit trace context,
    # we'll create a new span for each LiveView mount
    if connected?(socket) do
      # For connected LiveView (WebSocket), create a new trace
      OpenTelemetry.Tracer.with_span "liveview.mount" do
        OpenTelemetry.Tracer.set_attributes([
          {"liveview.module", inspect(socket.view)},
          {"liveview.connected", true}
        ])

        Logger.info("LiveView telemetry: Created new span for connected LiveView")
      end
    end

    {:cont, socket}
  end
end
