defmodule Setlistify.SetlistFm.API do
  require OpenTelemetry.Tracer

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

  @type pagination() :: %{
          page: pos_integer(),
          total: non_neg_integer(),
          items_per_page: pos_integer()
        }

  @type search_response() ::
          {:ok,
           %{
             setlists: [search_result()],
             pagination: pagination()
           }}
          | {:error, :not_found}
          | {:error, {:api_error, term()}}

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

  @callback search(String.t(), pos_integer()) :: search_response()
  def search(query, page \\ 1) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.search" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "setlist_fm"},
        {"setlist_fm.operation", "search"},
        {"setlist_fm.search.query", query},
        {"setlist_fm.search.page", page}
      ])

      # Warning: different pages may have different expiration times in cache,
      # which could cause consistency issues if this becomes problematic
      Setlistify.Cache.fetch(:setlist_fm_search_cache, {query, page}, fn _cache_key ->
        case impl().search(query, page) do
          {:ok, _} = success -> {:commit, success}
          {:error, :not_found} = error -> {:commit, error}
          {:error, _} = error -> {:ignore, error}
        end
      end)
    end
  end

  @callback get_setlist(String.t()) :: {:ok, setlist()} | {:error, atom() | String.t()}
  def get_setlist(id) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.get_setlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"peer.service", "setlist_fm"},
        {"setlist_fm.operation", "get_setlist"},
        {"setlist_fm.setlist.id", id}
      ])

      Setlistify.Cache.fetch(:setlist_fm_setlist_cache, id, fn id ->
        case impl().get_setlist(id) do
          {:ok, _} = result -> {:commit, result}
          {:error, reason} -> {:ignore, {:error, reason}}
        end
      end)
    end
  end

  defp impl do
    Application.get_env(
      :setlistify,
      :setlistfm_api_client,
      Setlistify.SetlistFm.API.ExternalClient
    )
  end
end
