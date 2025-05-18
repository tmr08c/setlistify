defmodule Setlistify.SetlistFm.API.ExternalClient do
  @behaviour Setlistify.SetlistFm.API

  @root_endpoint "https://api.setlist.fm/rest/1.0"

  def search(query, endpoint \\ @root_endpoint) do
    %{"setlist" => setlists} =
      Req.get!(request(endpoint), url: "/search/setlists", params: %{"artistName" => query}).body

    Enum.map(setlists, fn setlist ->
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
  end

  def get_setlist(id, endpoint \\ @root_endpoint) do
    resp = Req.get!(request(endpoint), url: "/setlist/#{id}").body

    %{
      "artist" => %{"name" => artist_name},
      "venue" => %{"name" => venue_name},
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

    %{artist: artist_name, venue: %{name: venue_name}, date: format_date(date), sets: sets}
  end

  defp request(endpoint) do
    api_key = Application.fetch_env!(:setlistify, :setlist_fm_api_key)

    default_opts = [
      base_url: endpoint,
      headers: %{"x-api-key" => api_key, "Accept" => "application/json"}
    ]

    config_opts = Application.get_env(:setlistify, :setlist_fm_req_options, [])

    Req.new(Keyword.merge(default_opts, config_opts))
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
