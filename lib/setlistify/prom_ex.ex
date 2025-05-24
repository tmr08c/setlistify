defmodule Setlistify.PromEx do
  use PromEx, otp_app: :setlistify

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # PromEx built-in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, endpoint: SetlistifyWeb.Endpoint, router: SetlistifyWeb.Router}
      # Add Ecto plugin if you have a Repo
      # {Plugins.Ecto, repos: [Setlistify.Repo]},

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
      {:prom_ex, "phoenix.json"}
      # {:prom_ex, "ecto.json"}
    ]
  end
end
