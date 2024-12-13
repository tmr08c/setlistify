defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, setlists: [], search: search_form(%{}))}
  end

  def handle_params(params, _uri, socket) when params == %{} do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    search_form = search_form(params)
    search_changeset = search_form.source

    setlists =
      if search_changeset.valid? do
        search_changeset |> Ecto.Changeset.get_field(:query) |> Setlistify.SetlistFm.API.search()
      else
        []
      end

    {:noreply, assign(socket, search: search_form, setlists: setlists)}
  end

  def handle_event("search", %{"search" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def render(assigns) do
    ~H"""
    <.simple_form for={@search} name="search" phx-submit="search" class="mb-10">
      <.input field={@search[:query]} placeholder="Search by artist..." />

      <:actions>
        <.button class="w-full">Search</.button>
      </:actions>
    </.simple_form>

    <ol :if={@setlists != []} class="flex flex-col divide-y divide-slate-200">
      <%= for setlist <- @setlists do %>
        <.link navigate={~p"/setlist/#{setlist.id}"} {tid(["setlist", setlist.id])}>
          <li class="py-6 px-8 flex space-x-5 hover:bg-slate-100">
            <time
              datetime={setlist.date}
              class="border-2 border-slate-600 text-center rounded shadow-sm font-mono"
            >
              <div class="uppercase font-medium bg-slate-300 p-2">
                {Calendar.strftime(setlist.date, "%b '%y")}
              </div>

              <div class="py-3">{setlist.date.day}</div>
            </time>
            <div class="self-center space-y-1">
              <div class="text-lg">{setlist.artist}</div>
              <div class="font-light text-slate-400">{setlist.venue.name}</div>
            </div>
          </li>
        </.link>
      <% end %>
    </ol>
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
    |> Map.put(:action, :validate)
  end
end
