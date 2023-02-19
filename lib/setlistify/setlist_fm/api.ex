defmodule Setlistify.SetlistFm.API do
  @type search_result() :: %{artist: String.t(), venue: %{name: String.t()}, date: Date.t()}

  @callback search(String.t()) :: [search_result()]
  def search(query), do: impl().search(query)

  defp impl do
    Application.get_env(
      :setlistify,
      :setlistfm_api_client,
      Setlistify.SetlistFm.API.ExternalClient
    )
  end
end
