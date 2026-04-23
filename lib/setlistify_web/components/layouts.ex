defmodule SetlistifyWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is an explicit function
  component called directly from LiveView templates.
  """
  use SetlistifyWeb, :html

  alias Setlistify.Spotify.UserSession

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :user_session, :any, default: nil
  attr :redirect_to, :string, default: nil
  attr :apple_music_trigger, :boolean, default: false
  attr :apple_music_user_token, :string, default: nil
  attr :apple_music_storefront, :string, default: nil

  slot :inner_block, required: true

  def app(assigns)

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
end
