defmodule Setlistify.Tidal.API.ExternalClient do
  @moduledoc false
  @behaviour Setlistify.Tidal.API

  alias Setlistify.Tidal.RequestThrottle
  alias Setlistify.Tidal.SessionManager
  alias Setlistify.Tidal.UserSession

  require Logger
  require OpenTelemetry.Tracer

  @catalog_base_url "https://openapi.tidal.com/v2/"
  @token_base_url "https://auth.tidal.com/v1/oauth2/token"
  @playlist_url_base "https://tidal.com/playlist/"
  @json_api_content_type "application/vnd.api+json"
  @tracks_per_request 20

  defp client(%UserSession{access_token: token}) do
    default_opts = [
      base_url: @catalog_base_url,
      auth: {:bearer, token},
      headers: [
        {"accept", @json_api_content_type},
        {"content-type", @json_api_content_type}
      ]
    ]

    config_opts = Application.get_env(:setlistify, :tidal_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  defp token_client do
    default_opts = [base_url: @token_base_url]
    config_opts = Application.get_env(:setlistify, :tidal_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach()
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  # Every Tidal HTTP call goes through the RequestThrottle semaphore: Tidal's
  # measured burst capacity is only ~8 requests (see ADR-004 §3), so calls
  # above the cap queue instead of firing-and-429ing.
  defp throttled_request(request_fn, req) do
    RequestThrottle.with_slot(fn -> request_fn.(req) end)
  end

  defp with_token_refresh(user_session, request_fn, context) do
    req = client(user_session)

    case throttled_request(request_fn, req) do
      {:ok, %{status: 401}} ->
        refresh_and_retry(user_session, request_fn, context)

      other ->
        handle_rate_limit(other)
    end
  end

  defp refresh_and_retry(user_session, request_fn, context) do
    Logger.debug("Token expired during #{context}, attempting to refresh for user_id: #{user_session.user_id}")

    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.with_token_refresh" do
      case SessionManager.refresh_session(user_session.user_id) do
        {:ok, new_session} ->
          Logger.debug("Successfully refreshed token during #{context}, retrying request")
          new_req = client(new_session)
          handle_rate_limit(throttled_request(request_fn, new_req))

        {:error, reason} ->
          Logger.error(
            "Failed to refresh token during #{context} for user_id #{user_session.user_id}: #{inspect(reason)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "Token refresh failed: #{inspect(reason)}")

          {:error, :token_refresh_failed}
      end
    end
  end

  # 429s that occur despite the throttle (e.g. multiple users sharing the app
  # credential) surface as `{:error, {:rate_limited, retry_after}}` — recorded
  # with semconv HTTP attributes only, never a `tidal.*` namespace.
  defp handle_rate_limit({:ok, %{status: 429} = response}) do
    retry_after = retry_after_seconds(response)

    OpenTelemetry.Tracer.set_attributes([{"http.status_code", 429}])

    OpenTelemetry.Tracer.add_event("http.rate_limited", [
      {"http.response.header.retry_after", retry_after || ""}
    ])

    Logger.warning("Tidal rate limited request", %{retry_after: retry_after})

    {:error, {:rate_limited, retry_after}}
  end

  defp handle_rate_limit(other), do: other

  defp retry_after_seconds(response) do
    response.headers
    |> Enum.find_value(fn {header, value} ->
      if String.downcase(header) == "retry-after", do: value
    end)
    |> case do
      [value | _] when is_binary(value) -> parse_retry_after(value)
      value when is_binary(value) -> parse_retry_after(value)
      _ -> nil
    end
  end

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end

  def search_for_track(user_session, artist, track, cover_artist \\ nil) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.search_for_track" do
      case do_search_for_track(user_session, artist, track) do
        {:ok, %{track_id: _} = result} ->
          result

        {:ok, :no_match} when is_binary(cover_artist) ->
          OpenTelemetry.Tracer.set_attributes([{"search.fallback", "cover_artist"}])

          case do_search_for_track(user_session, cover_artist, track) do
            {:ok, %{track_id: _} = result} -> result
            {:ok, :no_match} -> nil
            {:error, _} = error -> error
          end

        {:ok, :no_match} ->
          nil

        {:error, _} = error ->
          error
      end
    end
  rescue
    error ->
      Logger.error("Exception during Tidal search: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      OpenTelemetry.Tracer.set_status(:error, "Exception: #{Exception.message(error)}")
      nil
  end

  defp do_search_for_track(user_session, artist, track) do
    # Tidal's search endpoint takes the query as a path segment, not a query
    # param, so it must be URL-encoded strictly (spaces as %20, not +).
    query = URI.encode(artist <> " " <> track, &URI.char_unreserved?/1)

    request_fn = fn req ->
      Req.get(req,
        url: "/searchResults/#{query}",
        params: %{countryCode: user_session.country_code, include: "tracks,tracks.artists"}
      )
    end

    case with_token_refresh(user_session, request_fn, "track search") do
      {:ok, %{status: 200} = resp} ->
        resp.body
        |> first_track_entry()
        |> evaluate_search_result(resp.body, artist, track)

      {:error, _} = error ->
        error

      {:ok, %{status: 401} = response} ->
        Logger.error("Unauthorized search request with user_id #{user_session.user_id}: #{inspect(response)}")

        {:error, :unauthorized}

      {:ok, response} ->
        Logger.error("Unexpected response from Tidal search: #{inspect(response)}")
        {:error, :unexpected_response}
    end
  end

  # The search result's tracks arrive as ordered {type, id} references under
  # data.relationships.tracks.data, with the full track resources in the
  # flat top-level `included` array.
  defp first_track_entry(body) do
    case get_in(body, ["data", "relationships", "tracks", "data"]) do
      [%{"type" => type, "id" => id} | _] -> extract_included(body, type, id)
      _ -> nil
    end
  end

  defp evaluate_search_result(nil, _body, artist, track) do
    Logger.warning("No search results", %{artist: artist, track: track})

    OpenTelemetry.Tracer.set_attributes([{"search.outcome", "no_results"}])
    {:ok, :no_match}
  end

  defp evaluate_search_result(track_entry, body, artist, track) do
    result_artists =
      track_entry
      |> get_in(["relationships", "artists", "data"])
      |> List.wrap()
      |> Enum.map(&resolve_artist_name(body, &1))

    if Enum.any?(result_artists, &artist_match?(artist, &1)) do
      Logger.info("Found match", %{artist: artist, track: track})

      OpenTelemetry.Tracer.set_attributes([
        {"track.id", track_entry["id"]},
        {"search.outcome", "match"}
      ])

      {:ok, %{track_id: track_entry["id"]}}
    else
      Logger.warning("Rejected search result: artist mismatch", %{
        queried_artist: artist,
        returned_artists: result_artists,
        track: track
      })

      OpenTelemetry.Tracer.set_attributes([{"search.outcome", "rejected_artist_mismatch"}])

      OpenTelemetry.Tracer.add_event("search.result_rejected", [
        {"reason", "artist_mismatch"},
        {"queried_artist", artist},
        {"returned_artists", Enum.map_join(result_artists, ", ", &(&1 || ""))},
        {"track", track}
      ])

      {:ok, :no_match}
    end
  end

  # Resolves a {type, id} relationships reference against the top-level
  # included list. The included array is flat across all search-result tracks'
  # relationships, so always resolve by {type, id} lookup, never by index.
  defp extract_included(%{"included" => included}, type, id) when is_list(included) do
    Enum.find(included, fn entry -> entry["type"] == type && entry["id"] == id end)
  end

  defp extract_included(_body, _type, _id), do: nil

  # A reference that resolves to nothing in `included` yields nil, which
  # artist_match?/2 treats as a mismatch — falling into the cover-fallback path.
  defp resolve_artist_name(body, %{"type" => type, "id" => id}) do
    case extract_included(body, type, id) do
      %{"attributes" => %{"name" => name}} -> name
      _ -> nil
    end
  end

  defp resolve_artist_name(_body, _ref), do: nil

  defp artist_match?(_queried, nil), do: false

  defp artist_match?(queried, returned) do
    String.equivalent?(normalize_artist(queried), normalize_artist(returned))
  end

  defp normalize_artist(name), do: name |> String.downcase() |> String.trim()

  def create_playlist(user_session, name, description) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.create_playlist" do
      Logger.info("Creating playlist", %{
        name: name,
        user_id: user_session.user_id
      })

      request_fn = fn req ->
        Req.post(req,
          url: "/playlists",
          params: %{countryCode: user_session.country_code},
          headers: [{"idempotency-key", idempotency_key([user_session.user_id, name, description])}],
          json: %{
            data: %{
              type: "playlists",
              attributes: %{
                name: name,
                description: description,
                # UNLISTED (owner-only) rather than PUBLIC; Tidal rejects
                # "PRIVATE" outright. See ADR-004 §4.
                accessType: "UNLISTED"
              }
            }
          }
        )
      end

      case with_token_refresh(user_session, request_fn, "playlist creation") do
        {:ok, %{status: 201} = resp} ->
          playlist_id = resp.body |> Map.fetch!("data") |> Map.fetch!("id")
          external_url = @playlist_url_base <> playlist_id

          OpenTelemetry.Tracer.set_attributes([
            {"playlist.id", playlist_id},
            {"playlist.url", external_url}
          ])

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
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error
      end
    end
  end

  def add_tracks_to_playlist(_, _, []), do: {:ok, :no_tracks}

  def add_tracks_to_playlist(user_session, playlist_id, tracks) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.add_tracks_to_playlist" do
      Logger.info("Adding tracks to playlist", %{
        playlist_id: playlist_id,
        track_count: length(tracks),
        user_id: user_session.user_id
      })

      result =
        tracks
        |> Enum.chunk_every(@tracks_per_request)
        |> Enum.reduce_while(:ok, fn chunk, :ok ->
          case add_track_chunk(user_session, playlist_id, chunk) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end
        end)

      case result do
        :ok ->
          Logger.info("Tracks added successfully", %{
            playlist_id: playlist_id,
            track_count: length(tracks)
          })

          {:ok, :tracks_added}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error
      end
    end
  end

  defp add_track_chunk(user_session, playlist_id, chunk) do
    request_fn = fn req ->
      Req.post(req,
        url: "/playlists/#{playlist_id}/relationships/items",
        params: %{countryCode: user_session.country_code},
        headers: [{"idempotency-key", idempotency_key([playlist_id | chunk])}],
        # No meta.positionBefore: it's a no-op for new appends, and natural
        # append-to-end is exactly what we want for setlist-derived playlists.
        json: %{data: Enum.map(chunk, &%{id: &1, type: "tracks"})}
      )
    end

    case with_token_refresh(user_session, request_fn, "adding tracks to playlist") do
      {:ok, %{status: status}} when status in [200, 201, 204] ->
        :ok

      {:ok, response} ->
        Logger.error("Failed to add tracks to playlist: #{inspect(response)}")
        {:error, :tracks_addition_failed}

      {:error, _} = error ->
        error
    end
  end

  # A deterministic Idempotency-Key so retries of the same logical operation
  # (same user + playlist name + description, or same playlist + track chunk)
  # dedupe server-side instead of creating duplicates. Colliding across two
  # genuinely identical requests is the behavior we want — duplicate playlists
  # from retried creates are exactly the bug idempotency keys exist to prevent.
  defp idempotency_key(parts) do
    :sha256
    |> :crypto.hash(Enum.intersperse(parts, "\n"))
    |> Base.encode16(case: :lower)
  end

  def refresh_token(refresh_token) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"oauth.provider", "tidal"},
        {"oauth.grant_type", "refresh_token"}
      ])

      client_id = Application.fetch_env!(:setlistify, :tidal_client_id)
      client_secret = Application.fetch_env!(:setlistify, :tidal_client_secret)

      result =
        throttled_request(
          fn req ->
            Req.post(req,
              form: %{
                grant_type: "refresh_token",
                refresh_token: refresh_token,
                client_id: client_id,
                client_secret: client_secret
              }
            )
          end,
          token_client()
        )

      case result do
        {:ok, %{status: 200, body: body}} ->
          Logger.info("Successfully refreshed Tidal token")

          # Tidal does NOT rotate refresh tokens — the response carries no
          # refresh_token field, so callers keep the one they already hold.
          {:ok,
           %{
             access_token: Map.fetch!(body, "access_token"),
             expires_in: Map.fetch!(body, "expires_in")
           }}

        {:ok, %{status: status}} when status in [400, 401] ->
          Logger.error("Tidal token refresh failed with status #{status}")
          OpenTelemetry.Tracer.set_status(:error, "Invalid token: status #{status}")
          {:error, :invalid_token}

        error ->
          Logger.error("Tidal token refresh error: #{inspect(error)}")
          OpenTelemetry.Tracer.set_status(:error, "Refresh failed: #{inspect(error)}")
          {:error, :refresh_failed}
      end
    end
  end

  def refresh_to_user_session(refresh_token) do
    case refresh_token(refresh_token) do
      {:ok, tokens} ->
        # Tidal doesn't rotate refresh tokens, so the new session keeps the
        # refresh token we already hold.
        build_user_session_from_tokens(tokens.access_token, refresh_token, tokens.expires_in)

      {:error, reason} = error ->
        Logger.error("Failed to refresh Tidal token: #{inspect(reason)}")
        error
    end
  end

  def exchange_code(code, redirect_uri, code_verifier) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.exchange_code" do
      OpenTelemetry.Tracer.set_attributes([
        {"oauth.provider", "tidal"},
        {"oauth.redirect_uri", redirect_uri}
      ])

      client_id = Application.fetch_env!(:setlistify, :tidal_client_id)
      client_secret = Application.fetch_env!(:setlistify, :tidal_client_secret)

      result =
        throttled_request(
          fn req ->
            Req.post(req,
              form: %{
                grant_type: "authorization_code",
                code: code,
                redirect_uri: redirect_uri,
                client_id: client_id,
                client_secret: client_secret,
                # Tidal (OAuth 2.1) mandates PKCE for all clients, even
                # confidential ones that also send a client_secret.
                code_verifier: code_verifier
              }
            )
          end,
          token_client()
        )

      case result do
        {:ok, %{status: 200, body: body}} ->
          Logger.info("Successfully exchanged code for Tidal tokens")

          build_user_session_from_tokens(
            Map.fetch!(body, "access_token"),
            Map.fetch!(body, "refresh_token"),
            Map.fetch!(body, "expires_in")
          )

        {:ok, %{status: status, body: body}} when status in [400, 401] ->
          Logger.error("Failed to exchange code: Invalid code. Status: #{status}, Error: #{inspect(body)}")

          OpenTelemetry.Tracer.set_status(:error, "Invalid code: status #{status}")

          {:error, :invalid_code}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Failed to exchange code. Status: #{status}, Error: #{inspect(body)}")
          OpenTelemetry.Tracer.set_status(:error, "Unexpected status: #{status}")
          {:error, {:unexpected_status, status, body}}

        {:error, error} ->
          Logger.error("Error exchanging code: #{inspect(error)}")
          OpenTelemetry.Tracer.set_status(:error, "Exchange failed: #{inspect(error)}")
          {:error, :exchange_failed}
      end
    end
  end

  # DELIBERATE NON-STANDARD: we treat Tidal's access-token JWT internals as a
  # stable interface. The OAuth spec says treat access tokens as opaque, but
  # deriving user_id/country_code from the `uid`/`cc` claims saves a network
  # round-trip at sign-in (verified against /v2/users/me in the Phase 0 spike).
  # If Tidal ever rotates these claim names or moves to opaque tokens, switch
  # back to a GET /v2/users/me call — its response shape is documented in
  # ADR-004 §1 and the issue #137 findings. Map.fetch! is intentional: a
  # missing claim must blow up sign-in loudly, not silently corrupt a session.
  defp build_user_session_from_tokens(access_token, refresh_token, expires_in) do
    claims = decode_jwt_payload!(access_token)

    {:ok,
     %UserSession{
       access_token: access_token,
       refresh_token: refresh_token,
       expires_at: System.system_time(:second) + expires_in,
       user_id: claims |> Map.fetch!("uid") |> to_string(),
       country_code: Map.fetch!(claims, "cc")
     }}
  end

  # Decodes the payload segment of a JWT without verifying the signature — we
  # aren't validating someone else's token, this one came straight from Tidal
  # in response to our own token request.
  defp decode_jwt_payload!(access_token) do
    [_header, payload, _signature] = String.split(access_token, ".")

    payload
    |> Base.url_decode64!(padding: false)
    |> JSON.decode!()
  end
end
