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
        |> Map.fetch!("setlist")
        |> Enum.map(fn setlist ->
          %{"artist" => %{"name" => artist_name}, "venue" => %{"name" => venue_name}} = setlist
          %{artist: artist_name, venue: venue_name}
        end)

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

    <%= for setlist <- @setlists do %>
      Artist: <%= Map.fetch!(setlist, :artist) %>
      Venue: <%= Map.fetch!(setlist, :venue) %>
    <% end %>
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
