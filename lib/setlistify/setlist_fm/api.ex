defmodule Setlistify.SetlistFm.API do
  @type search_result() :: %{
          artist: String.t(),
          venue: %{
            name: String.t(),
            location: %{
              city: String.t(),
              state: String.t() | nil,
              country: String.t()
            }
          },
          date: Date.t(),
          id: String.t(),
          song_count: non_neg_integer()
        }

  @type setlist() :: %{
          artist: String.t(),
          venue: %{
            name: String.t(),
            location: %{
              city: String.t(),
              state: String.t() | nil,
              country: String.t()
            }
          },
          date: Date.t(),
          sets: [set()]
        }

  @type set :: %{
          optional(:encore) => integer(),
          name: nil | String.t(),
          songs: [%{title: String.t()}]
        }
  @callback search(String.t()) :: [search_result()]
  def search(query) do
    :setlist_fm_search_cache |> Cachex.fetch(query, &impl().search/1) |> elem(1)
  end

  @callback get_setlist(String.t()) :: setlist()
  def get_setlist(id) do
    :setlist_fm_setlist_cache |> Cachex.fetch(id, &impl().get_setlist/1) |> elem(1)
  end

  defp impl do
    Application.get_env(
      :setlistify,
      :setlistfm_api_client,
      Setlistify.SetlistFm.API.ExternalClient
    )
  end
end
