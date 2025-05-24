defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  require Logger
  require OpenTelemetry.Tracer

  alias Setlistify.Spotify.UserSession
  alias Setlistify.Spotify.SessionManager

  defp client(%UserSession{access_token: token}, endpoint \\ "https://api.spotify.com/v1/") do
    Logger.debug("Current Spotify API client token: #{token}")
    default_opts = [base_url: endpoint, auth: {:bearer, token}]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  # Helper function to handle token refresh and retry logic
  defp with_token_refresh(user_session, request_fn, context) do
    # OpentelemetryReq will handle HTTP-level tracing, so we only need business logic spans
    req = client(user_session)

    case request_fn.(req) do
      {:ok, %{status: 401} = response} ->
        # Check if this is a token expiration issue
        authenticate_header =
          Enum.find_value(response.headers, fn {header, value} ->
            if String.downcase(header) == "www-authenticate", do: value
          end)

        # Handle both string and list formats
        authenticate_value =
          case authenticate_header do
            nil -> ""
            header when is_binary(header) -> header
            [header | _] when is_binary(header) -> header
            _ -> ""
          end

        if authenticate_header && String.contains?(authenticate_value, "invalid_token") do
          Logger.debug(
            "Token expired during #{context}, attempting to refresh for user_id: #{user_session.user_id}"
          )

          # Attempt to refresh the token
          case SessionManager.refresh_session(user_session.user_id) do
            {:ok, new_session} ->
              Logger.debug("Successfully refreshed token during #{context}, retrying request")
              # Create new client and retry the request
              new_req = client(new_session)
              request_fn.(new_req)

            {:error, reason} ->
              Logger.error(
                "Failed to refresh token during #{context} for user_id #{user_session.user_id}: #{inspect(reason)}"
              )

              {:error, :token_refresh_failed}
          end
        else
          # Non-token 401 error, just pass it through
          {:ok, response}
        end

      # Any other response passes through unchanged
      other ->
        other
    end
  end

  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "spotify.external_client.search_for_track" do
      request_fn = fn req ->
        Req.get(req,
          url: "/search",
          params: %{q: "artist:#{artist} track:#{track}", type: "track"}
        )
      end

      case with_token_refresh(user_session, request_fn, "track search") do
        {:ok, %{status: 200} = resp} ->
          items = resp.body |> Map.get("tracks", %{}) |> Map.get("items", [])

          result =
            case List.first(items) do
              nil ->
                Logger.warning("No search results", %{artist: artist, track: track})
                OpenTelemetry.Tracer.set_attribute("spotify.results.count", 0)
                nil

              track_info ->
                Logger.info("Found match", %{artist: artist, track: track})

                OpenTelemetry.Tracer.set_attributes([
                  {"spotify.results.count", length(items)},
                  {"spotify.track.uri", track_info["uri"]}
                ])

                %{uri: track_info["uri"], preview_url: track_info["preview_url"]}
            end

          OpenTelemetry.Tracer.set_status(:ok)
          result

        {:error, reason} = error ->
          Logger.error("Search failed", %{
            artist: artist,
            track: track,
            error: reason
          })

          OpenTelemetry.Tracer.set_status(:error, "Search failed: #{inspect(reason)}")
          error

        {:ok, %{status: 401} = response} ->
          Logger.error(
            "Unauthorized search request with user_id #{user_session.user_id}: #{inspect(response)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "Unauthorized")
          nil

        {:ok, response} ->
          Logger.error("Unexpected response from Spotify search: #{inspect(response)}")
          OpenTelemetry.Tracer.set_status(:error, "Unexpected response")
          nil
      end
    end
  rescue
    error ->
      Logger.error("Exception during Spotify search: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      OpenTelemetry.Tracer.set_status(:error, "Exception: #{Exception.message(error)}")
      nil
  end

  def create_playlist(user_session, name, description) do
    OpenTelemetry.Tracer.with_span "spotify.create_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "spotify"},
        {"spotify.operation", "create_playlist"},
        {"spotify.playlist.name", name},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      Logger.info("Creating playlist", %{
        name: name,
        user_id: user_session.user_id
      })

      request_fn = fn req ->
        Req.post(req,
          url: "/users/#{user_session.user_id}/playlists",
          json: %{
            name: name,
            description: description,
            public: false
          }
        )
      end

      case with_token_refresh(user_session, request_fn, "playlist creation") do
        {:ok, %{status: status} = resp} when status in [200, 201] ->
          playlist_id = Map.fetch!(resp.body, "id")
          external_url = resp.body |> Map.fetch!("external_urls") |> Map.fetch!("spotify")

          OpenTelemetry.Tracer.set_attributes([
            {"spotify.playlist.id", playlist_id},
            {"spotify.playlist.url", external_url}
          ])

          OpenTelemetry.Tracer.set_status(:ok)

          Logger.info("Playlist created successfully", %{
            playlist_id: playlist_id,
            name: name
          })

          {:ok, %{id: playlist_id, external_url: external_url}}

        {:ok, response} ->
          Logger.error("Unexpected response creating playlist: #{inspect(response)}")

          OpenTelemetry.Tracer.set_status(
            :error,
            "Unexpected response: status #{response.status}"
          )

          {:error, :playlist_creation_failed}

        {:error, reason} = error ->
          Logger.error("Failed to create playlist", %{
            name: name,
            error: reason
          })

          OpenTelemetry.Tracer.set_status(:error, "Creation failed: #{inspect(reason)}")
          error
      end
    end
  end

  def add_tracks_to_playlist(_, _, []), do: {:ok, :no_tracks}

  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    OpenTelemetry.Tracer.with_span "spotify.add_tracks_to_playlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "spotify"},
        {"spotify.operation", "add_tracks_to_playlist"},
        {"spotify.playlist.id", playlist_id},
        {"spotify.tracks.count", length(tracks)},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      Logger.info("Adding tracks to playlist", %{
        playlist_id: playlist_id,
        track_count: length(tracks),
        user_id: user_session.user_id
      })

      request_fn = fn req ->
        Req.post(req,
          url: "/playlists/#{playlist_id}/tracks",
          json: %{uris: tracks}
        )
      end

      case with_token_refresh(user_session, request_fn, "adding tracks to playlist") do
        {:ok, %{status: 201}} ->
          Logger.info("Tracks added successfully", %{
            playlist_id: playlist_id,
            track_count: length(tracks)
          })

          OpenTelemetry.Tracer.set_status(:ok)
          {:ok, :tracks_added}

        {:ok, response} ->
          Logger.error("Failed to add tracks to playlist: #{inspect(response)}")
          OpenTelemetry.Tracer.set_status(:error, "Failed: status #{response.status}")
          {:error, :tracks_addition_failed}

        {:error, reason} = error ->
          Logger.error("Failed to add tracks", %{
            playlist_id: playlist_id,
            error: reason
          })

          OpenTelemetry.Tracer.set_status(:error, "Addition failed: #{inspect(reason)}")
          error
      end
    end
  end

  def get_embed(url) do
    default_opts = [
      base_url: Application.get_env(:setlistify, :oembed_endpoint, "https://open.spotify.com")
    ]

    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    req =
      Req.new()
      |> OpentelemetryReq.attach()
      |> Req.merge(Keyword.merge(default_opts, config_opts))

    resp = Req.get(req, url: "/oembed?url=#{URI.encode_www_form(url)}")

    case resp do
      {:ok, %{status: 200} = resp} ->
        case resp.body do
          %{"html" => html} -> {:ok, html}
          _ -> {:error, :invalid_response}
        end

      _ ->
        {:error, :failed_to_fetch}
    end
  end

  def refresh_token(refresh_token) do
    OpenTelemetry.Tracer.with_span "spotify.oauth.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"oauth.provider", "spotify"},
        {"oauth.grant_type", "refresh_token"}
      ])

      client_id = Application.fetch_env!(:setlistify, :spotify_client_id)
      client_secret = Application.fetch_env!(:setlistify, :spotify_client_secret)

      default_opts = [base_url: "https://accounts.spotify.com/api/token"]
      config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

      req =
        Req.new()
        |> OpentelemetryReq.attach()
        |> Req.merge(Keyword.merge(default_opts, config_opts))

      result =
        Req.post(
          req,
          form: %{
            grant_type: "refresh_token",
            refresh_token: refresh_token,
            client_id: client_id,
            client_secret: client_secret
          }
        )

      case result do
        {:ok, %{status: 200, body: body}} ->
          Logger.info("Successfully refreshed token")
          OpenTelemetry.Tracer.set_status(:ok)

          {:ok,
           %{
             access_token: body["access_token"],
             refresh_token: body["refresh_token"] || refresh_token,
             expires_in: body["expires_in"]
           }}

        {:ok, %{status: status}} when status in [400, 401] ->
          Logger.error("Token refresh failed with status #{status}")
          OpenTelemetry.Tracer.set_status(:error, "Invalid token: status #{status}")
          {:error, :invalid_token}

        error ->
          Logger.error("Token refresh error: #{inspect(error)}")
          OpenTelemetry.Tracer.set_status(:error, "Refresh failed: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  def refresh_to_user_session(refresh_token) do
    case refresh_token(refresh_token) do
      {:ok, tokens} ->
        build_user_session_from_tokens(tokens)

      {:error, reason} ->
        Logger.error("Failed to refresh token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def exchange_code(code, redirect_uri) do
    OpenTelemetry.Tracer.with_span "spotify.oauth.exchange_code" do
      OpenTelemetry.Tracer.set_attributes([
        {"oauth.provider", "spotify"},
        {"oauth.redirect_uri", redirect_uri}
      ])

      client_id = Application.fetch_env!(:setlistify, :spotify_client_id)
      client_secret = Application.fetch_env!(:setlistify, :spotify_client_secret)

      # Instead of using auth header, include credentials in the request body as recommended by Spotify
      default_opts = [base_url: "https://accounts.spotify.com/api/token"]
      config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

      req =
        Req.new()
        |> OpentelemetryReq.attach()
        |> Req.merge(Keyword.merge(default_opts, config_opts))

      Logger.debug("Spotify token exchange request for URI: #{redirect_uri}")

      result =
        Req.post(
          req,
          form: %{
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri,
            client_id: client_id,
            client_secret: client_secret
          }
        )

      case result do
        {:ok, %{status: 200, body: body}} ->
          Logger.info("Successfully exchanged code for Spotify tokens")
          OpenTelemetry.Tracer.set_status(:ok)

          body |> Spotify.API.Types.TokenResponse.from_json!() |> build_user_session_from_tokens()

        {:ok, %{status: status, body: body}} when status in [400, 401] ->
          Logger.error(
            "Failed to exchange code: Invalid code. Status: #{status}, Error: #{inspect(body)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "Invalid code: status #{status}")

          {:error, :invalid_code}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Failed to exchange code. Status: #{status}, Error: #{inspect(body)}")
          OpenTelemetry.Tracer.set_status(:error, "Unexpected status: #{status}")
          {:error, {:unexpected_status, status, body}}

        {:error, error} ->
          Logger.error("Error exchanging code: #{inspect(error)}")
          OpenTelemetry.Tracer.set_status(:error, "Exchange failed: #{inspect(error)}")
          OpenTelemetry.Tracer.record_exception(error)
          {:error, error}
      end
    end
  end

  # Helper function to fetch user profile and create UserSession from tokens
  defp build_user_session_from_tokens(tokens) do
    OpenTelemetry.Tracer.with_span "spotify.fetch_user_profile" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "spotify"},
        {"spotify.operation", "fetch_user_profile"}
      ])

      default_opts = [
        base_url: "https://api.spotify.com/v1/",
        auth: {:bearer, tokens.access_token}
      ]

      config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

      req =
        Req.new()
        |> OpentelemetryReq.attach()
        |> Req.merge(Keyword.merge(default_opts, config_opts))

      profile_result = Req.get(req, url: "/me")

      case profile_result do
        {:ok, %{status: 200, body: profile}} ->
          user_id = profile["id"]
          username = profile["display_name"]

          OpenTelemetry.Tracer.set_attributes([
            {"user.id", user_id},
            {"user.name", username || ""},
            {"enduser.id", user_id}
          ])

          # Create and return UserSession struct
          user_session = %UserSession{
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_at: System.system_time(:second) + tokens.expires_in,
            user_id: user_id,
            username: username
          }

          Logger.info("User profile fetched successfully", %{user_id: user_id})
          OpenTelemetry.Tracer.set_status(:ok)
          {:ok, user_session}

        {:ok, %{status: status, body: body}} ->
          Logger.error(
            "Error fetching user profile. Received code #{status}. Response: #{inspect(body)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "Profile fetch failed: status #{status}")
          {:error, :failed_to_fetch_profile}

        {:error, error} ->
          Logger.error("Error fetching user profile: #{inspect(error)}")
          OpenTelemetry.Tracer.set_status(:error, "Profile fetch error: #{inspect(error)}")
          OpenTelemetry.Tracer.record_exception(error)
          {:error, :failed_to_fetch_profile}
      end
    end
  end
end
