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

  # TODO Try to find a more elegant want to handle auth flow when necessary,
  # bring person back to the page. Maybe a new window?
  def handle_event("create-playlist", _, socket) do
    # TODO
    # - handle state
    # - probably turn off show dialog
    uri =
      "https://accounts.spotify.com/authorize"
      |> URI.new!()
      |> URI.append_query(
        URI.encode_query(%{
          client_id: Application.fetch_env!(:setlistify, :spotify_client_id),
          response_type: "code",
          redirect_uri: url(~p"/spotifyauthcallback"),
          state: "TODO",
          scope: "playlist-modify-private",
          show_dialog: true
        })
      )
      |> URI.to_string()
      |> IO.inspect(label: "redirect URI")

    {:noreply, redirect(socket, external: uri)}
  end

  def render(assigns) do
    ~H"""
    <%= if !@setlist do %>
      Fetching setlist...
    <% else %>
      <button type="button" phx-click="create-playlist">Create Playlist</button>
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
