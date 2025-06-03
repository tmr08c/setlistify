defmodule Setlistify.SetlistFm.API.ExternalClient do
  @behaviour Setlistify.SetlistFm.API

  require Logger
  require OpenTelemetry.Tracer

  @root_endpoint "https://api.setlist.fm/rest/1.0"

  def search(query, page \\ 1, endpoint \\ @root_endpoint) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.ExternalClient.search" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "search"},
        {"setlist_fm.search.query", query},
        {"setlist_fm.search.page", page},
        {"http.url", "#{endpoint}/search/setlists"}
      ])

      response =
        Req.get!(request(endpoint), url: "/search/setlists", params: %{"artistName" => query, "p" => page})

      OpenTelemetry.Tracer.set_attributes([
        {"http.status_code", response.status}
      ])

      case response do
        %{status: 200, body: %{"setlist" => setlists, "page" => page_num, "total" => total, "itemsPerPage" => items_per_page}} ->
          formatted_setlists = Enum.map(setlists, fn setlist ->
            %{
              "artist" => %{"name" => artist_name},
              "eventDate" => date,
              "id" => id,
              "venue" => %{
                "name" => venue_name,
                "city" => city_data
              },
              "sets" => %{"set" => sets}
            } = setlist

            song_count =
              sets
              |> Enum.flat_map(&Map.get(&1, "song", []))
              |> length()

            location = build_location(city_data)

            %{
              artist: artist_name,
              date: format_date(date),
              id: id,
              venue: %{name: venue_name, location: location},
              song_count: song_count
            }
          end)

          %{
            setlists: formatted_setlists,
            pagination: %{
              page: page_num,
              total: total,
              items_per_page: items_per_page
            }
          }

        # A 404 is returned when no matching results are found
        %{status: 404} ->
          %{
            setlists: [],
            pagination: %{
              page: page,
              total: 0,
              items_per_page: nil
            }
          }
      end
      |> tap(fn %{setlists: setlists, pagination: pagination} ->
        OpenTelemetry.Tracer.set_attributes([
          {"setlist_fm.results.count", length(setlists)},
          {"setlist_fm.pagination.page", pagination.page},
          {"setlist_fm.pagination.total", pagination.total},
          {"setlist_fm.pagination.items_per_page", pagination.items_per_page}
        ])

        OpenTelemetry.Tracer.set_status(:ok, "")
      end)
    end
  rescue
    error ->
      Logger.error("Exception during Setlist.fm search: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      OpenTelemetry.Tracer.set_status(:error, "Exception: #{Exception.message(error)}")
      []
  end

  def get_setlist(id, endpoint \\ @root_endpoint) do
    OpenTelemetry.Tracer.with_span "Setlistify.SetlistFm.API.ExternalClient.get_setlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "get_setlist"},
        {"setlist_fm.setlist.id", id},
        {"http.url", "#{endpoint}/setlist/#{id}"}
      ])

      response = Req.get!(request(endpoint), url: "/setlist/#{id}")

      OpenTelemetry.Tracer.set_attributes([
        {"http.status_code", response.status}
      ])

      resp = response.body

      %{
        "artist" => %{"name" => artist_name},
        "venue" => %{"name" => venue_name, "city" => city_data},
        "eventDate" => date,
        # The [docs](https://api.setlist.fm/docs/1.0/json_Setlist.html) do not
        # indicate there is a "sets" key, but only a "set" key which is an array
        # of set resources. For now, I am going to assume this is essentially an
        # extraneous key and we can dig into the sub-"set" array and not miss out
        # on anything.
        "sets" => %{"set" => sets}
      } = resp

      sets =
        Enum.map(sets, fn set ->
          songs = set |> Map.get("song", []) |> Enum.map(&%{title: Map.get(&1, "name")})
          %{name: set["name"], encore: set["encore"], songs: songs}
        end)

      location = build_location(city_data)

      result = %{
        artist: artist_name,
        venue: %{name: venue_name, location: location},
        date: format_date(date),
        sets: sets
      }

      OpenTelemetry.Tracer.set_attributes([
        {"setlist_fm.artist", artist_name},
        {"setlist_fm.venue", venue_name},
        {"setlist_fm.sets.count", length(sets)},
        {"setlist_fm.songs.count", sets |> Enum.flat_map(& &1.songs) |> length()}
      ])

      OpenTelemetry.Tracer.set_status(:ok, "")
      result
    end
  rescue
    error ->
      Logger.error("Exception during Setlist.fm get_setlist: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      OpenTelemetry.Tracer.set_status(:error, "Exception: #{Exception.message(error)}")
      raise error
  end

  defp request(endpoint) do
    api_key = Application.fetch_env!(:setlistify, :setlist_fm_api_key)

    default_opts = [
      base_url: endpoint,
      headers: %{"x-api-key" => api_key, "Accept" => "application/json"}
    ]

    config_opts = Application.get_env(:setlistify, :setlist_fm_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  @date_regex ~r/(?<day>\d{2})-(?<month>\d{2})-(?<year>\d{4})/
  defp format_date(date) do
    %{"year" => year, "month" => month, "day" => day} = Regex.named_captures(@date_regex, date)
    Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day))
  end

  defp build_location(city_data) do
    city_name = Map.get(city_data, "name", "Unknown")

    country_name =
      case Map.get(city_data, "country") do
        %{"name" => name} -> name
        _ -> "Unknown"
      end

    # stateCode is optional - only present for certain countries like US, Canada, etc.
    state_code = Map.get(city_data, "stateCode")

    %{
      city: city_name,
      state: state_code,
      country: country_name
    }
  end
end
