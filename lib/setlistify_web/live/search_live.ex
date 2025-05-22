defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  require Logger
  require OpenTelemetry.Tracer

  def mount(_params, _session, socket) do
    {:ok, assign(socket, setlists: [], search: search_form(%{}))}
  end

  def handle_params(params, _uri, socket) when params == %{} do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    # Create a span for the handle_params operation
    OpenTelemetry.Tracer.with_span "search_live.handle_params" do
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

  def handle_event("search", %{"search" => params}, socket) do
    search_changeset = search_changeset(params) |> Map.put(:action, :validate)
    search_form = to_form(search_changeset, as: :search)

    if search_changeset.valid? do
      {:noreply, push_patch(socket, to: ~p"/?#{params}")}
    else
      {:noreply, assign(socket, search: search_form)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="scroll-smooth">
      <%= if @setlists == [] do %>
        <.hero_section>
          <div class="flex flex-col h-full items-center justify-between px-4">
            <div class="flex-1 flex flex-col justify-center items-center text-center max-w-3xl mx-auto">
              <h1 class="text-3xl sm:text-4xl md:text-5xl font-bold mb-6">
                Transform <span class="text-emerald-400 font-extrabold">Live Shows</span>
                into <span class="text-emerald-400 font-extrabold">Playlists</span>
                with
                <span class="relative inline-block font-extrabold after:content-[''] after:absolute after:left-0 after:right-0 after:bottom-[-8px] after:h-1 after:bg-gradient-to-r after:from-emerald-400 after:via-emerald-500 after:to-emerald-600 after:rounded-sm">
                  One Click
                </span>
              </h1>

              <.rotating_text
                class="mb-8"
                text_class="text-gray-300 text-sm sm:text-base font-medium text-center px-4"
                texts={[
                  "Turn concert memories into streaming soundtracks",
                  "Create the perfect pre-concert playlist",
                  "Experience setlists from shows you missed",
                  "Build your music library with authentic live experiences",
                  "Share iconic concert experiences with friends"
                ]}
              />

              <div class="w-full max-w-lg mx-auto mb-8 sm:mb-16">
                <.form
                  for={@search}
                  name="search"
                  phx-submit="search"
                  class="w-full flex justify-center"
                >
                  <div class="w-full max-w-full">
                    <div class="relative w-full">
                      <input
                        type="text"
                        id="search-query"
                        name="search[query]"
                        value={@search[:query].value}
                        placeholder="Search for an artist or band..."
                        autocomplete="off"
                        class={[
                          "w-full px-4 sm:px-6 py-4 sm:py-5 pr-14 sm:pr-16 text-sm sm:text-base text-white bg-gradient-to-r from-gray-900 to-gray-800 border rounded-full placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-emerald-400 focus:ring-opacity-50 focus:border-emerald-500 transition-all duration-200 shadow-lg focus:shadow-emerald-500/25",
                          @search[:query].errors == [] && "border-gray-700 hover:border-gray-600",
                          @search[:query].errors != [] && "border-rose-400"
                        ]}
                      />
                      <button
                        type="submit"
                        class="absolute right-2 sm:right-3 top-1/2 -translate-y-1/2 w-9 h-9 sm:w-10 sm:h-10 bg-emerald-500 rounded-full flex items-center justify-center hover:bg-emerald-400 transition-colors"
                      >
                        <Heroicons.magnifying_glass class="w-4 h-4 sm:w-5 sm:h-5 text-black" />
                      </button>
                    </div>
                    <div :if={@search[:query].errors != []} class="mt-2">
                      <.error :for={msg <- @search[:query].errors}>
                        {SetlistifyWeb.CoreComponents.translate_error(msg)}
                      </.error>
                    </div>
                  </div>
                </.form>
              </div>
            </div>

            <div class="mb-8">
              <button
                type="button"
                id="learn-more-btn"
                class="learn-more-button flex flex-col items-center gap-1 hover:text-emerald-400 transition-colors"
                onclick="document.getElementById('how-it-works').scrollIntoView({ behavior: 'smooth' })"
                phx-hook="DelayedBounce"
              >
                <span class="text-sm font-normal">Learn More</span>
                <Heroicons.chevron_double_down class="w-5 h-5 sm:w-6 sm:h-6" />
              </button>
            </div>
          </div>
        </.hero_section>

        <.section_container id="how-it-works" class="text-center bg-gray-900">
          <h2 class="text-3xl font-bold mb-12">How It Works</h2>

          <div class="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            <.step_card number={1} title="Search an Artist">
              Enter any band or performer to see their concert history
            </.step_card>

            <.step_card number={2} title="Pick a Setlist">
              Browse through recent shows and select the perfect setlist
            </.step_card>

            <.step_card number={3} title="Create Playlist">
              With one click, generate a Spotify playlist of the entire show
            </.step_card>
          </div>
        </.section_container>
      <% else %>
        <.section_container class="py-10">
          <div class="max-w-lg mx-auto mb-10">
            <.form for={@search} name="search" phx-submit="search" class="w-full flex justify-center">
              <div class="w-full max-w-full">
                <div class="relative w-full">
                  <input
                    type="text"
                    id="search-query-results"
                    name="search[query]"
                    value={@search[:query].value}
                    placeholder="Search for an artist or band..."
                    autocomplete="off"
                    class={[
                      "w-full px-4 sm:px-6 py-4 sm:py-5 pr-14 sm:pr-16 text-sm sm:text-base text-white bg-gradient-to-r from-gray-900 to-gray-800 border rounded-full placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-emerald-400 focus:ring-opacity-50 focus:border-emerald-500 transition-all duration-200 shadow-lg focus:shadow-emerald-500/25",
                      @search[:query].errors == [] && "border-gray-700 hover:border-gray-600",
                      @search[:query].errors != [] && "border-rose-400"
                    ]}
                  />
                  <button
                    type="submit"
                    class="absolute right-2 sm:right-3 top-1/2 -translate-y-1/2 w-9 h-9 sm:w-10 sm:h-10 bg-emerald-500 rounded-full flex items-center justify-center hover:bg-emerald-400 transition-colors"
                  >
                    <Heroicons.magnifying_glass class="w-4 h-4 sm:w-5 sm:h-5 text-black" />
                  </button>
                </div>
                <div :if={@search[:query].errors != []} class="mt-2">
                  <.error :for={msg <- @search[:query].errors}>
                    {SetlistifyWeb.CoreComponents.translate_error(msg)}
                  </.error>
                </div>
              </div>
            </.form>
          </div>

          <h2 class="text-3xl font-bold text-center mb-12">Search Results</h2>

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
                  <p class="text-emerald-400 text-sm mt-2">{format_song_count(setlist.song_count)}</p>
                </li>
              </.link>
            <% end %>
          </ol>
        </.section_container>
      <% end %>
    </div>
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
