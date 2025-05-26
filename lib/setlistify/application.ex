defmodule Setlistify.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Cachex.Spec

  @impl true
  def start(_type, _args) do
    Setlistify.Observability.setup()

    children =
      [
        # Start the Telemetry supervisor
        SetlistifyWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: Setlistify.PubSub},
        # Start Finch
        {Finch, name: Setlistify.Finch},
        # Start the Endpoint (http/https)
        SetlistifyWeb.Endpoint,
        # Start the Registry for user session processes
        {Registry, keys: :unique, name: Setlistify.UserSessionRegistry},
        # Start the DynamicSupervisor for user session processes
        {DynamicSupervisor, name: Setlistify.UserSessionSupervisor},
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
      |> maybe_add_prom_ex()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Setlistify.Supervisor]

    # Start the supervisor
    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        # Initialize OpenTelemetry after supervisor starts
        result

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SetlistifyWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_prom_ex(children) do
    if Application.get_env(:setlistify, Setlistify.PromEx)[:disabled] do
      children
    else
      # Add PromEx after Telemetry
      List.insert_at(children, 1, Setlistify.PromEx)
    end
  end
end
