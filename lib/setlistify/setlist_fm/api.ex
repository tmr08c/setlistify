defmodule Setlistify.SetlistFm.API do
  @type search_result() :: %{
          artist: String.t(),
          venue: %{name: String.t()},
          date: Date.t(),
          id: String.t()
        }

  @type setlist() :: %{
          artist: String.t(),
          venue: %{name: String.t()},
          date: Date.t(),
          sets: [set()]
        }

  @type set :: %{
          optional(:name) => String.t(),
          songs: [String.t()]
        }
  @callback search(String.t()) :: [search_result()]
  def search(query), do: impl().search(query)

  @callback get_setlist(String.t()) :: setlist()
  def get_setlist(id), do: impl().get_setlist(id)

  defp impl do
    Application.get_env(
      :setlistify,
      :setlistfm_api_client,
      Setlistify.SetlistFm.API.ExternalClient
    )
  end
end
