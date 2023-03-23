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

    <%= for {set, songs} <- @songs |> Enum.group_by(&{&1.name, &1.encore}) |> Enum.reverse() do %>
      <article>
        <h2><%= set_name(set) %></h2>

        <ol>
          <%= for song <- songs do %>
            <li class="flex space-x-1 items-center">
              <Heroicons.check :if={@music_account && song.spotify_info != nil} mini class="h-4 w-4" />
              <Heroicons.x_mark :if={@music_account && song.spotify_info == nil} mini class="h-4 w-4" />
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

  defp wip_modal(assigns) do
    ~H"""
    <.modal id="confirm-modal" on_cancel={hide_modal("confirm-modal")}>
      <%= if @searched? do %>
        <ol>
          Matched <%= Enum.count(@songs, fn {_, info} -> info != nil end) %> out of <%= length(@songs) %> songs.
          <%= for {title, spotify_info} <- @songs do %>
            <li class="flex content-center">
              <Heroicons.check :if={spotify_info != nil} mini class="h-4 w-4" />
              <Heroicons.x_mark :if={spotify_info == nil} mini class="h-4 w-4" />
              <%= title %>
              <div :if={spotify_info}>(<%= spotify_info.uri %>)</div>
            </li>
          <% end %>
        </ol>
      <% else %>
        Searching for songs...
      <% end %>
      <:confirm :if={@searched?}>Create</:confirm>
      <:cancel>Cancel</:cancel>
    </.modal>
    """
  end

  defp set_name({_, encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name({nil, _}), do: "Unnamed Setlist"
  defp set_name({name, _}), do: name
end
