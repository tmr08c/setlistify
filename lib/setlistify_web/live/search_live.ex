defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, setlists: [], search: %{})}
  end

  def handle_event("search", %{"search" => params}, socket) do
    search = search_changeset(params)

    if search.valid? do
      setlists =
        search
        |> Ecto.Changeset.get_field(:query)
        |> Setlistify.SetlistFm.API.search()

      {:noreply, assign(socket, setlists: setlists, search: search)}
    else
      {:noreply, assign(socket, setlists: [], search: search)}
    end
  end

  def render(assigns) do
    ~H"""
    <.simple_form :let={f} for={@search} as="search" phx-submit="search" id="phx-search">
      <.input field={{f, :query}} />

      <:actions>
        <.button>Search</.button>
      </:actions>
    </.simple_form>

    <ol>
      <%= for setlist <- @setlists do %>
        <li>
          <.link navigate={~p"/setlists/#{setlist.id}"} {tid(["setlist", setlist.id])}>
            <%= setlist.artist %> @ <%= setlist.venue.name %> on <%= setlist.date %>
          </.link>
        </li>
      <% end %>
    </ol>
    """
  end

  def search_changeset(params) do
    types = %{query: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required(Map.keys(types))
    |> Map.put(:action, :validate)
  end
end
