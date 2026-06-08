defmodule SetlistifyWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use SetlistifyWeb, :controller` and
  `use SetlistifyWeb, :live_view`.
  """
  use SetlistifyWeb, :html
  use Gettext, backend: SetlistifyWeb.Gettext

  alias Setlistify.Scope
  alias Setlistify.Spotify.UserSession

  embed_templates "layouts/*"

  defp user_display_name(%UserSession{username: username}), do: username
  defp user_display_name(%Setlistify.AppleMusic.UserSession{}), do: "Apple Music"

  defp user_signed_in_label(%UserSession{username: username}), do: "Signed in as #{username}"

  defp user_signed_in_label(%Setlistify.AppleMusic.UserSession{}), do: "Signed in with Apple Music"

  defp needs_music_kit?(%Setlistify.AppleMusic.UserSession{}), do: true
  defp needs_music_kit?(nil), do: apple_music_developer_token() != nil
  defp needs_music_kit?(_), do: false

  defp sign_out_hook(%Setlistify.AppleMusic.UserSession{}), do: "AppleMusicSignOut"
  defp sign_out_hook(_), do: nil

  defp sign_out_developer_token(%Setlistify.AppleMusic.UserSession{}), do: apple_music_developer_token()

  defp sign_out_developer_token(_), do: nil

  defp apple_music_developer_token do
    Setlistify.AppleMusic.DeveloperTokenManager.get_token()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end
end
