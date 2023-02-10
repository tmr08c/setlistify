defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, result: "", search: %{})}
  end

  def handle_event("search", %{"search" => params}, socket) do
    search = search_changeset(params)

    if search.valid? do
      {:noreply,
       assign(socket, result: "Searching for setlists for '#{params["query"]}'.", search: search)}
    else
      {:noreply, assign(socket, result: "", search: search)}
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

    <%= @result %>
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
