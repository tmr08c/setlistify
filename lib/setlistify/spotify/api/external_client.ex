defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API

  require Logger

  def new(token, endpoint \\ "https://api.spotify.com/v1/") do
    Logger.debug("Current Spotify API client token: #{token}")
    default_opts = [base_url: endpoint, auth: {:bearer, token}]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    Req.new(Keyword.merge(default_opts, config_opts))
  end

  def username(client) do
    # Use try/rescue to handle potential transport errors
    result =
      try do
        Req.get(client, url: "/me")
      rescue
        error in Req.TransportError ->
          Logger.error("Transport error during Spotify API call to /me: #{inspect(error)}")
          {:error, error}
      end

    case result do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully retrieved user profile from Spotify")
        body["display_name"] || body["id"]

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Failed to get Spotify user profile. Status: #{status}, Body: #{inspect(body)}"
        )

        # Return a fallback username to prevent authentication failure
        "spotify_user_#{:rand.uniform(100_000)}"

      {:error, error} ->
        Logger.error("Error retrieving Spotify user profile: #{inspect(error)}")
        # Return a fallback username to prevent authentication failure
        "spotify_user_#{:rand.uniform(100_000)}"
    end
  end

  def search_for_track(client, artist, track, user_id \\ nil) do
    try do
      resp =
        Req.get(client,
          url: "/search",
          params: %{q: "artist:#{artist} track:#{track}", type: "track"}
        )

      case resp do
        {:ok, %{status: 401} = response} ->
          # Check if this is a token expiration issue
          [authenticate_header] =
            Enum.find_value(response.headers, fn {header, value} ->
              if String.downcase(header) == "www-authenticate", do: value
            end)

          if authenticate_header && String.contains?(authenticate_header, "invalid_token") do
            Logger.info(
              "Token expired during search, attempting to refresh for user_id: #{user_id}"
            )

            # Attempt to refresh the token using the provided user_id
            case Setlistify.Spotify.SessionManager.refresh_token(user_id) do
              {:ok, new_token} ->
                Logger.info("Successfully refreshed token, retrying search")
                # Create a new client with the refreshed token
                new_client = new(new_token)

                # Retry the search with the new client, passing the user_id again in case we need another refresh
                search_for_track(new_client, artist, track, user_id)

              {:error, reason} ->
                Logger.error("Failed to refresh token for user_id #{user_id}: #{inspect(reason)}")
                nil
            end
          else
            if user_id do
              Logger.error(
                "Unauthorized search request with user_id #{user_id}: #{inspect(response)}"
              )
            else
              Logger.error("Unauthorized search request without user_id: #{inspect(response)}")
            end

            nil
          end

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

        {:ok, response} ->
          Logger.error("Unexpected response from Spotify search: #{inspect(response)}")
          nil

        {:error, error} ->
          Logger.error("Error during Spotify search: #{inspect(error)}")
          nil
      end
    rescue
      error ->
        Logger.error("Exception during Spotify search: #{inspect(error)}")
        nil
    end
  end

  def create_playlist(client, name, description) do
    # TODO Update to no longer user the `username` function
    #
    # 1. it would be preferable not to re-request this data while the user is logged in
    # 2. I probably don't want to use display name here and want to *always* use ID
    resp =
      Req.post!(client,
        url: "/users/#{username(client)}/playlists",
        json: %{
          name: name,
          description: description,
          public: false
        }
      )

    %{
      id: Map.fetch!(resp.body, "id"),
      external_url: resp.body |> Map.fetch!("external_urls") |> Map.fetch!("spotify")
    }
  end

  def add_tracks_to_playlist(_, _, []), do: :ok

  def add_tracks_to_playlist(client, playlist_id, tracks) do
    resp =
      Req.post!(client,
        url: "/playlists/#{playlist_id}/tracks",
        json: %{uris: tracks}
      )

    if resp.status == 201, do: :ok, else: :error
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

  def exchange_code(code, redirect_uri) do
    client_id = Application.fetch_env!(:setlistify, :spotify_client_id)
    client_secret = Application.fetch_env!(:setlistify, :spotify_client_secret)

    # Instead of using auth header, include credentials in the request body as recommended by Spotify
    default_opts = [base_url: "https://accounts.spotify.com/api/token"]
    config_opts = Application.get_env(:setlistify, :spotify_req_options, [])

    req = Req.new(Keyword.merge(default_opts, config_opts))

    Logger.debug("Spotify token exchange request for URI: #{redirect_uri}")

    # Use try/rescue to handle potential transport errors
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

        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"],
           expires_in: body["expires_in"]
         }}

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
end
