defmodule SetlistifyWeb.Setlists.ShowLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.{SetlistFm, Spotify}

  def mount(%{"id" => id}, _session, %{assigns: %{music_account: nil}} = socket) do
    setlist = SetlistFm.API.get_setlist(id)

    songs =
      Enum.flat_map(setlist.sets, fn set ->
        {songs, set} = Map.pop(set, :songs)
        Enum.map(songs, &Map.merge(&1, set))
      end)

    {:ok, assign(socket, setlist: setlist, songs: songs)}
  end

  def mount(%{"id" => id}, _session, socket) do
    client = Spotify.API.new(socket.assigns.music_account.access_token)
    setlist = SetlistFm.API.get_setlist(id)

    songs =
      setlist.sets
      |> Enum.flat_map(fn set ->
        {songs, set} = Map.pop(set, :songs)
        Enum.map(songs, &Map.merge(&1, set))
      end)
      |> Task.async_stream(fn song ->
        Map.merge(
          song,
          %{spotify_info: Spotify.API.search_for_track(client, setlist.artist, song.title)}
        )
      end)
      |> Enum.map(&elem(&1, 1))

    {:ok, assign(socket, setlist: setlist, songs: songs)}
  end

  def render(assigns) do
    ~H"""
    <%= @setlist.artist %> @ <%= @setlist.venue.name %> on <%= @setlist.date %>

    <h2>Sets</h2>

    <div :if={@music_account}>
      Matched <%= Enum.count(@songs, &(not is_nil(&1.spotify_info))) %> out of <%= length(@songs) %> songs.
    </div>
    <!--
    TODO Fix ordering

    See http://localhost:4000/setlist/7bbc8268 for examples
    -->
    <%= for {set, songs} <- @songs |> Enum.group_by(&{&1.name, &1[:encore]}) |> Enum.reverse() do %>
      <article>
        <h2><%= set_name(set) %></h2>

        <ol>
          <%= for song <- songs do %>
            <li class="flex space-x-1 items-center">
              <Heroicons.check
                :if={@music_account && song.spotify_info != nil}
                mini
                class="h-4 w-4"
                aria-label="found matching song"
              />
              <Heroicons.x_mark
                :if={@music_account && song.spotify_info == nil}
                mini
                class="h-4 w-4"
                aria-label="no matching song found"
              />
              <span><%= song.title %></span>
            </li>
          <% end %>
        </ol>
      </article>
    <% end %>
    <hr />
    <%= if @music_account do %>
      <.button type="button" phx-click={show_modal("confirm-modal") |> JS.push("create-playlist")}>
        Create Playlist
      </.button>
    <% else %>
      <.link navigate={~p"/signin/spotify?redirect_to=#{@redirect_to}"}>
        Sign in to Spotify to Create Playlist
      </.link>
    <% end %>
    """
  end

  defp set_name({_, encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name({nil, _}), do: "Unnamed Setlist"
  defp set_name({name, _}), do: name
end
