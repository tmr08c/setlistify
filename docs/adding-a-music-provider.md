# Adding a New Music Provider

This guide walks through adding a new music provider (e.g. Tidal) to Setlistify. Follow
these steps in order — each section references the existing Spotify and Apple Music
implementations so you can model your code directly on them.

The guide uses "Tidal" as the running example. Replace it with your actual provider name
throughout.

---

## Overview of what you're building

A provider lives under `lib/setlistify/<provider>/` and consists of:

- `UserSession` — a plain struct holding the authenticated user's credentials
- `SessionManager` — a GenServer that stores the session and (for OAuth providers)
  auto-refreshes the token
- `SessionSupervisor` — a thin wrapper that starts/stops `SessionManager` children
  under the shared `DynamicSupervisor`
- `API` — the public interface module (defines callbacks + delegates to `impl/0`)
- `API.ExternalClient` — the real HTTP implementation
- `DeveloperTokenManager` — only needed if the provider uses a signed app-level token
  (like Apple Music's JWTs); skip for standard OAuth flows

You will also touch:
- `Setlistify.UserSessionManager` — the provider-agnostic dispatch layer
- `Setlistify.MusicService.API` — the provider-agnostic facade used by LiveViews
- `Setlistify.Auth.TokenSalts` — a constant for the Phoenix.Token salt
- `SetlistifyWeb.Plugs.RestoreTidalToken` — session restoration plug
- `SetlistifyWeb.Router` — plug pipeline and OAuth routes
- `SetlistifyWeb.OAuthCallbackController` — callback handler and sign-out
- `SetlistifyWeb.Auth.LiveHooks` — provider key mapping for LiveView auth
- `SetlistifyWeb.UserAuth` — session fields preserved across login
- `Setlistify.Application` — Cachex cache and optional DeveloperTokenManager
- `test/test_helper.exs` — mock registration

---

## Step 1: Create the UserSession struct

Create `lib/setlistify/tidal/user_session.ex`.

The struct holds whatever credentials the provider issues. Include at minimum `user_id`
and whatever token(s) the HTTP client will need.

**OAuth provider (like Spotify) — access + refresh token:**

```elixir
defmodule Setlistify.Tidal.UserSession do
  @moduledoc """
  Represents an authenticated Tidal user session.
  """

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t(),
          expires_at: integer(),
          user_id: String.t(),
          username: String.t()
        }

  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :username]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :username]
end
```

**Developer-token provider (like Apple Music) — long-lived user token:**

```elixir
defmodule Setlistify.Tidal.UserSession do
  @type t :: %__MODULE__{
          user_token: String.t(),
          user_id: String.t(),
          storefront: String.t()   # omit if not applicable
        }

  @enforce_keys [:user_token, :user_id]
  defstruct [:user_token, :user_id]
end
```

Decide which fields you need based on the provider's API. Use `@enforce_keys` for every
field so you get a compile-time error if any are omitted at construction time.

---

## Step 2: Create the SessionManager

Create `lib/setlistify/tidal/session_manager.ex`.

The SessionManager is a GenServer registered in `Setlistify.UserSessionRegistry` under the
key `{:tidal, user_id}`. There are two variants depending on whether the provider requires
token refresh.

### 2a. With token refresh (OAuth, like Spotify)

Use this when the provider issues short-lived access tokens and a separate refresh token.

Key points:
- `init/1` accepts `{user_id, %UserSession{}}` and schedules a timer via `{:continue, :schedule_refresh}`
- `handle_info(:refresh_token, state)` fires the real refresh and reschedules
- Broadcast `{:token_refreshed, user_session}` on `"user:#{user_id}"` so LiveViews can
  update their `user_session` assign without a page reload
- The Registry key must be `{:tidal, user_id}` — do not reuse `:spotify` or `:apple_music`

```elixir
defmodule Setlistify.Tidal.SessionManager do
  use GenServer
  require Logger
  require OpenTelemetry.Tracer

  @behaviour Setlistify.UserSessionManager

  alias Setlistify.Tidal.{API, UserSession}

  @refresh_threshold 5 * 60   # seconds before expiry to refresh

  @impl Setlistify.UserSessionManager
  def start_link({user_id, %UserSession{} = session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.start_link" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "start"}
      ])

      case GenServer.start_link(__MODULE__, {user_id, session}, name: via_tuple(user_id)) do
        {:ok, pid} = result ->
          Logger.info("Tidal session manager started", %{user_id: user_id, pid: inspect(pid)})
          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:error, reason} = error ->
          Logger.error("Failed to start Tidal session manager", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Failed to start: #{inspect(reason)}")
          error
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def get_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.get_session" do
      OpenTelemetry.Tracer.set_attributes([{"user.id", user_id}, {"enduser.id", user_id}])

      case lookup(user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :get_session)
          OpenTelemetry.Tracer.set_status(:ok, "")
          {:ok, result}

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def stop(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        GenServer.stop(pid, :normal)
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  def refresh_session(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.call(pid, :refresh_session)
      :error -> {:error, :not_found}
    end
  end

  def lookup(user_id) do
    case Registry.lookup(Setlistify.UserSessionRegistry, {:tidal, user_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @impl true
  def init({user_id, %UserSession{} = session}) do
    state = Map.put(session, :user_id, user_id)
    {:ok, state, {:continue, :schedule_refresh}}
  end

  @impl true
  def handle_continue(:schedule_refresh, %{expires_at: expires_at} = state) do
    schedule_refresh(expires_at - timestamp() - @refresh_threshold)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    session = %UserSession{
      access_token: state.access_token,
      refresh_token: state.refresh_token,
      expires_at: state.expires_at,
      user_id: state.user_id,
      username: state.username
    }
    {:reply, session, state}
  end

  @impl true
  def handle_call(:refresh_session, _from, state) do
    case do_refresh_token(state) do
      {:ok, new_state, _tokens} ->
        session = struct_from_state(new_state)
        {:reply, {:ok, session}, new_state}

      {:error, reason} = error ->
        {:stop, :normal, error, state}
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    case do_refresh_token(state) do
      {:ok, new_state, _tokens} -> {:noreply, new_state}
      {:error, reason} ->
        Logger.error("Scheduled Tidal token refresh failed", %{user_id: state.user_id, error: reason})
        {:stop, :normal, state}
    end
  end

  defp via_tuple(user_id),
    do: {:via, Registry, {Setlistify.UserSessionRegistry, {:tidal, user_id}}}

  defp schedule_refresh(after_seconds) when after_seconds > 0,
    do: Process.send_after(self(), :refresh_token, :timer.seconds(after_seconds))
  defp schedule_refresh(_),
    do: Process.send(self(), :refresh_token, [])

  defp timestamp, do: System.system_time(:second)

  defp do_refresh_token(state) do
    case API.refresh_token(state.refresh_token) do
      {:ok, new_tokens} ->
        schedule_refresh(new_tokens.expires_in - @refresh_threshold)

        new_state =
          state
          |> Map.merge(new_tokens)
          |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

        broadcast_token_refreshed(new_state)
        {:ok, new_state, new_tokens}

      {:error, _} = error ->
        error
    end
  end

  defp broadcast_token_refreshed(state) do
    session = struct_from_state(state)
    Phoenix.PubSub.broadcast(Setlistify.PubSub, "user:#{state.user_id}", {:token_refreshed, session})
  end

  defp struct_from_state(state) do
    %UserSession{
      access_token: state.access_token,
      refresh_token: state.refresh_token,
      expires_at: state.expires_at,
      user_id: state.user_id,
      username: state.username
    }
  end
end
```

### 2b. Without token refresh (long-lived token, like Apple Music)

Use this when the user token is valid for months and there is no server-side refresh
endpoint. Skip the `handle_continue`, `handle_info`, and `do_refresh_token` functions
entirely.

```elixir
defmodule Setlistify.Tidal.SessionManager do
  use GenServer
  require Logger
  require OpenTelemetry.Tracer

  @behaviour Setlistify.UserSessionManager

  alias Setlistify.Tidal.UserSession

  @impl Setlistify.UserSessionManager
  def start_link({user_id, %UserSession{} = session}) do
    GenServer.start_link(__MODULE__, session, name: via_tuple(user_id))
  end

  @impl Setlistify.UserSessionManager
  def get_session(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> {:ok, GenServer.call(pid, :get_session)}
      :error -> {:error, :not_found}
    end
  end

  @impl Setlistify.UserSessionManager
  def stop(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.stop(pid, :normal)
      :error -> {:error, :not_found}
    end
  end

  def lookup(user_id) do
    case Registry.lookup(Setlistify.UserSessionRegistry, {:tidal, user_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @impl true
  def init(%UserSession{} = session), do: {:ok, session}

  @impl true
  def handle_call(:get_session, _from, session), do: {:reply, session, session}

  defp via_tuple(user_id),
    do: {:via, Registry, {Setlistify.UserSessionRegistry, {:tidal, user_id}}}
end
```

---

## Step 3: Create the SessionSupervisor

Create `lib/setlistify/tidal/session_supervisor.ex`.

Both providers share the same `Setlistify.UserSessionSupervisor` `DynamicSupervisor` —
this wrapper just gives the caller a named entry point and handles logging.

```elixir
defmodule Setlistify.Tidal.SessionSupervisor do
  @moduledoc """
  Supervisor for managing Tidal user session processes.
  """

  require Logger
  require OpenTelemetry.Tracer

  alias Setlistify.Tidal.{SessionManager, UserSession}

  def start_user_token(user_id, %UserSession{} = session) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.start_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "start_child"}
      ])

      case DynamicSupervisor.start_child(
             Setlistify.UserSessionSupervisor,
             {SessionManager, {user_id, session}}
           ) do
        {:ok, pid} = result ->
          Logger.info("Tidal user token process started", %{user_id: user_id, pid: inspect(pid)})
          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:error, {:already_started, pid}} ->
          Logger.info("Tidal user token process already running", %{user_id: user_id, pid: inspect(pid)})
          OpenTelemetry.Tracer.set_status(:ok, "")
          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start Tidal user token process", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Failed to start child: #{inspect(reason)}")
          error
      end
    end
  end

  def stop_user_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.stop_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "terminate_child"}
      ])

      case SessionManager.lookup(user_id) do
        {:ok, pid} ->
          case DynamicSupervisor.terminate_child(Setlistify.UserSessionSupervisor, pid) do
            :ok ->
              Logger.info("Tidal user token process terminated", %{user_id: user_id})
              OpenTelemetry.Tracer.set_status(:ok, "")
              :ok

            {:error, reason} = error ->
              OpenTelemetry.Tracer.set_status(:error, "Failed to terminate: #{inspect(reason)}")
              error
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Process not found in registry")
          {:error, :not_found}
      end
    end
  end

  def get_session(user_id) do
    SessionManager.get_session(user_id)
  end
end
```

If your provider uses token refresh (Step 2a), also delegate `refresh_session/1` here,
matching the pattern in `Setlistify.Spotify.SessionSupervisor`.

---

## Step 4: Create the API behaviour and ExternalClient

### 4a. API module

Create `lib/setlistify/tidal/api.ex`.

This module declares the callbacks and delegates to `impl/0`, which reads from application
config. This allows tests to swap in a mock client without touching the production code.

```elixir
defmodule Setlistify.Tidal.API do
  @behaviour Setlistify.MusicService.API

  require OpenTelemetry.Tracer

  alias Setlistify.Tidal.UserSession

  @callback search_for_track(UserSession.t(), String.t(), String.t()) ::
              nil | %{track_id: String.t()}
  def search_for_track(user_session, artist, track) do
    parent_ctx = OpenTelemetry.Ctx.get_current()
    parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

    :tidal_track_cache
    |> Cachex.fetch({artist, track}, fn {artist, track} ->
      OpenTelemetry.Ctx.attach(parent_ctx)
      OpenTelemetry.Tracer.set_current_span(parent_span)
      impl().search_for_track(user_session, artist, track)
    end)
    |> elem(1)
  end

  @callback create_playlist(UserSession.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t(), external_url: String.t()}} | {:error, atom()}
  def create_playlist(user_session, name, description),
    do: impl().create_playlist(user_session, name, description)

  @callback add_tracks_to_playlist(UserSession.t(), String.t(), [String.t()]) ::
              {:ok, atom()} | {:error, atom()}
  def add_tracks_to_playlist(user_session, playlist_id, tracks),
    do: impl().add_tracks_to_playlist(user_session, playlist_id, tracks)

  # Add provider-specific callbacks here (e.g. exchange_code, refresh_token,
  # build_user_session) mirroring the Spotify or Apple Music API modules.

  defp impl do
    Application.get_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.ExternalClient)
  end
end
```

The three callbacks (`search_for_track`, `create_playlist`, `add_tracks_to_playlist`) are
required by `Setlistify.MusicService.API` and must be implemented for every provider.

The Cachex propagation boilerplate in `search_for_track` is necessary because Cachex runs
the fetch function in a separate process. Copy it verbatim from either existing provider —
do not simplify it.

### 4b. ExternalClient

Create `lib/setlistify/tidal/api/external_client.ex`.

The ExternalClient builds a `Req` client with the provider's base URL and auth headers,
then implements each callback.

**For OAuth providers (access token in Authorization header, with refresh on 401):**

```elixir
defmodule Setlistify.Tidal.API.ExternalClient do
  @behaviour Setlistify.Tidal.API

  require Logger
  require OpenTelemetry.Tracer

  alias Setlistify.Tidal.{UserSession, SessionManager}

  defp client(%UserSession{access_token: token}) do
    default_opts = [base_url: "https://openapi.tidal.com/v2/", auth: {:bearer, token}]
    config_opts = Application.get_env(:setlistify, :tidal_req_options, [])

    Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
    |> Req.merge(Keyword.merge(default_opts, config_opts))
  end

  defp with_token_refresh(user_session, request_fn, context) do
    req = client(user_session)

    case request_fn.(req) do
      {:ok, %{status: 401}} ->
        Logger.warning("401 during #{context}, attempting token refresh for user #{user_session.user_id}")

        OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.with_token_refresh" do
          case SessionManager.refresh_session(user_session.user_id) do
            {:ok, new_session} ->
              new_req = client(new_session)
              result = request_fn.(new_req)
              OpenTelemetry.Tracer.set_status(:ok, "")
              result

            {:error, reason} ->
              Logger.error("Token refresh failed during #{context}: #{inspect(reason)}")
              OpenTelemetry.Tracer.set_status(:error, "Token refresh failed")
              {:error, :token_refresh_failed}
          end
        end

      other ->
        other
    end
  end

  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.API.ExternalClient.search_for_track" do
      request_fn = fn req ->
        Req.get(req, url: "/search", params: %{query: "#{artist} #{track}", limit: 1})
      end

      case with_token_refresh(user_session, request_fn, "track search") do
        {:ok, %{status: 200} = resp} ->
          # Parse the response body to extract the track ID.
          # Return %{track_id: id} on success or nil if not found.
          nil  # TODO: implement per provider API shape

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          error

        {:ok, response} ->
          Logger.error("Unexpected response from Tidal search: #{inspect(response)}")
          nil
      end
    end
  rescue
    error ->
      Logger.error("Exception during Tidal search: #{inspect(error)}")
      OpenTelemetry.Tracer.record_exception(error)
      nil
  end

  # Implement create_playlist/3 and add_tracks_to_playlist/3 similarly.
  # Each function wraps its Req call in with_token_refresh/3 and an OTel span.
end
```

**For developer-token providers (like Apple Music, two-header auth):**

The difference is that the `client/1` function calls `DeveloperTokenManager.get_token/0`
and sets two headers, and `with_developer_token_refresh/3` calls
`DeveloperTokenManager.regenerate_token/0` on 401 instead of refreshing the user token:

```elixir
defp client(%UserSession{user_token: user_token}) do
  developer_token = Setlistify.Tidal.DeveloperTokenManager.get_token()

  default_opts = [
    base_url: "https://api.tidal.com",
    headers: [
      {"Authorization", "Bearer #{developer_token}"},
      {"X-Tidal-User-Token", user_token}
    ]
  ]

  config_opts = Application.get_env(:setlistify, :tidal_req_options, [])

  Req.new()
  |> OpentelemetryReq.attach(propagate_trace_headers: true)
  |> Req.merge(Keyword.merge(default_opts, config_opts))
end
```

Note: The `config_opts` merge pattern (using `Application.get_env(:setlistify, :tidal_req_options, [])`) is important — it lets tests inject a `plug:` option to intercept HTTP calls without a real network connection.

---

## Step 5: Create DeveloperTokenManager (only if needed)

Skip this step if your provider uses standard OAuth (access + refresh tokens). You need
this only when the provider requires an app-level JWT signed with a private key, like
Apple Music.

Create `lib/setlistify/tidal/developer_token_manager.ex`:

```elixir
defmodule Setlistify.Tidal.DeveloperTokenManager do
  @moduledoc """
  Singleton GenServer that generates and caches the Tidal developer token.
  Token is regenerated 5 minutes before expiry.
  """

  use GenServer
  require Logger

  @refresh_threshold 5 * 60
  @default_ttl_seconds 30 * 24 * 60 * 60

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get_token, do: GenServer.call(__MODULE__, :get_token)
  def regenerate_token, do: GenServer.call(__MODULE__, :regenerate_token)

  def init(_),
    do: {:ok, %{token: nil, expires_at: nil, timer_ref: nil}, {:continue, :generate_token}}

  def handle_continue(:generate_token, state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("DeveloperTokenManager failed to generate token: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  def handle_call(:get_token, _from, state), do: {:reply, state.token, state}

  def handle_call(:regenerate_token, _from, state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:reply, token, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("DeveloperTokenManager failed to regenerate: #{inspect(reason)}")
        {:reply, state.token, state}
    end
  end

  def handle_info(:refresh_token, state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("DeveloperTokenManager failed to refresh: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  defp generate_and_sign do
    now = System.system_time(:second)
    expires_at = now + @default_ttl_seconds
    # Generate your signed token here using provider-specific signing logic
    {:ok, "signed-token-placeholder", expires_at}
  rescue
    e -> {:error, e}
  end

  defp schedule_refresh(expires_at, existing_timer) do
    if existing_timer, do: Process.cancel_timer(existing_timer)
    ms = max((expires_at - System.system_time(:second) - @refresh_threshold) * 1_000, 0)
    Process.send_after(self(), :refresh_token, ms)
  end
end
```

Start it in `Application` (see Step 11).

---

## Step 6: Add the session restoration plug

Create `lib/setlistify_web/plugs/restore_tidal_token.ex`.

This plug runs on every request. If the user has a `tidal` session cookie but no live
GenServer process (e.g. after a server restart), it reconstructs the session from the
encrypted cookie data.

**OAuth provider (needs a network call to refresh):**

```elixir
defmodule SetlistifyWeb.Plugs.RestoreTidalToken do
  @moduledoc """
  Restores a Tidal session process from an encrypted refresh token cookie.
  If the process is missing (e.g. after a server restart), it calls the
  token endpoint to get a fresh access token and re-starts the GenServer.
  """

  import Plug.Conn

  alias Setlistify.Tidal.{SessionSupervisor, SessionManager, API}
  alias Setlistify.Auth.TokenSalts

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :auth_provider) == "tidal" do
      do_call(conn)
    else
      conn
    end
  end

  defp do_call(conn) do
    user_id = get_session(conn, :user_id)
    encrypted_token = get_session(conn, :refresh_token)

    with user_id when not is_nil(user_id) <- user_id,
         {:error, :not_found} <- SessionManager.get_session(user_id),
         encrypted when not is_nil(encrypted) <- encrypted_token,
         {:ok, refresh_token} <-
           Phoenix.Token.verify(
             SetlistifyWeb.Endpoint,
             TokenSalts.tidal_refresh_token(),
             encrypted,
             max_age: 86_400 * 30
           ) do
      case API.refresh_to_user_session(refresh_token) do
        {:ok, user_session} ->
          {:ok, _pid} = SessionSupervisor.start_user_token(user_id, user_session)
          conn

        {:error, _reason} ->
          conn
          |> clear_session()
          |> Phoenix.Controller.put_flash(:error, "Your Tidal session has expired. Please log in again.")
      end
    else
      _ -> conn
    end
  end
end
```

**Long-lived token provider (no network call needed):**

```elixir
defmodule SetlistifyWeb.Plugs.RestoreTidalToken do
  @moduledoc """
  Restores a Tidal session process from an encrypted user token cookie.
  No network call required — the token is reconstructed directly from
  encrypted cookie values.
  """

  import Plug.Conn

  alias Setlistify.Tidal.{SessionManager, SessionSupervisor, API}
  alias Setlistify.Auth.TokenSalts

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :auth_provider) == "tidal" do
      restore_session(conn)
    else
      conn
    end
  end

  defp restore_session(conn) do
    user_id = get_session(conn, :user_id)
    encrypted_token = get_session(conn, :tidal_user_token)

    case SessionManager.get_session(user_id) do
      {:ok, _session} ->
        conn

      {:error, :not_found} ->
        with user_id when not is_nil(user_id) <- user_id,
             {:ok, user_token} <- decrypt_token(encrypted_token),
             {:ok, user_session} <- API.build_user_session(user_token, user_id) do
          SessionSupervisor.start_user_token(user_id, user_session)
          conn
        else
          _ ->
            conn
            |> clear_session()
            |> Phoenix.Controller.put_flash(:error, "Session expired. Please sign in again.")
        end
    end
  end

  defp decrypt_token(nil), do: {:error, :missing}
  defp decrypt_token(encrypted) do
    Phoenix.Token.verify(SetlistifyWeb.Endpoint, TokenSalts.tidal_user_token(), encrypted,
      max_age: 86_400 * 180
    )
  end
end
```

---

## Step 7: Update MusicService.API dispatch

Edit `lib/setlistify/music_service/api.ex`. This module dispatches to the correct
provider-specific API based on the struct type of the session.

Add the alias and a new `impl/1` clause:

```elixir
# in the alias block at the top:
alias Setlistify.{AppleMusic, Spotify, Tidal}

# add to the @type union:
@type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t() | Tidal.UserSession.t()

# add a new impl/1 clause:
defp impl(%Tidal.UserSession{}) do
  OpenTelemetry.Tracer.set_attribute("peer.service", "tidal")
  Tidal.API
end
```

If your provider supports embeds (playlist preview iframes), also add a `get_embed/2`
clause:

```elixir
def get_embed("tidal", url), do: Tidal.API.get_embed(url)
```

---

## Step 8: Update UserSessionManager dispatch

Edit `lib/setlistify/user_session_manager.ex`. This module dispatches session lifecycle
operations (start, get, stop) to the correct provider.

```elixir
# Add to the alias
alias Setlistify.{Spotify, AppleMusic, Tidal}

# Add to the @type unions
@type provider_key :: {:spotify, String.t()} | {:apple_music, String.t()} | {:tidal, String.t()}
@type user_session :: Spotify.UserSession.t() | AppleMusic.UserSession.t() | Tidal.UserSession.t()

# Add impl/1 clauses
defp impl(%Tidal.UserSession{}), do: Tidal.SessionManager
defp impl({:tidal, _}), do: Tidal.SessionManager
```

---

## Step 9: Add a TokenSalts constant

Edit `lib/setlistify/auth/token_salts.ex` and add a function for your provider's cookie
salt. The salt must match exactly between the sign site (controller) and the verify site
(plug).

```elixir
def tidal_refresh_token, do: "tidal refresh token"
# or, for a long-lived user token:
def tidal_user_token, do: "tidal user token"
```

---

## Step 10: Update auth wiring

### 10a. LiveHooks provider key mapping

Edit `lib/setlistify_web/auth/live_hooks.ex`. Add a clause to `to_provider_key/2` so the
LiveView auth hook can resolve the session from the cookie:

```elixir
defp to_provider_key("tidal", user_id), do: {:ok, {:tidal, user_id}}
```

### 10b. UserAuth session preservation

Edit `lib/setlistify_web/controllers/user_auth.ex`. The `auth_user/2` function reads
session fields before clearing the session and re-writes them after. Add your new
provider-specific fields here.

For an OAuth provider storing a refresh token:

```elixir
def auth_user(conn, user_id) do
  encrypted_refresh_token = get_session(conn, :refresh_token)
  auth_provider = get_session(conn, :auth_provider)
  # ... existing fields ...
  tidal_refresh_token = get_session(conn, :tidal_refresh_token)  # add this

  conn
  |> renew_session()
  |> put_session(:user_id, user_id)
  |> put_session(:auth_provider, auth_provider)
  |> put_session(:refresh_token, encrypted_refresh_token)
  # ... existing puts ...
  |> put_session(:tidal_refresh_token, tidal_refresh_token)  # add this
  |> put_session(:live_socket_id, "users_sessions:#{user_id}")
  |> redirect(external: redirect_to || url(~p"/"))
end
```

If your provider uses a different session key name than `:refresh_token` (to avoid
collisions), add a dedicated key here and adjust accordingly in the controller and plug.

---

## Step 11: Wire up the router

### 11a. Add the restoration plug to the browser pipeline

Edit `lib/setlistify_web/router.ex`:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, {SetlistifyWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers

  plug SetlistifyWeb.Plugs.RestoreSpotifyToken
  plug SetlistifyWeb.Plugs.RestoreAppleMusicToken
  plug SetlistifyWeb.Plugs.RestoreTidalToken   # add this
end
```

### 11b. Add OAuth routes

For a standard OAuth provider, add a callback GET route:

```elixir
get "/oauth/callbacks/:provider", OAuthCallbackController, :new
get "/signin/:provider", OAuthCallbackController, :sign_in
```

These routes already exist (`:provider` is a wildcard). You just need to add matching
function heads in the controller (see Step 12).

For a non-standard auth flow (like Apple Music's JS-based sign-in), add a POST route:

```elixir
post "/oauth/callbacks/tidal", OAuthCallbackController, :new_tidal
```

---

## Step 12: Update OAuthCallbackController

Edit `lib/setlistify_web/controllers/oauth_callback_controller.ex`.

### 12a. Sign-in redirect (OAuth flow)

Add a `sign_in/2` function head for your provider. This redirects the user to the
provider's authorization page:

```elixir
def sign_in(conn, %{"provider" => "tidal"} = params) do
  state =
    :crypto.strong_rand_bytes(10)
    |> Base.url_encode64()
    |> binary_part(0, 10)

  uri =
    "https://login.tidal.com/authorize"
    |> URI.new!()
    |> URI.append_query(
      URI.encode_query(%{
        client_id: Application.fetch_env!(:setlistify, :tidal_client_id),
        response_type: "code",
        redirect_uri: url(~p"/oauth/callbacks/tidal"),
        state: state,
        scope: "playlists.read playlists.write"
      })
    )
    |> URI.to_string()

  conn
  |> put_session(:oauth_state, state)
  |> maybe_put_redirect_to(params)
  |> redirect(external: uri)
end
```

### 12b. OAuth callback handler

Add a `new/2` function head to handle the redirect back from the provider:

```elixir
def new(conn, %{"provider" => "tidal", "code" => code, "state" => state}) do
  if state == get_session(conn, :oauth_state) do
    redirect_uri = url(~p"/oauth/callbacks/tidal")

    case Tidal.API.exchange_code(code, redirect_uri) do
      {:ok, user_session} ->
        encrypted_refresh_token =
          Phoenix.Token.sign(
            SetlistifyWeb.Endpoint,
            TokenSalts.tidal_refresh_token(),
            user_session.refresh_token
          )

        Tidal.SessionSupervisor.start_user_token(user_session.user_id, user_session)

        conn
        |> put_session(:auth_provider, "tidal")
        |> put_session(:refresh_token, encrypted_refresh_token)
        |> put_session(:user_id, user_session.user_id)
        |> UserAuth.auth_user(user_session.user_id)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to authenticate with Tidal. Please try again.")
        |> redirect(to: ~p"/")
    end
  else
    conn
    |> put_flash(:error, "Response from Tidal did not match. Please try again.")
    |> redirect(to: ~p"/")
  end
end
```

### 12c. Sign-out

Add a clause to the `sign_out/2` case expression:

```elixir
{"tidal", id} when not is_nil(id) -> Tidal.SessionSupervisor.stop_user_token(id)
```

---

## Step 13: Add sign-in UI

The `SetlistifyWeb.Setlists.ShowLive` view shows a sign-in prompt when `@user_session` is
nil. The current Spotify-only link should be extended to offer all supported providers.

In `lib/setlistify_web/live/setlists/show_live.ex`, add a `provider/1` clause so the
redirect after playlist creation resolves the correct provider string:

```elixir
defp provider(%Tidal.UserSession{}), do: "tidal"
```

In the render template, add a sign-in button for Tidal alongside the Spotify one:

```heex
<.link navigate={~p"/signin/tidal?redirect_to=#{@redirect_to}"} ...>
  Sign in with Tidal
</.link>
```

In `SetlistifyWeb.Playlists.ShowLive`, add a `handle_params/3` clause for the new
provider. If your provider supports embeds, call `MusicService.API.get_embed("tidal", url)`
there. If it does not, link to the library root (see the Apple Music clause for an example).

---

## Step 14: Update Application

Edit `lib/setlistify/application.ex`.

### 14a. Add the track cache

Every provider gets its own Cachex cache for `search_for_track` results. Add it to the
`children` list:

```elixir
Supervisor.child_spec(
  {Cachex,
   name: :tidal_track_cache,
   expiration: Cachex.Spec.expiration(default: :timer.minutes(5))},
  id: :tidal_track_cache
)
```

The cache name (`:tidal_track_cache`) must match the atom used in `Tidal.API.search_for_track/3`.

### 14b. Start DeveloperTokenManager (only if needed)

If your provider uses a `DeveloperTokenManager`, start it conditionally (the flag lets
tests disable it to avoid needing valid credentials):

```elixir
defp tidal_children do
  if Application.get_env(:setlistify, :start_tidal_token_manager, true) do
    [Setlistify.Tidal.DeveloperTokenManager]
  else
    []
  end
end
```

Then append it to children:

```elixir
children = [...existing children...] ++ apple_music_children() ++ tidal_children()
```

---

## Step 15: Register the test mock

Edit `test/test_helper.exs`. Add two lines at the top (before `ExUnit.start()`):

```elixir
Hammox.defmock(Setlistify.Tidal.API.MockClient, for: Setlistify.Tidal.API)
Application.put_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.MockClient)
```

This creates a mock module that satisfies the `Setlistify.Tidal.API` behaviour and
registers it as the active client for the test environment. Tests then call
`Hammox.expect/3` or `Hammox.stub/3` to set expectations on individual callbacks.

If you added a `DeveloperTokenManager`, also add:

```elixir
Application.put_env(:setlistify, :start_tidal_token_manager, false)
```

---

## Step 16: Add environment variables

Add the following to your `.env` file (copy `.env.example` as a starting point):

**For an OAuth provider:**

```
TIDAL_CLIENT_ID=your_client_id
TIDAL_CLIENT_SECRET=your_client_secret
```

Wire them into config in `config/runtime.exs`:

```elixir
config :setlistify,
  tidal_client_id: System.fetch_env!("TIDAL_CLIENT_ID"),
  tidal_client_secret: System.fetch_env!("TIDAL_CLIENT_SECRET")
```

Then read them in `ExternalClient`:

```elixir
client_id = Application.fetch_env!(:setlistify, :tidal_client_id)
client_secret = Application.fetch_env!(:setlistify, :tidal_client_secret)
```

**For a developer-token provider (app-level JWT):**

```
TIDAL_TEAM_ID=your_team_id
TIDAL_KEY_ID=your_key_id
TIDAL_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
```

```elixir
config :setlistify,
  tidal_team_id: System.fetch_env!("TIDAL_TEAM_ID"),
  tidal_key_id: System.fetch_env!("TIDAL_KEY_ID"),
  tidal_private_key: System.fetch_env!("TIDAL_PRIVATE_KEY")
```

---

## Checklist

Work through these in order:

- [ ] `lib/setlistify/tidal/user_session.ex` — `@enforce_keys`, provider fields
- [ ] `lib/setlistify/tidal/session_manager.ex` — GenServer, `{:tidal, user_id}` Registry key, refresh timer if needed
- [ ] `lib/setlistify/tidal/session_supervisor.ex` — `start_user_token`, `stop_user_token`, `get_session`
- [ ] `lib/setlistify/tidal/api.ex` — `@behaviour Setlistify.MusicService.API`, three required callbacks, Cachex propagation in `search_for_track`, `impl/0`
- [ ] `lib/setlistify/tidal/api/external_client.ex` — `client/1`, `with_token_refresh/3` or `with_developer_token_refresh/3`, three required functions
- [ ] `lib/setlistify/tidal/developer_token_manager.ex` — only if provider uses app-level JWTs
- [ ] `lib/setlistify_web/plugs/restore_tidal_token.ex` — checks `auth_provider == "tidal"`, decrypts cookie, restarts GenServer
- [ ] `lib/setlistify/music_service/api.ex` — add alias, `@type` union, `impl/1` clause
- [ ] `lib/setlistify/user_session_manager.ex` — add alias, `@type` unions, two `impl/1` clauses
- [ ] `lib/setlistify/auth/token_salts.ex` — add salt constant function
- [ ] `lib/setlistify_web/auth/live_hooks.ex` — add `to_provider_key/2` clause
- [ ] `lib/setlistify_web/controllers/user_auth.ex` — preserve new session fields in `auth_user/2`
- [ ] `lib/setlistify_web/router.ex` — add `RestoreTidalToken` to browser pipeline; add routes if needed
- [ ] `lib/setlistify_web/controllers/oauth_callback_controller.ex` — `sign_in/2`, `new/2`, `sign_out/2` clauses
- [ ] `lib/setlistify_web/live/setlists/show_live.ex` — `provider/1` clause, sign-in link
- [ ] `lib/setlistify_web/live/playlists/show_live.ex` — `handle_params/3` clause for provider
- [ ] `lib/setlistify/application.ex` — Cachex cache; `DeveloperTokenManager` if needed
- [ ] `test/test_helper.exs` — mock registration
- [ ] `.env` / `config/runtime.exs` — environment variables
- [ ] `mix format && mix test` — verify everything compiles and passes
