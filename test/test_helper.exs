Hammox.defmock(Setlistify.SetlistFm.API.MockClient, for: Setlistify.SetlistFm.API)
Application.put_env(:setlistify, :setlistfm_api_client, Setlistify.SetlistFm.API.MockClient)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Setlistify.Repo, :manual)
