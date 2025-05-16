defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  require Logger
  alias Setlistify.Spotify.UserSession
  alias Setlistify.Spotify.SessionManager

  defp client(%UserSession{access_token: token}, endpoint \\ "https://api.spotify.com/v1/") do
    Logger.debug("Current Spotify API client token: #{token}")
    default_opts = [base_url: endpoint, auth: {:bearer, token}]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    Req.new(Keyword.merge(default_opts, config_opts))
  end

  def username(%UserSession{username: username}) do
    # Since we already have the username in the UserSession, just return it
    username
  end

  # Helper function to handle token refresh and retry logic
  defp with_token_refresh(user_session, request_fn, context) do
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
          case SessionManager.refresh_token(user_session.user_id) do
            {:ok, _new_token} ->
              Logger.debug("Successfully refreshed token during #{context}, retrying request")
              # Get the new session and retry ONCE
              case SessionManager.get_session(user_session.user_id) do
                {:ok, new_session} ->
                  # Create new client and retry the request
                  new_req = client(new_session)
                  request_fn.(new_req)

                _ ->
                  Logger.error("Failed to get new session during #{context}")
                  {:error, :session_refresh_failed}
              end

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
    request_fn = fn req ->
      Req.get(req,
        url: "/search",
        params: %{q: "artist:#{artist} track:#{track}", type: "track"}
      )
    end

    case with_token_refresh(user_session, request_fn, "track search") do
      {:ok, %{status: 200} = resp} ->
        items = resp.body |> Map.get("tracks", %{}) |> Map.get("items", [])

        with nil <- List.first(items) do
          Logger.warning("No search results for artist: #{artist}, track: #{track}")
          nil
        else
          track_info ->
            Logger.info("Found match for artist: #{artist}, track: #{track}")
            %{uri: track_info["uri"], preview_url: track_info["preview_url"]}
        end

      {:ok, %{status: 401} = response} ->
        Logger.error(
          "Unauthorized search request with user_id #{user_session.user_id}: #{inspect(response)}"
        )

        nil

      {:ok, response} ->
        Logger.error("Unexpected response from Spotify search: #{inspect(response)}")
        nil

      {:error, _reason} ->
        # Error already logged by with_token_refresh
        nil
    end
  rescue
    error ->
      Logger.error("Exception during Spotify search: #{inspect(error)}")
      nil
  end

  def create_playlist(user_session, name, description) do
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
        {:ok,
         %{
           id: Map.fetch!(resp.body, "id"),
           external_url: resp.body |> Map.fetch!("external_urls") |> Map.fetch!("spotify")
         }}

      {:ok, response} ->
        Logger.error("Unexpected response creating playlist: #{inspect(response)}")
        {:error, :playlist_creation_failed}

      {:error, _reason} = error ->
        # Error already logged by with_token_refresh
        error
    end
  end

  def add_tracks_to_playlist(_, _, []), do: {:ok, :no_tracks}

  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    request_fn = fn req ->
      Req.post(req,
        url: "/playlists/#{playlist_id}/tracks",
        json: %{uris: tracks}
      )
    end

    case with_token_refresh(user_session, request_fn, "adding tracks to playlist") do
      {:ok, %{status: 201}} ->
        {:ok, :tracks_added}

      {:ok, response} ->
        Logger.error("Failed to add tracks to playlist: #{inspect(response)}")
        {:error, :tracks_addition_failed}

      {:error, _reason} = error ->
        # Error already logged by with_token_refresh
        error
    end
  end

  def get_embed(url) do
    resp =
      [base_url: Application.get_env(:setlistify, :oembed_endpoint, "https://open.spotify.com")]
      |> Keyword.merge(Application.get_env(:setlistify, :spotify_req_options, []))
      |> Req.get(url: "/oembed?url=#{URI.encode_www_form(url)}")

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
    client_id = Application.fetch_env!(:setlistify, :spotify_client_id)
    client_secret = Application.fetch_env!(:setlistify, :spotify_client_secret)

    default_opts = [base_url: "https://accounts.spotify.com/api/token"]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    req = Req.new(Keyword.merge(default_opts, config_opts))

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
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"] || refresh_token,
           expires_in: body["expires_in"]
         }}

      {:ok, %{status: status}} when status in [400, 401] ->
        {:error, :invalid_token}

      error ->
        {:error, error}
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
    client_id = Application.fetch_env!(:setlistify, :spotify_client_id)
    client_secret = Application.fetch_env!(:setlistify, :spotify_client_secret)

    # Instead of using auth header, include credentials in the request body as recommended by Spotify
    default_opts = [base_url: "https://accounts.spotify.com/api/token"]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    req = Req.new(Keyword.merge(default_opts, config_opts))

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

        body |> Spotify.API.Types.TokenResponse.from_json!() |> build_user_session_from_tokens()

      {:ok, %{status: status, body: body}} when status in [400, 401] ->
        Logger.error(
          "Failed to exchange code: Invalid code. Status: #{status}, Error: #{inspect(body)}"
        )

        {:error, :invalid_code}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to exchange code. Status: #{status}, Error: #{inspect(body)}")
        {:error, {:unexpected_status, status, body}}

      {:error, error} ->
        Logger.error("Error exchanging code: #{inspect(error)}")
        {:error, error}
    end
  end

  # Helper function to fetch user profile and create UserSession from tokens
  defp build_user_session_from_tokens(tokens) do
    default_opts = [base_url: "https://api.spotify.com/v1/", auth: {:bearer, tokens.access_token}]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    req = Req.new(Keyword.merge(default_opts, config_opts))

    profile_result = Req.get(req, url: "/me")

    case profile_result do
      {:ok, %{status: 200, body: profile}} ->
        # Create and return UserSession struct
        user_session = %UserSession{
          access_token: tokens.access_token,
          refresh_token: tokens.refresh_token,
          expires_at: System.system_time(:second) + tokens.expires_in,
          user_id: profile["id"],
          username: profile["display_name"]
        }

        {:ok, user_session}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Error fetching user profile. Received code #{status}. Response: #{inspect(body)}"
        )

        {:error, :failed_to_fetch_profile}

      {:error, error} ->
        Logger.error("Error fetching user profile: #{inspect(error)}")
        {:error, :failed_to_fetch_profile}
    end
  end
end
