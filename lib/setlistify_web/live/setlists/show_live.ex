defmodule SetlistifyWeb.Setlists.ShowLive do
  @moduledoc false
  use SetlistifyWeb, :live_view

  alias Setlistify.AppleMusic
  alias Setlistify.MusicService
  alias Setlistify.Scope
  alias Setlistify.SetlistFm
  alias Setlistify.Spotify

  require OpenTelemetry.Tracer
  require OpentelemetryPhoenixLiveViewProcessPropagator.LiveView

  def mount(%{"id" => id}, _session, socket) do
    case SetlistFm.API.get_setlist(id) do
      {:ok, setlist} ->
        current_scope = socket.assigns[:current_scope]

        socket =
          assign(socket,
            sets: setlist.sets,
            artist: setlist.artist,
            venue_name: setlist.venue.name,
            venue_location: setlist.venue.location,
            date: setlist.date,
            redirect_to: "/setlist/#{id}",
            song_results: %{}
          )

        socket = maybe_start_song_searches(socket, setlist, current_scope)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Setlist not found")
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Failed to load setlist. Please try again.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_async({set_index, song_index}, {:ok, result}, socket) do
    song_results = Map.put(socket.assigns.song_results, {set_index, song_index}, {:ok, result})
    {:noreply, assign(socket, song_results: song_results)}
  end

  def handle_async({set_index, song_index}, {:exit, reason}, socket) do
    song_results = Map.put(socket.assigns.song_results, {set_index, song_index}, {:error, reason})
    {:noreply, assign(socket, song_results: song_results)}
  end

  def handle_event("create_playlist", _params, socket) do
    current_scope = socket.assigns.current_scope

    if Scope.authenticated?(current_scope) do
      create_and_populate_playlist(socket, current_scope.user_session)
    else
      {:noreply, put_flash(socket, :error, "Unable to access your music session. Please log in again.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.section_container class="py-6 sm:py-10">
      <div class="max-w-4xl mx-auto px-4">
        <div class="text-center mb-6 sm:mb-8">
          <h1 class="text-2xl sm:text-3xl md:text-4xl font-bold mb-2">
            <span class="text-emerald-400">{@artist}</span>
          </h1>
          <p id="venue-name" class="text-lg sm:text-xl text-gray-400">
            {@venue_name}
          </p>
          <p id="venue-location" class="text-gray-400">
            {format_location(@venue_location)} • {@date}
          </p>
        </div>

        <div
          id="setlist-sets"
          class="bg-black/50 border border-gray-800 rounded-xl p-4 sm:p-6 md:p-8 mb-6 sm:mb-8"
        >
          <div class="space-y-8">
            <%= for {set, set_index} <- Enum.with_index(@sets) do %>
              <article id={"set-#{set_index}"}>
                <h2 class="text-xl font-semibold mb-4 text-emerald-400">
                  {set_name(set)}
                </h2>

                <ol class="list-decimal list-inside space-y-2 ml-6">
                  <%= for {song, song_index} <- Enum.with_index(set.songs) do %>
                    <% song_result = Map.get(@song_results, {set_index, song_index}) %>
                    <li>
                      <span class="inline-flex items-center gap-2">
                        <%= if Scope.authenticated?(@current_scope) do %>
                          <%= case song_result do %>
                            <% nil -> %>
                              <.icon
                                name="hero-arrow-path-mini"
                                id={"loading-spinner-#{set_index}-#{song_index}"}
                                class="h-4 w-4 text-gray-400 animate-spin opacity-0"
                                aria-label="searching for song"
                                phx-hook="DelayedShow"
                                phx-update="ignore"
                                data-delay="250"
                              />
                            <% {:ok, %{track_info: nil}} -> %>
                              <.icon
                                name="hero-x-mark-mini"
                                class="h-4 w-4 text-red-500"
                                aria-label="no matching song found"
                              />
                            <% {:ok, _result} -> %>
                              <.icon
                                name="hero-check-mini"
                                class="h-4 w-4 text-emerald-500"
                                aria-label="found matching song"
                              />
                            <% {:error, _reason} -> %>
                              <.icon
                                name="hero-x-mark-mini"
                                class="h-4 w-4 text-red-500"
                                aria-label="search failed"
                              />
                          <% end %>
                        <% end %>
                        <span class={[
                          Scope.authenticated?(@current_scope) &&
                            match?({:ok, %{track_info: nil}}, song_result) &&
                            "text-gray-500",
                          "inline"
                        ]}>
                          {song.title}
                        </span>
                      </span>
                    </li>
                  <% end %>
                </ol>
              </article>
            <% end %>
          </div>
        </div>

        <div class="bg-gray-900 rounded-xl p-4 sm:p-6 border border-gray-800">
          <div class="text-center">
            <%= if Scope.authenticated?(@current_scope) do %>
              <div class="space-y-4">
                <p class="text-gray-400 mb-4">
                  Ready to create your playlist? We'll add all available tracks to your music library.
                </p>
                <.button type="button" phx-click="create_playlist" class="w-full sm:w-auto">
                  <.icon name="hero-musical-note" class="mr-2" /> Create Playlist
                </.button>
              </div>
            <% else %>
              <p class="text-gray-400">
                Sign in to create a playlist from this setlist
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </.section_container>
    """
  end

  defp maybe_start_song_searches(socket, setlist, current_scope) do
    if Scope.authenticated?(current_scope) do
      start_song_searches(socket, setlist, current_scope.user_session)
    else
      socket
    end
  end

  defp start_song_searches(socket, setlist, user_session) do
    setlist.sets
    |> Enum.with_index()
    |> Enum.flat_map(fn {set, set_index} ->
      set.songs
      |> Enum.with_index()
      |> Enum.map(fn {song, song_index} ->
        {set_index, song_index, song}
      end)
    end)
    |> Enum.reduce(socket, fn {set_index, song_index, song}, acc_socket ->
      OpentelemetryPhoenixLiveViewProcessPropagator.LiveView.start_async(
        acc_socket,
        {set_index, song_index},
        fn ->
          OpenTelemetry.Tracer.with_span "SetlistifyWeb.Setlists.ShowLive.search_song_async" do
            cover_artist = Map.get(song, :cover_artist)

            OpenTelemetry.Tracer.set_attributes([
              {"music.service", provider(user_session)},
              {"music.track", song.title},
              {"music.artist", setlist.artist},
              {"music.cover_artist", cover_artist || ""},
              {"song.set_index", set_index},
              {"song.song_index", song_index}
            ])

            track_info =
              MusicService.API.search_for_track(
                user_session,
                setlist.artist,
                song.title,
                cover_artist
              )

            %{
              track_info: track_info,
              set_index: set_index,
              song_index: song_index
            }
          end
        end
      )
    end)
  end

  defp create_and_populate_playlist(socket, user_session) do
    name = "#{socket.assigns.artist} @ #{socket.assigns.venue_name} (#{socket.assigns.date})"

    description =
      "Created by Setlistify: #{socket.assigns.artist} at #{socket.assigns.venue_name} on #{socket.assigns.date}"

    case MusicService.API.create_playlist(user_session, name, description) do
      {:ok, %{id: playlist_id, external_url: external_url}} ->
        track_ids = collect_track_ids(socket.assigns)

        case MusicService.API.add_tracks_to_playlist(user_session, playlist_id, track_ids) do
          {:ok, _} ->
            {:noreply,
             push_navigate(socket,
               to: ~p"/playlists?provider=#{provider(user_session)}&url=#{external_url}"
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to add tracks to playlist: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create playlist: #{inspect(reason)}")}
    end
  end

  defp collect_track_ids(assigns) do
    assigns.sets
    |> Enum.with_index()
    |> Enum.flat_map(fn {set, set_index} ->
      set.songs
      |> Enum.with_index()
      |> Enum.flat_map(fn {_song, song_index} ->
        song_result_track_id(assigns.song_results, {set_index, song_index})
      end)
    end)
  end

  defp song_result_track_id(song_results, key) do
    case Map.get(song_results, key) do
      {:ok, %{track_info: track_info}} when not is_nil(track_info) -> [track_info.track_id]
      _ -> []
    end
  end

  defp set_name(%{encore: encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name(%{name: nil}), do: "Unnamed Setlist"

  defp set_name(%{name: name}) do
    # Remove trailing colon if present for consistency with encore format
    String.trim_trailing(name, ":")
  end

  defp provider(%Spotify.UserSession{}), do: "spotify"
  defp provider(%AppleMusic.UserSession{}), do: "apple_music"

  defp format_location(%{city: city, state: state, country: country}) do
    [city, state, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end
end
