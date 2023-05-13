Hammox.defmock(Setlistify.SetlistFm.API.MockClient, for: Setlistify.SetlistFm.API)
Application.put_env(:setlistify, :setlistfm_api_client, Setlistify.SetlistFm.API.MockClient)

Hammox.defmock(Setlistify.Spotify.API.MockClient, for: Setlistify.Spotify.API)
Application.put_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.MockClient)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Setlistify.Repo, :manual)
