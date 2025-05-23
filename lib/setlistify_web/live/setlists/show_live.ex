defmodule SetlistifyWeb.Setlists.ShowLive do
  use SetlistifyWeb, :live_view

  require OpenTelemetry.Tracer

  alias Setlistify.{SetlistFm, Spotify}

  def mount(%{"id" => id}, _session, socket) do
    setlist = SetlistFm.API.get_setlist(id)
    user_session = socket.assigns[:user_session]

    setlist =
      if user_session do
        # Get the current context to propagate to the background process
        ctx = OpenTelemetry.Ctx.get_current()
        current_span = OpenTelemetry.Tracer.current_span_ctx(ctx)

        # Map context to something that can be sent between processes
        # ctx_map = OpenTelemetry.Propagator.text_map_injector().inject(ctx, %{})

        sets =
          setlist.sets
          |> Enum.map(fn set ->
            # TODO: The workflow of updating UserSession after a refresh (see
            # SetlistifyWeb.handle_info) probably won't work with this pattern
            # because the spawned tasks won't receive the message.
            songs =
              Task.async_stream(set.songs, fn song ->
                spotify_info =
                  Spotify.API.search_for_track(
                    user_session,
                    setlist.artist,
                    song.title,
                    {ctx, current_span}
                  )

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
       venue_location: setlist.venue.location,
       date: setlist.date,
       redirect_to: "/setlist/#{id}"
     )}
  end

  def handle_event("create_playlist", _params, socket) do
    user_session = socket.assigns.user_session

    if user_session do
      name = "#{socket.assigns.artist} @ #{socket.assigns.venue_name} (#{socket.assigns.date})"

      description =
        "Created by Setlistify: #{socket.assigns.artist} at #{socket.assigns.venue_name} on #{socket.assigns.date}"

      case Spotify.API.create_playlist(user_session, name, description) do
        {:ok, %{id: playlist_id, external_url: external_url}} ->
          # Build a flatlist of track Ids from our setlist
          track_ids =
            Enum.flat_map(socket.assigns.sets, fn set ->
              set.songs
              |> Enum.filter(&(Map.has_key?(&1, :spotify_info) and not is_nil(&1.spotify_info)))
              |> Enum.map(& &1.spotify_info.uri)
            end)

          case Spotify.API.add_tracks_to_playlist(user_session, playlist_id, track_ids) do
            {:ok, _} ->
              {:noreply,
               push_navigate(socket, to: ~p"/playlists?provider=spotify&url=#{external_url}")}

            {:error, reason} ->
              {:noreply,
               put_flash(socket, :error, "Failed to add tracks to playlist: #{inspect(reason)}")}
          end

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create playlist: #{inspect(reason)}")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Unable to access Spotify session. Please log in again.")}
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
                  <%= for song <- set.songs do %>
                    <li>
                      <span class="inline-flex items-center gap-2">
                        <Heroicons.check
                          :if={@user_session && song[:spotify_info] != nil}
                          mini
                          class="h-4 w-4 text-emerald-500"
                          aria-label="found matching song"
                        />
                        <Heroicons.x_mark
                          :if={@user_session && song[:spotify_info] == nil}
                          mini
                          class="h-4 w-4 text-red-500"
                          aria-label="no matching song found"
                        />
                        <span class={[
                          @user_session && song[:spotify_info] == nil && "text-gray-500",
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
                  Ready to create your playlist? We'll add all available tracks to your Spotify account.
                </p>
                <.button type="button" phx-click="create_playlist" class="w-full sm:w-auto">
                  <.icon name="hero-musical-note" class="mr-2" /> Create Spotify Playlist
                </.button>
              </div>
            <% else %>
              <div class="space-y-4">
                <p class="text-gray-400 mb-4">
                  Sign in to create a Spotify playlist from this setlist
                </p>
                <.link
                  navigate={~p"/signin/spotify?redirect_to=#{@redirect_to}"}
                  class={[
                    "inline-flex items-center justify-center",
                    "bg-emerald-500 text-black font-semibold",
                    "px-6 py-3 rounded-full",
                    "hover:bg-emerald-400 transition-colors"
                  ]}
                >
                  <.icon name="hero-arrow-right-end-on-rectangle" class="mr-2" /> Sign in with Spotify
                </.link>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </.section_container>
    """
  end

  defp set_name(%{encore: encore}) when is_number(encore), do: "Encore #{encore}"
  defp set_name(%{name: nil}), do: "Unnamed Setlist"

  defp set_name(%{name: name}) do
    # Remove trailing colon if present for consistency with encore format
    String.trim_trailing(name, ":")
  end

  defp format_location(%{city: city, state: state, country: country}) do
    [city, state, country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end
end
