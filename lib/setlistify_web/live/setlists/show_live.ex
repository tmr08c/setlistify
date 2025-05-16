defmodule SetlistifyWeb.Setlists.ShowLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.{SetlistFm, Spotify}

  def mount(%{"id" => id}, _session, socket) do
    setlist = SetlistFm.API.get_setlist(id)
    user_session = socket.assigns[:user_session]

    setlist =
      if user_session do
        sets =
          setlist.sets
          |> Enum.map(fn set ->
            songs =
              Task.async_stream(set.songs, fn song ->
                spotify_info =
                  Spotify.API.search_for_track(user_session, setlist.artist, song.title)

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

  def handle_event("create_playlist", _params, socket) do
    user_session = socket.assigns.user_session

    if user_session do
      name = "#{socket.assigns.artist} @ #{socket.assigns.venue_name} (#{socket.assigns.date})"

      description =
        "Created by Setlistify: #{socket.assigns.artist} at #{socket.assigns.venue_name} on #{socket.assigns.date}"

      %{id: playlist_id, external_url: external_url} =
        Spotify.API.create_playlist(user_session, name, description)

      # Build a flatlist of track Ids from our setlist
      track_ids =
        Enum.flat_map(socket.assigns.sets, fn set ->
          set.songs
          |> Enum.filter(&(Map.has_key?(&1, :spotify_info) and not is_nil(&1.spotify_info)))
          |> Enum.map(& &1.spotify_info.uri)
        end)

      :ok = Spotify.API.add_tracks_to_playlist(user_session, playlist_id, track_ids)

      {:noreply, push_navigate(socket, to: ~p"/playlists?provider=spotify&url=#{external_url}")}
    else
      {:noreply,
       put_flash(socket, :error, "Unable to access Spotify session. Please log in again.")}
    end
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
                    :if={@user_session && song[:spotify_info] != nil}
                    mini
                    class="h-4 w-4"
                    aria-label="found matching song"
                  />
                  <Heroicons.x_mark
                    :if={@user_session && song[:spotify_info] == nil}
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

    <%= if @user_session do %>
      <.button type="button" phx-click="create_playlist">
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
