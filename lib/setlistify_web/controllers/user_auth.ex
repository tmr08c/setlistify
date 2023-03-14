defmodule SetlistifyWeb.UserAuth do
  def on_mount(:default, _params, session, socket) do
    case session do
      %{"access_token" => access_token, "account_name" => account_name} ->
        account = %Setlistify.MusicAccount{access_token: access_token, username: account_name}
        {:cont, Phoenix.Component.assign_new(socket, :music_account, fn -> account end)}

      %{} ->
        {:cont, Phoenix.Component.assign(socket, :music_account, nil)}
    end
  end
end
