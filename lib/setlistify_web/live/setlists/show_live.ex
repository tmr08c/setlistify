defmodule SetlistifyWeb.Setlists.ShowLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.{SetlistFm, Spotify}

  def mount(%{"id" => id}, _session, socket) do
    setlist = SetlistFm.API.get_setlist(id)
    access_token = get_in(socket.assigns, [:music_account, Access.key!(:access_token)])

    setlist =
      if access_token do
        client = Spotify.API.new(access_token)

        sets =
          setlist.sets
          |> Enum.map(fn set ->
            %{
              set
              | songs:
                  Task.async_stream(set.songs, fn song ->
                    Map.put(
                      song,
                      :spotify_info,
                      Spotify.API.search_for_track(client, setlist.artist, song.title)
                    )
                  end)
            }
          end)
          |> Enum.map(fn set -> %{set | songs: Enum.map(set.songs, &elem(&1, 1))} end)

        %{setlist | sets: sets}
      else
        setlist
      end

    {:ok,
     assign(socket,
       sets: setlist.sets,
       artist: setlist.artist,
       venue_name: setlist.venue.name,
       date: setlist.date
     )}
  end

  def render(assigns) do
    ~H"""
    <%= @artist %> @ <%= @venue_name %> on <%= @date %>

    <h2>Sets</h2>

    <%= for set <- @sets do %>
      <article>
        <h2><%= set_name(set) %></h2>

        <ol>
          <%= for song <- set.songs do %>
            <li class="flex space-x-1 items-center">
              <Heroicons.check
                :if={@music_account && song[:spotify_info] != nil}
                mini
                class="h-4 w-4"
                aria-label="found matching song"
              />
              <Heroicons.x_mark
                :if={@music_account && song[:spotify_info] == nil}
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
      <.button type="button" disabled>
        Create Playlist
      </.button>
    <% else %>
      <.link navigate={~p"/signin/spotify?redirect_to=#{@redirect_to}"}>
        Sign in to Spotify to Create Playlist
      </.link>
    <% end %>
    """
  end

  defp set_name(%{encore: encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name(%{name: nil}), do: "Unnamed Setlist"
  defp set_name(%{name: name}), do: name
end
