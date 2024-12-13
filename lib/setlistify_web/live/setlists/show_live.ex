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
            songs =
              Task.async_stream(set.songs, fn song ->
                spotify_info = Spotify.API.search_for_track(client, setlist.artist, song.title)
                Map.put(song, :spotify_info, spotify_info)
              end)

            %{set | songs: songs}
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
    <h1 class="mb-3 text-2xl">{@artist} @ {@venue_name} on {@date}</h1>

    <div class="space-y-3 mb-6">
      <%= for set <- @sets do %>
        <article>
          <h2 class="text-lg mb-3">{set_name(set)}</h2>

          <ol class="list-decimal">
            <%= for song <- set.songs do %>
              <li>
                <div class="flex space-x-1 items-center">
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
                  <span>{song.title}</span>
                </div>
              </li>
            <% end %>
          </ol>
        </article>
      <% end %>
    </div>

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
