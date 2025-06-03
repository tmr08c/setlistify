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

        <%= if should_show_pagination?(@pagination) do %>
          <.pagination
            page={@pagination.page}
            total_pages={total_pages(@pagination)}
            query={@query_params["query"]}
          />
        <% end %>
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
      {page, remainder} when page > 0 ->
        # Accept the parse if remainder is empty or starts with a decimal point
        if remainder == "" or String.starts_with?(remainder, ".") do
          page
        else
          1
        end

      _ ->
        1
    end
  end

  defp parse_page(_), do: 1

  defp should_show_pagination?(%{total: _total, items_per_page: nil}), do: false

  defp should_show_pagination?(%{total: total, items_per_page: items_per_page})
       when total > items_per_page,
       do: true

  defp should_show_pagination?(_), do: false

  defp total_pages(%{total: _total, items_per_page: nil}), do: 1

  defp total_pages(%{total: total, items_per_page: items_per_page}) when items_per_page > 0 do
    ceil(total / items_per_page)
  end

  defp total_pages(_), do: 1

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :query, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <nav class="flex justify-center mt-8" aria-label="Pagination Navigation">
      <div class="flex items-center gap-6">
        <!-- Previous -->
        <%= if @page > 1 do %>
          <.link
            navigate={build_pagination_url(@query, @page - 1)}
            class="nav-btn font-light text-sm inline-flex items-center gap-2 text-gray-600 hover:text-emerald-500 transition-colors"
          >
            ← Prev
          </.link>
        <% else %>
          <span class="nav-btn disabled font-light text-sm inline-flex items-center gap-2 text-gray-700 cursor-not-allowed">
            ← Prev
          </span>
        <% end %>
        
    <!-- Page Numbers -->
        <div class="flex items-center gap-4">
          {render_page_numbers(assigns)}
        </div>
        
    <!-- Next -->
        <%= if @page < @total_pages do %>
          <.link
            navigate={build_pagination_url(@query, @page + 1)}
            class="nav-btn font-light text-sm inline-flex items-center gap-2 text-gray-600 hover:text-emerald-500 transition-colors"
          >
            Next →
          </.link>
        <% else %>
          <span class="nav-btn disabled font-light text-sm inline-flex items-center gap-2 text-gray-700 cursor-not-allowed">
            Next →
          </span>
        <% end %>
      </div>
    </nav>
    """
  end

  defp render_page_numbers(assigns) do
    page_range = calculate_page_range(assigns.page, assigns.total_pages)

    assigns = assign(assigns, :page_range, page_range)

    ~H"""
    <%= for item <- @page_range do %>
      <%= case item do %>
        <% :ellipsis -> %>
          <span class="text-gray-500 font-light">•••</span>
        <% page_num -> %>
          <%= if page_num == @page do %>
            <span class="pagination-button active font-light inline-flex items-center justify-center w-8 h-10 text-emerald-500 border-b-2 border-emerald-500">
              {page_num}
            </span>
          <% else %>
            <.link
              navigate={build_pagination_url(@query, page_num)}
              class="pagination-button font-light inline-flex items-center justify-center w-8 h-10 text-gray-600 hover:text-white transition-colors"
            >
              {page_num}
            </.link>
          <% end %>
      <% end %>
    <% end %>
    """
  end

  defp calculate_page_range(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp calculate_page_range(current_page, total_pages) do
    cond do
      current_page <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total_pages]

      current_page >= total_pages - 3 ->
        [1, :ellipsis] ++ Enum.to_list((total_pages - 4)..total_pages)

      true ->
        [1, :ellipsis, current_page - 1, current_page, current_page + 1, :ellipsis, total_pages]
    end
  end

  defp build_pagination_url(query, page) do
    "/setlists?#{URI.encode_query(%{"query" => query, "page" => page})}"
  end
end
