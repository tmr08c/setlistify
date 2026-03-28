defmodule SetlistifyWeb.SignInLive do
  use SetlistifyWeb, :live_view

  def mount(params, _session, socket) do
    redirect_to = Map.get(params, "redirect_to", "/")
    {:ok, assign(socket, redirect_to: redirect_to)}
  end

  def render(assigns) do
    ~H"""
    <.section_container class="py-6 sm:py-10">
      <div class="max-w-md mx-auto px-4">
        <div class="text-center mb-8">
          <h1 class="text-2xl sm:text-3xl font-bold mb-2">Sign In</h1>
          <p class="text-gray-400">Choose a music service to continue</p>
        </div>

        <div class="space-y-4">
          <.link
            navigate={~p"/signin/spotify?redirect_to=#{@redirect_to}"}
            class={[
              "flex items-center justify-center w-full",
              "bg-emerald-500 text-black font-semibold",
              "px-6 py-4 rounded-xl",
              "hover:bg-emerald-400 transition-colors"
            ]}
          >
            <.icon name="hero-musical-note" class="mr-3" /> Sign in with Spotify
          </.link>

          <button
            type="button"
            disabled
            class={[
              "flex items-center justify-center w-full",
              "bg-gray-800 text-gray-500 font-semibold",
              "px-6 py-4 rounded-xl",
              "cursor-not-allowed"
            ]}
          >
            <.icon name="hero-musical-note" class="mr-3" /> Sign in with Apple Music
            <span class="ml-2 text-xs font-normal text-gray-600">(coming soon)</span>
          </button>
        </div>
      </div>
    </.section_container>
    """
  end
end
