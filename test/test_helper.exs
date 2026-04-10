alias Setlistify.SetlistFm.API.MockClient

Hammox.defmock(MockClient, for: Setlistify.SetlistFm.API)
Application.put_env(:setlistify, :setlistfm_api_client, MockClient)

Hammox.defmock(Setlistify.Spotify.API.MockClient, for: Setlistify.Spotify.API)
Application.put_env(:setlistify, :spotify_api_client, Setlistify.Spotify.API.MockClient)

Hammox.defmock(Setlistify.AppleMusic.API.MockClient, for: Setlistify.AppleMusic.API)
Application.put_env(:setlistify, :apple_music_api_client, Setlistify.AppleMusic.API.MockClient)

ExUnit.start()
