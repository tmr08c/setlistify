defmodule Setlistify.AppleMusic.API.ExternalClient do
  @behaviour Setlistify.AppleMusic.API

  require Logger
  require OpenTelemetry.Tracer

  alias Setlistify.AppleMusic.DeveloperTokenManager
  alias Setlistify.AppleMusic.UserSession

  defp client(%UserSession{user_token: user_token}) do
    developer_token = DeveloperTokenManager.get_token()

    default_opts = [
      base_url: "https://api.music.apple.com",
      headers: [
        {"Authorization", "Bearer #{developer_token}"},
        {"Music-User-Token", user_token}
      ]
    ]

    config_opts = Application.get_env(:setlistify, :apple_music_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  defp with_developer_token_refresh(user_session, request_fn, context) do
    req = client(user_session)

    case request_fn.(req) do
      {:ok, %{status: 401}} ->
        Logger.warning("401 during #{context}, regenerating developer token and retrying")

        OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.API.ExternalClient.with_developer_token_refresh" do
          DeveloperTokenManager.regenerate_token()
          new_req = client(user_session)

          case request_fn.(new_req) do
            {:ok, %{status: 401}} ->
              Logger.error("Unauthorized during #{context} for user_id #{user_session.user_id}")
              OpenTelemetry.Tracer.set_status(:error, "Unauthorized after token regeneration")
              {:error, :unauthorized}

            other ->
              OpenTelemetry.Tracer.set_status(:ok, "")
              other
          end
        end

      other ->
        other
    end
  end

  def build_user_session(user_token, storefront, user_id) do
    {:ok, %UserSession{user_token: user_token, storefront: storefront, user_id: user_id}}
  end

  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.API.ExternalClient.search_for_track" do
      request_fn = fn req ->
        Req.get(req,
          url: "/v1/catalog/#{user_session.storefront}/search",
          params: %{term: "#{artist} #{track}", types: "songs", limit: 1}
        )
      end

      case with_developer_token_refresh(user_session, request_fn, "track search") do
        {:ok, %{status: 200} = resp} ->
          songs =
            resp.body |> Map.get("results", %{}) |> Map.get("songs", %{}) |> Map.get("data", [])

          case List.first(songs) do
            nil ->
              Logger.warning("No search results", %{artist: artist, track: track})
              OpenTelemetry.Tracer.set_attributes([{"results.count", 0}])
              OpenTelemetry.Tracer.set_status(:ok, "")
              nil

            song ->
              OpenTelemetry.Tracer.set_attributes([
                {"results.count", length(songs)},
                {"track.id", song["id"]}
              ])

              OpenTelemetry.Tracer.set_status(:ok, "")
              %{track_id: song["id"]}
          end

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error

        {:ok, response} ->
          Logger.error("Unexpected response from Apple Music search: #{inspect(response)}")
          OpenTelemetry.Tracer.set_status(:error, "Unexpected response")
          nil
      end
    end
  rescue
    error ->
      Logger.error("Exception during Apple Music search: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      OpenTelemetry.Tracer.set_status(:error, "Exception: #{Exception.message(error)}")
      nil
  end

  def create_playlist(user_session, name, description) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.API.ExternalClient.create_playlist" do
      Logger.info("Creating playlist", %{name: name, user_id: user_session.user_id})

      request_fn = fn req ->
        Req.post(req,
          url: "/v1/me/library/playlists",
          json: %{attributes: %{name: name, description: description}}
        )
      end

      case with_developer_token_refresh(user_session, request_fn, "playlist creation") do
        {:ok, %{status: 201} = resp} ->
          playlist_id = resp.body |> Map.get("data", []) |> List.first() |> Map.fetch!("id")
          external_url = "https://music.apple.com/library/playlist/#{playlist_id}"

          OpenTelemetry.Tracer.set_attributes([
            {"playlist.id", playlist_id},
            {"playlist.url", external_url}
          ])

          OpenTelemetry.Tracer.set_status(:ok, "")

          Logger.info("Playlist created successfully", %{
            playlist_id: playlist_id,
            name: name
          })

          {:ok, %{id: playlist_id, external_url: external_url}}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error

        {:ok, response} ->
          Logger.error("Unexpected response creating playlist: #{inspect(response)}")

          OpenTelemetry.Tracer.set_status(
            :error,
            "Unexpected response: status #{response.status}"
          )

          {:error, :playlist_creation_failed}
      end
    end
  end

  def add_tracks_to_playlist(_, _, []), do: {:ok, :no_tracks}

  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.API.ExternalClient.add_tracks_to_playlist" do
      Logger.info("Adding tracks to playlist", %{
        playlist_id: playlist_id,
        track_count: length(tracks),
        user_id: user_session.user_id
      })

      track_data = Enum.map(tracks, &%{id: &1, type: "songs"})

      request_fn = fn req ->
        Req.post(req,
          url: "/v1/me/library/playlists/#{playlist_id}/tracks",
          json: %{data: track_data}
        )
      end

      case with_developer_token_refresh(user_session, request_fn, "adding tracks to playlist") do
        {:ok, %{status: 204}} ->
          Logger.info("Tracks added successfully", %{
            playlist_id: playlist_id,
            track_count: length(tracks)
          })

          OpenTelemetry.Tracer.set_status(:ok, "")
          {:ok, :tracks_added}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error

        {:ok, response} ->
          Logger.error("Failed to add tracks to playlist: #{inspect(response)}")
          OpenTelemetry.Tracer.set_status(:error, "Failed: status #{response.status}")
          {:error, :tracks_addition_failed}
      end
    end
  end
end
