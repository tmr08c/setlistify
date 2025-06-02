defmodule SetlistifyWeb.Components.SearchFormComponent do
  use SetlistifyWeb, :live_component
  use Gettext, backend: SetlistifyWeb.Gettext

  require OpenTelemetry.Tracer

  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@search}
        name="search"
        phx-submit="search"
        phx-target={@myself}
        class="w-full flex justify-center"
      >
        <div class="w-full max-w-full">
          <div class="relative w-full">
            <input
              type="text"
              id={@input_id}
              name="search[query]"
              value={@search[:query].value}
              placeholder="Search for an artist or band..."
              autocomplete="off"
              class={[
                "w-full px-4 sm:px-6 py-4 sm:py-5 pr-14 sm:pr-16 text-sm sm:text-base text-white bg-gradient-to-r from-gray-900 to-gray-800 border rounded-full placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-emerald-400 focus:ring-opacity-50 focus:border-emerald-500 shadow-lg focus:shadow-emerald-500/25",
                if(Enum.empty?(@search[:query].errors || []),
                  do: "border-gray-700 hover:border-gray-600",
                  else: "border-rose-400"
                )
              ]}
            />
            <button
              type="submit"
              class="absolute right-2 sm:right-3 top-1/2 -translate-y-1/2 w-9 h-9 sm:w-10 sm:h-10 bg-emerald-500 rounded-full flex items-center justify-center hover:bg-emerald-400"
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
    """
  end

  def handle_event("search", %{"search" => params}, socket) do
    OpenTelemetry.Tracer.with_span "SetlistifyWeb.Components.SearchFormComponent.handle_event" do
      OpenTelemetry.Tracer.set_attributes([
        {"event", "search"},
        {"params", inspect(params)}
      ])

      search_changeset = search_changeset(params) |> Map.put(:action, :validate)
      search_form = to_form(search_changeset, as: :search)

      OpenTelemetry.Tracer.set_attribute("search.valid", search_changeset.valid?)

      if search_changeset.valid? do
        {:noreply, push_navigate(socket, to: ~p"/setlists?#{params}")}
      else
        {:noreply, assign(socket, search: search_form)}
      end
    end
  end

  defp search_changeset(params) do
    types = %{query: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required(Map.keys(types))
  end
end
