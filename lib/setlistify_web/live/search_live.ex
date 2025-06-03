defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  alias SetlistifyWeb.Components.SearchFormComponent

  require Logger
  require OpenTelemetry.Tracer

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       setlists: [],
       query_params: %{},
       pagination: %{page: 1, total: 0, items_per_page: 0}
     )}
  end

  def handle_params(%{"query" => query} = params, _uri, socket)
      when is_binary(query) and byte_size(query) > 0 do
    case String.trim(query) do
      "" ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      trimmed_query ->
        page = parse_page(params["page"])

        OpenTelemetry.Tracer.with_span "SetlistifyWeb.SearchLive.handle_params" do
          OpenTelemetry.Tracer.set_attributes([
            {"query", trimmed_query},
            {"page", page}
          ])

          %{setlists: setlists, pagination: pagination} =
            Setlistify.SetlistFm.API.search(trimmed_query, page)

          {:noreply,
           assign(socket,
             setlists: setlists,
             pagination: pagination,
             query_params: params
           )}
        end
    end
  end

  # Catch-all: any other params structure redirects home
  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <.section_container class="py-10">
      <div class="max-w-lg mx-auto mb-10">
        <.live_component
          module={SearchFormComponent}
          id="results-search-form"
          input_id="search-query-results"
          query_params={@query_params}
        />
      </div>

      <h2 class="text-3xl font-bold text-center mb-12">Search Results</h2>

      <%= if @setlists == [] do %>
        <p class="text-center text-gray-400 text-lg">No results found</p>
      <% else %>
        <ol class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <%= for setlist <- @setlists do %>
            <.link navigate={~p"/setlist/#{setlist.id}"} {tid(["setlist", setlist.id])}>
              <li class="bg-black/50 border border-gray-800 rounded-xl p-6 hover:border-emerald-500 transition-colors">
                <time datetime={setlist.date} class="inline-block mb-3">
                  <span class="text-sm text-gray-400">
                    {Calendar.strftime(setlist.date, "%B %d, %Y")}
                  </span>
                </time>

                <h3 class="text-lg font-semibold mb-1">{setlist.artist}</h3>
                <p class="text-gray-400">{setlist.venue.name}</p>
                <p class="text-gray-400 text-sm">{format_location(setlist.venue.location)}</p>
                <p class="text-emerald-400 text-sm mt-2">
                  {format_song_count(setlist.song_count)}
                </p>
              </li>
            </.link>
          <% end %>
        </ol>
      <% end %>
    </.section_container>
    """
  end

  defp format_location(%{city: city, state: state, country: country}) do
    [city, state, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_song_count(count) do
    ngettext("1 song", "%{count} songs", count)
  end

  defp parse_page(nil), do: 1
  defp parse_page(""), do: 1

  defp parse_page(page_string) when is_binary(page_string) do
    case Integer.parse(page_string) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
