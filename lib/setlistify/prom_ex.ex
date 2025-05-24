defmodule Setlistify.PromEx do
  use PromEx, otp_app: :setlistify

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # PromEx built-in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, endpoint: SetlistifyWeb.Endpoint, router: SetlistifyWeb.Router},
      {Plugins.PhoenixLiveView, router: SetlistifyWeb.Router},
      {Plugins.PlugCowboy, routers: [SetlistifyWeb.Router]},
      {Plugins.PlugRouter,
       routers: [SetlistifyWeb.Router], event_prefix: [:phoenix, :router_dispatch]}

      # Add your own custom plugins here
      # Setlistify.PromEx.Plugins.CustomPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built-in Grafana dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "phoenix_live_view.json"},
      {:prom_ex, "plug_cowboy.json"},
      {:prom_ex, "plug_router.json"}
    ]
  end
end
