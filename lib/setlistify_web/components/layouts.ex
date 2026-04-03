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

  embed_templates "layouts/*"

  defp user_display_name(%Setlistify.Spotify.UserSession{username: username}), do: username
  defp user_display_name(%Setlistify.AppleMusic.UserSession{}), do: "Apple Music"

  defp user_signed_in_label(%Setlistify.Spotify.UserSession{username: username}),
    do: "Signed in as #{username}"

  defp user_signed_in_label(%Setlistify.AppleMusic.UserSession{}), do: "Signed in with Apple Music"

  defp apple_music_developer_token do
    try do
      Setlistify.AppleMusic.DeveloperTokenManager.get_token()
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end
end
