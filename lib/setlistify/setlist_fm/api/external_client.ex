defmodule Setlistify.SetlistFm.API.ExternalClient do
  @behaviour Setlistify.SetlistFm.API

  @root_endpoint "https://api.setlist.fm/rest/1.0"

  def search(query, endpoint \\ @root_endpoint) do
    api_key = Application.fetch_env!(:setlistify, :setlist_fm_api_key)

    req =
      Req.new(
        base_url: endpoint,
        headers: %{"x-api-key" => api_key, "Accept" => "application/json"}
      )

    %{"setlist" => setlists} =
      Req.get!(req, url: "/search/setlists", params: %{"artistName" => query}).body

    Enum.map(setlists, fn setlist ->
      %{
        "artist" => %{"name" => artist_name},
        "venue" => %{"name" => venue_name},
        "eventDate" => date
      } = setlist

      re = ~r/(?<day>\d{2})-(?<month>\d{2})-(?<year>\d{4})/
      %{"year" => year, "month" => month, "day" => day} = Regex.named_captures(re, date)
      date = Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      %{artist: artist_name, venue: %{name: venue_name}, date: date}
    end)
  end
end
