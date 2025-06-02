defmodule SetlistifyWeb.HomeLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  alias SetlistifyWeb.Components.SearchFormComponent

  def mount(_params, _session, socket) do
    {:ok, assign(socket, search: search_form(%{}))}
  end

  def render(assigns) do
    ~H"""
    <div class="scroll-smooth">
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
              <.live_component
                module={SearchFormComponent}
                id="hero-search-form"
                search={@search}
                input_id="search-query"
              />
            </div>
          </div>

          <div class="mb-8">
            <button
              type="button"
              id="learn-more-btn"
              class="learn-more-button flex flex-col items-center gap-1 text-white hover:text-emerald-400"
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
end
