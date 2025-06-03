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

  @type search_response() :: %{
          setlists: [search_result()],
          pagination: %{
            page: pos_integer(),
            total: non_neg_integer(),
            items_per_page: pos_integer() | nil
          }
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
  @callback search(String.t(), pos_integer()) :: search_response()
  def search(query, page \\ 1) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.search" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "search"},
        {"setlist_fm.search.query", query},
        {"setlist_fm.search.page", page}
      ])

      # Cachex uses a separate process, so we need to propagate OpenTelemetry context
      parent_ctx = OpenTelemetry.Ctx.get_current()
      parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

      # Warning: different pages may have different expiration times in cache,
      # which could cause consistency issues if this becomes problematic
      cache_key = {query, page}

      :setlist_fm_search_cache
      |> Cachex.fetch(cache_key, fn _cache_key ->
        OpenTelemetry.Ctx.attach(parent_ctx)
        OpenTelemetry.Tracer.set_current_span(parent_span)

        impl().search(query, page)
      end)
      |> elem(1)
    end
  end

  @callback get_setlist(String.t()) :: setlist()
  def get_setlist(id) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.get_setlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "get_setlist"},
        {"setlist_fm.setlist.id", id}
      ])

      # Cachex uses a separate process, so we need to propagate OpenTelemetry context
      parent_ctx = OpenTelemetry.Ctx.get_current()
      parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

      :setlist_fm_setlist_cache
      |> Cachex.fetch(id, fn id ->
        OpenTelemetry.Ctx.attach(parent_ctx)
        OpenTelemetry.Tracer.set_current_span(parent_span)

        impl().get_setlist(id)
      end)
      |> elem(1)
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
