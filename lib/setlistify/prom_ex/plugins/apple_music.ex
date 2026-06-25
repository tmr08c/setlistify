defmodule Setlistify.PromEx.Plugins.AppleMusic do
  @moduledoc """
  PromEx plugin for Apple Music developer token health.

  Surfaces metrics derived from the `[:setlistify, :apple_music, :developer_token, :attempt]`
  event emitted by `Setlistify.AppleMusic.DeveloperTokenManager`:

  - Counter of attempts tagged by `phase` (`:generate | :refresh | :regenerate | :retry`)
    and `outcome` (`:ok | :error`)
  - Gauge that reflects the most recent attempt's health (`1` healthy, `0` degraded)
    so Grafana can alert on sustained degradation
  """

  use PromEx.Plugin

  @event [:setlistify, :apple_music, :developer_token, :attempt]
  @metric_prefix [:setlistify, :apple_music, :developer_token]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :setlistify_apple_music_developer_token_event_metrics,
      [
        counter(
          @metric_prefix ++ [:attempt, :total],
          event_name: @event,
          measurement: :count,
          description: "Total Apple Music developer token attempts by phase and outcome.",
          tags: [:phase, :outcome]
        ),
        last_value(
          @metric_prefix ++ [:healthy, :status],
          event_name: @event,
          measurement: :healthy,
          description: "1 when the most recent token attempt succeeded, 0 when it failed."
        )
      ]
    )
  end
end
