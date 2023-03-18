defmodule SetlistifyWeb.Setlists.ShowLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.SetlistFm

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      {:ok, assign(socket, setlist: SetlistFm.API.get_setlist(id))}
    else
      {:ok, assign(socket, setlist: nil)}
    end
  end

  def render(assigns) do
    ~H"""
    <%= if !@setlist do %>
      Fetching setlist...
    <% else %>
      <%= if @music_account do %>
        <button type="button">Create Playlist</button>
      <% else %>
        <.link navigate={~p"/signin?redirect_to=#{@redirect_to}"}>
          Sign in to Spotify to Create Playlist
        </.link>
      <% end %>
      <hr />
      <%= @setlist.artist %> @ <%= @setlist.venue.name %> on <%= @setlist.date %>

      <h2>Sets</h2>

      <%= for set <- @setlist.sets do %>
        <article>
          <h2><%= set_name(set) %></h2>

          <ol>
            <%= for song <- set.songs do %>
              <li><%= song %></li>
            <% end %>
          </ol>
        </article>
      <% end %>
    <% end %>
    """
  end

  defp set_name(%{encore: encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name(%{name: nil}), do: "Unnamed Setlist"
  defp set_name(%{name: name}), do: name
end
