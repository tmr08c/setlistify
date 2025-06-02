defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  alias SetlistifyWeb.Components.SearchFormComponent

  require Logger
  require OpenTelemetry.Tracer

  def mount(_params, _session, socket) do
    {:ok, assign(socket, setlists: [], search: search_form(%{}))}
  end

  def handle_params(params, _uri, socket) when params == %{} do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_params(params, _uri, socket) do
    # Create a span for the handle_params operation
    OpenTelemetry.Tracer.with_span "SetlistifyWeb.SearchLive.handle_params" do
      OpenTelemetry.Tracer.set_attributes([
        {"query", inspect(params)}
      ])

      Logger.info("Log inside custom span looking for #{inspect(params)}")

      search_form = search_form(params)
      search_changeset = search_form.source

      setlists =
        if search_changeset.valid? do
          search_changeset
          |> Ecto.Changeset.get_field(:query)
          |> Setlistify.SetlistFm.API.search()
        else
          []
        end

      {:noreply, assign(socket, search: search_form, setlists: setlists)}
    end
  end

  def render(assigns) do
    ~H"""
    <.section_container class="py-10">
      <div class="max-w-lg mx-auto mb-10">
        <.live_component
          module={SearchFormComponent}
          id="results-search-form"
          search={@search}
          input_id="search-query-results"
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

  defp search_form(params) do
    params |> search_changeset() |> to_form(as: :search)
  end

  defp search_changeset(params) do
    types = %{query: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required(Map.keys(types))
  end

  defp format_location(%{city: city, state: state, country: country}) do
    [city, state, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_song_count(count) do
    ngettext("1 song", "%{count} songs", count)
  end
end
