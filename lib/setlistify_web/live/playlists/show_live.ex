defmodule SetlistifyWeb.Playlists.ShowLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.Spotify

  def mount(_params, _session, socket) do
    {:ok, assign(socket, error: nil, playlist_href: nil)}
  end

  def handle_params(%{"provider" => "spotify", "url" => url}, _uri, socket) do
    case Spotify.API.get_embed(url) do
      {:ok, embed_html} ->
        {:noreply, assign(socket, playlist_href: url, embed_html: embed_html, error: nil)}

      {:error, _reason} ->
        {:noreply, assign(socket, playlist_href: url, error: "Failed to load Spotify embed")}
    end
  end

  def handle_params(%{"provider" => provider, "url" => _url}, _uri, socket) do
    {:noreply, assign(socket, :error, "Unsupported provider: #{provider}")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :error, "Missing required parameters")}
  end

  def render(assigns) do
    ~H"""
    <.section_container class="py-6 sm:py-10">
      <div class="max-w-4xl mx-auto">
        <div class="text-center mb-6 sm:mb-8">
          <h1 class="text-2xl sm:text-3xl md:text-4xl font-bold mb-4">
            <%= if @playlist_href do %>
              <span class="text-emerald-400">Playlist Created!</span>
            <% else %>
              <span class="text-red-400">Error Creating Playlist</span>
            <% end %>
          </h1>
        </div>

        <div class="bg-black/50 border border-gray-800 rounded-xl p-4 sm:p-6 md:p-8">
          <%= if @playlist_href do %>
            <div class="space-y-6">
              <div class="text-center mb-6">
                <p class="text-lg text-gray-300 mb-4">
                  Your playlist has been successfully created on Spotify!
                </p>
                <.link
                  href={@playlist_href}
                  target="_blank"
                  class={[
                    "inline-flex items-center justify-center",
                    "bg-emerald-500 text-black font-semibold",
                    "px-6 py-3 rounded-full",
                    "hover:bg-emerald-400 transition-colors"
                  ]}
                >
                  <.icon name="hero-musical-note" class="mr-2" /> Open in Spotify
                  <.icon name="hero-arrow-top-right-on-square" class="ml-2" />
                </.link>
              </div>

              <%= if @error do %>
                <div class="bg-red-900/20 border border-red-800 rounded-lg p-4">
                  <div class="flex items-center gap-3">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="h-5 w-5 text-red-500 flex-shrink-0"
                    />
                    <p class="text-red-300">{@error}</p>
                  </div>
                </div>
              <% else %>
                <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
                  <div class="[&>iframe]:rounded-lg [&>iframe]:w-full [&>iframe]:min-h-[380px]">
                    {raw(@embed_html)}
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="bg-red-900/20 border border-red-800 rounded-lg p-6">
              <div class="flex items-start gap-3">
                <.icon name="hero-x-circle" class="h-6 w-6 text-red-500 flex-shrink-0 mt-0.5" />
                <div>
                  <h2 class="text-lg font-semibold text-red-300 mb-2">Unable to create playlist</h2>
                  <p class="text-red-300">{@error}</p>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div class="mt-8 text-center">
          <.link
            navigate={~p"/"}
            class={[
              "inline-flex items-center text-gray-400",
              "hover:text-emerald-400 transition-colors"
            ]}
          >
            <.icon name="hero-arrow-left" class="mr-2" /> Back to Search
          </.link>
        </div>
      </div>
    </.section_container>
    """
  end
end
