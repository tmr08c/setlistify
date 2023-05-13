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
    <div>
      <div class="space-y-4">
        <%= if @playlist_href do %>
          <div>
            Playlist created! Access it <.link href={@playlist_href} target="_blank">here</.link>.
          </div>
          <%= if @error do %>
            <div class="text-red-600">{@error}</div>
          <% else %>
            {raw(@embed_html)}
          <% end %>
        <% else %>
          <div class="text-red-600">{@error}</div>
        <% end %>
      </div>
    </div>
    """
  end
end
