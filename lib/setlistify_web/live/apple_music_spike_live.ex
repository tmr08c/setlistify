defmodule SetlistifyWeb.AppleMusicSpikeLive do
  use SetlistifyWeb, :live_view

  alias Setlistify.AppleMusic.DeveloperTokenManager

  def mount(_params, _session, socket) do
    {:ok, assign(socket, status: :idle, user_token: nil, storefront: nil, error: nil)}
  end

  def handle_event("connect", _params, socket) do
    {:noreply,
     socket
     |> assign(status: :authorizing)
     |> push_event("request_apple_music_auth", %{
       developer_token: DeveloperTokenManager.get_token()
     })}
  end

  def handle_event(
        "apple_music_authorized",
        %{"user_token" => user_token, "storefront" => storefront},
        socket
      ) do
    {:noreply,
     assign(socket, status: :authorized, user_token: user_token, storefront: storefront)}
  end

  def handle_event("apple_music_auth_failed", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, status: :failed, error: reason)}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8 max-w-xl mx-auto" id="apple-music-spike" phx-hook="AppleMusicAuth">
      <h1 class="text-2xl font-bold mb-6">Apple Music Spike</h1>

      <button
        :if={@status == :idle}
        phx-click="connect"
        class="px-4 py-2 bg-white text-black rounded font-semibold"
      >
        Connect Apple Music
      </button>

      <p :if={@status == :authorizing} class="text-gray-400">Authorizing…</p>

      <div :if={@status == :authorized} class="space-y-2 font-mono text-sm break-all">
        <p><span class="text-gray-400">storefront:</span> {@storefront}</p>
        <p><span class="text-gray-400">user_token:</span> {@user_token}</p>
      </div>

      <p :if={@status == :failed} class="text-red-400">Error: {@error}</p>
    </div>
    """
  end
end
