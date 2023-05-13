defmodule Setlistify.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Cachex.Spec

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      SetlistifyWeb.Telemetry,
      # Start the Ecto repository
      Setlistify.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Setlistify.PubSub},
      # Start Finch
      {Finch, name: Setlistify.Finch},
      # Start the Endpoint (http/https)
      SetlistifyWeb.Endpoint,
      # Start Caches
      Supervisor.child_spec(
        {Cachex,
         name: :setlist_fm_search_cache,
         expiration: Cachex.Spec.expiration(default: :timer.minutes(5))},
        id: :setlist_fm_search_cache
      ),
      Supervisor.child_spec(
        {Cachex,
         name: :setlist_fm_setlist_cache,
         expiration: Cachex.Spec.expiration(default: :timer.minutes(5))},
        id: :setlist_fm_setlist_cache
      ),
      Supervisor.child_spec(
        {Cachex,
         name: :spotify_track_cache,
         expiration: Cachex.Spec.expiration(default: :timer.minutes(5))},
        id: :spotify_track_cache
      )
      # Start a worker by calling: Setlistify.Worker.start_link(arg)
      # {Setlistify.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Setlistify.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SetlistifyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
