defmodule SetlistifyWeb.Setlists.ShowLive do
  @moduledoc false
  use SetlistifyWeb, :live_view

  alias Setlistify.AppleMusic
  alias Setlistify.MusicService
  alias Setlistify.SetlistFm
  alias Setlistify.Spotify

  require OpenTelemetry.Tracer
  require OpentelemetryPhoenixLiveViewProcessPropagator.LiveView

  def mount(%{"id" => id}, _session, socket) do
    case SetlistFm.API.get_setlist(id) do
      {:ok, setlist} ->
        scope = socket.assigns[:current_scope]

        socket =
          assign(socket,
            sets: setlist.sets,
            artist: setlist.artist,
            venue_name: setlist.venue.name,
            venue_location: setlist.venue.location,
            date: setlist.date,
            redirect_to: "/setlist/#{id}"
          )

        socket = maybe_start_song_searches(socket, setlist, scope)

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

  def handle_event("create_playlist", _params, socket) do
    scope = socket.assigns.current_scope

    if Setlistify.Scope.authenticated?(scope) do
      create_and_populate_playlist(socket, scope.user_session)
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
          <p class="text-lg sm:text-xl text-gray-400">
            {@venue_name}
          </p>
          <p class="text-gray-400">
            {format_location(@venue_location)} • {@date}
          </p>
        </div>

        <div class="bg-black/50 border border-gray-800 rounded-xl p-4 sm:p-6 md:p-8 mb-6 sm:mb-8">
          <div class="space-y-8">
            <%= for set <- @sets do %>
              <article>
                <h2 class="text-xl font-semibold mb-4 text-emerald-400">
                  {set_name(set)}
                </h2>

                <ol class="list-decimal list-inside space-y-2 ml-6">
                  <%= for {song, song_index} <- Enum.with_index(set.songs) do %>
                    <% set_index = Enum.find_index(@sets, &(&1 == set))
                    async_key = String.to_atom("song_#{set_index}_#{song_index}")
                    async_result = Map.get(assigns, async_key) %>
                    <li>
                      <span class="inline-flex items-center gap-2">
                        <%= if @user_session && async_result do %>
                          <.async_result :let={result} assign={async_result}>
                            <:loading>
                              <Heroicons.arrow_path
                                mini
                                id={"loading-spinner-#{set_index}-#{song_index}"}
                                class="h-4 w-4 text-gray-400 animate-spin opacity-0"
                                aria-label="searching for song"
                                phx-hook="DelayedShow"
                                data-delay="250"
                              />
                            </:loading>
                            <:failed :let={_failure}>
                              <Heroicons.x_mark
                                mini
                                class="h-4 w-4 text-red-500"
                                aria-label="search failed"
                              />
                            </:failed>
                            <%= if result[:track_info] do %>
                              <Heroicons.check
                                mini
                                class="h-4 w-4 text-emerald-500"
                                aria-label="found matching song"
                              />
                            <% else %>
                              <Heroicons.x_mark
                                mini
                                class="h-4 w-4 text-red-500"
                                aria-label="no matching song found"
                              />
                            <% end %>
                          </.async_result>
                        <% end %>
                        <span class={[
                          @user_session && async_result && async_result.ok? &&
                            !async_result.result[:track_info] && "text-gray-500",
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
            <%= if @user_session do %>
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

  defp maybe_start_song_searches(socket, _setlist, %Setlistify.Scope{user_session: nil}), do: socket
  defp maybe_start_song_searches(socket, _setlist, nil), do: socket

  defp maybe_start_song_searches(socket, setlist, %Setlistify.Scope{user_session: user_session}) do
    setlist.sets
    |> Enum.with_index()
    |> Enum.flat_map(fn {set, set_index} ->
      set.songs
      |> Enum.with_index()
      |> Enum.map(fn {song, song_index} ->
        key = "song_#{set_index}_#{song_index}"
        {key, set_index, song_index, song}
      end)
    end)
    |> Enum.reduce(socket, fn {key, set_index, song_index, song}, acc_socket ->
      atom_key = String.to_atom(key)

      OpentelemetryPhoenixLiveViewProcessPropagator.LiveView.assign_async(
        acc_socket,
        atom_key,
        fn ->
          OpenTelemetry.Tracer.with_span "SetlistifyWeb.Setlists.ShowLive.search_song_async" do
            OpenTelemetry.Tracer.set_attributes([
              {"music.service", provider(user_session)},
              {"music.track", song.title},
              {"music.artist", setlist.artist},
              {"song.set_index", set_index},
              {"song.song_index", song_index}
            ])

            track_info =
              MusicService.API.search_for_track(user_session, setlist.artist, song.title)

            {:ok,
             %{
               atom_key => %{
                 track_info: track_info,
                 set_index: set_index,
                 song_index: song_index
               }
             }}
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
      Enum.with_index(set.songs, fn _song, song_index ->
        String.to_atom("song_#{set_index}_#{song_index}")
      end)
    end)
    |> Enum.flat_map(fn async_key ->
      case async_track_id(Map.get(assigns, async_key)) do
        nil -> []
        track_id -> [track_id]
      end
    end)
  end

  defp async_track_id(%Phoenix.LiveView.AsyncResult{ok?: true, result: result}) do
    case result[:track_info] do
      nil -> nil
      track_info -> track_info.track_id
    end
  end

  defp async_track_id(_), do: nil

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
