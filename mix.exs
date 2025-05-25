defmodule Setlistify.MixProject do
  use Mix.Project

  def project do
    [
      app: :setlistify,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      docs: [
        main: "readme",
        extras: ["README.md"],
        before_closing_head_tag: &before_closing_head_tag/1,
        mermaid: true
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Setlistify.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:dotenv_parser, "~> 2.0", only: [:dev, :test]},
      {:cachex, "~> 3.6.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.5", runtime: Mix.env() == :dev},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:finch, "~> 0.13"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.20"},
      {:hammox, "~> 0.7", only: :test},
      {:heroicons, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:phoenix, "~> 1.7.0-rc.2", override: true},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_dashboard, "~> 0.8.5"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:plug_cowboy, "~> 2.5"},
      {:req, "~> 0.3"},
      {:tailwind, "~> 0.3.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:prom_ex, "~> 1.9"},

      # OpenTelemetry
      {:opentelemetry_exporter, "~> 1.6.0"},
      {:opentelemetry, "~> 1.3.0"},
      {:opentelemetry_api, "~> 1.2.0"},

      # Framework Integrations
      {:opentelemetry_phoenix, "~> 1.1.0"},
      {:opentelemetry_telemetry, "~> 1.0.0"},

      # Telemetry
      {:telemetry, "~> 1.2.1"},

      # Logging - enabled in Phase 2
      {:opentelemetry_logger_metadata, "~> 0.2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.deploy": ["tailwind setlistify --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  # Add Mermaid support to the generated documentation
  defp before_closing_head_tag(:html) do
    """
    <script type="module">
      import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
      mermaid.initialize({
        startOnLoad: true,
        theme: 'default',
        themeVariables: {
          primaryColor: '#BB2528',
          primaryTextColor: '#fff',
          primaryBorderColor: '#7C0000',
          lineColor: '#F8B229',
          secondaryColor: '#006100',
          tertiaryColor: '#fff'
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(_), do: ""
end
