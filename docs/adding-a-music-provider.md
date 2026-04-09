# Adding a New Music Provider

This guide walks through adding a new music provider (e.g. Tidal) to Setlistify. Each
step points you to the real implementations to copy and adapt — read those files first,
then apply only the provider-specific changes described here.

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

The struct holds whatever credentials the provider issues. Use `@enforce_keys` for every
field so you get a compile-time error if any are omitted at construction time.

**OAuth provider (access + refresh token):** include `access_token`, `refresh_token`,
`expires_at`, `user_id`, and any display fields (e.g. `username`).

**Long-lived token provider (like Apple Music):** include `user_token`, `user_id`, and
any provider-specific fields (e.g. `storefront`). Omit `expires_at` and `refresh_token`.

---

## Step 2: Create the SessionManager

Create `lib/setlistify/tidal/session_manager.ex`.

**Reference implementations:**
- OAuth with refresh: `lib/setlistify/spotify/session_manager.ex`
- Long-lived token (no refresh): `lib/setlistify/apple_music/session_manager.ex`

The SessionManager is a GenServer registered in `Setlistify.UserSessionRegistry` under
`{:tidal, user_id}`. It implements `@behaviour Setlistify.UserSessionManager`, which
requires `start_link/1`, `get_session/1`, and `stop/1`.

**Key things to adapt:**

- Registry key in `via_tuple/1` and `lookup/1`: use `{:tidal, user_id}` — not `:spotify`
  or `:apple_music`
- If OAuth: `init/1` returns `{:ok, state, {:continue, :schedule_refresh}}`. Include
  `handle_continue(:schedule_refresh, ...)`, `handle_info(:refresh_token, ...)`, and a
  private `do_refresh_token/1` that calls `Tidal.API.refresh_token/1`, reschedules the
  timer, and calls `broadcast_token_refreshed/1`
- The PubSub broadcast in `broadcast_token_refreshed/1` publishes
  `{:token_refreshed, session}` on `"user:#{user_id}"` so LiveViews update their assigns
  without a page reload
- If long-lived token: omit the refresh timer entirely — `init/1` just stores the session
  and returns `{:ok, session}`
- OTel spans follow the `"Module.Submodule.function_name"` naming convention; copy the
  attribute keys from the reference implementation

---

## Step 3: Create the SessionSupervisor

Create `lib/setlistify/tidal/session_supervisor.ex`.

**Reference implementation:** `lib/setlistify/spotify/session_supervisor.ex` (OAuth) or
`lib/setlistify/apple_music/session_supervisor.ex` (long-lived token).

The supervisor wraps `DynamicSupervisor.start_child/2` and
`DynamicSupervisor.terminate_child/2` against the shared `Setlistify.UserSessionSupervisor`.
Both providers share that supervisor — this module is just a named entry point with logging.

**Key things to adapt:**

- `start_user_token/2`: calls `DynamicSupervisor.start_child(Setlistify.UserSessionSupervisor, {SessionManager, {user_id, session}})`. Handle `{:already_started, pid}` as a success.
- `stop_user_token/1`: looks up the pid via `SessionManager.lookup/1`, then calls `DynamicSupervisor.terminate_child/2`
- `get_session/1`: delegates to `SessionManager.get_session/1`
- If OAuth: also delegate `refresh_session/1` to `SessionManager.refresh_session/1`

---

## Step 4: Create the API behaviour and ExternalClient

### 4a. API module

Create `lib/setlistify/tidal/api.ex`.

**Reference implementations:** `lib/setlistify/spotify/api.ex` (OAuth) or
`lib/setlistify/apple_music/api.ex` (long-lived token).

The module declares `@behaviour Setlistify.MusicService.API` and delegates every call to
`impl/0`, which reads the client from application config. This allows tests to swap in a
mock without touching production code.

**Required callbacks** (from `Setlistify.MusicService.API`):
- `search_for_track/3` — must go through Cachex using the OTel context propagation pattern
- `create_playlist/3` — delegates directly to `impl()`
- `add_tracks_to_playlist/3` — delegates directly to `impl()`

**Provider-specific callbacks** to add alongside the required ones:
- OAuth: `exchange_code/2`, `refresh_token/1`, `refresh_to_user_session/1`
- Long-lived token: `build_user_session/2` (or `/3` if you have a `storefront` field)

The `impl/0` private function reads:

```elixir
defp impl do
  Application.get_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.ExternalClient)
end
```

The Cachex OTel propagation pattern in `search_for_track/3` is necessary because Cachex
runs the fetch function in a separate process. Copy it verbatim from either existing
provider — do not simplify it.

### 4b. ExternalClient

Create `lib/setlistify/tidal/api/external_client.ex`.

**Reference implementations:** `lib/setlistify/spotify/api/external_client.ex` (OAuth with
refresh) or `lib/setlistify/apple_music/api/external_client.ex` (developer token, two-header
auth).

The ExternalClient builds a `Req` client with the provider's base URL and auth headers,
then implements each callback declared in `Tidal.API`.

**Key things to adapt:**

- `client/1`: set `base_url` and auth. For OAuth: `auth: {:bearer, access_token}`. For
  developer-token providers: set two headers — `Authorization: Bearer <developer_token>`
  and a provider-specific user-token header. Always merge
  `Application.get_env(:setlistify, :tidal_req_options, [])` — this lets tests inject a
  `plug:` option to intercept HTTP without a live network.
- For OAuth: include a `with_token_refresh/3` helper that retries the request with a fresh
  token on 401, calling `SessionManager.refresh_session/1`
- For developer-token providers: include a `with_developer_token_refresh/3` helper that
  calls `DeveloperTokenManager.regenerate_token/0` on 401
- Wrap each public function in an OTel span named `"Setlistify.Tidal.API.ExternalClient.<function>"`

---

## Step 5: Create DeveloperTokenManager (only if needed)

Skip this step for standard OAuth providers.

Create `lib/setlistify/tidal/developer_token_manager.ex` if the provider requires an
app-level JWT signed with a private key (as Apple Music does).

**Reference implementation:** `lib/setlistify/apple_music/developer_token_manager.ex`

The DeveloperTokenManager is a singleton GenServer (registered by module name) that
generates a signed token on startup and refreshes it before expiry.

**Key things to adapt:**

- `generate_and_sign/0`: implement provider-specific JWT signing using your private key,
  team/key IDs, and whatever claims the provider requires
- `@default_ttl_seconds`: set to the provider's actual maximum token lifetime
- `@refresh_threshold`: typically 5 minutes before expiry

---

## Step 6: Add the session restoration plug

Create `lib/setlistify_web/plugs/restore_tidal_token.ex`.

**Reference implementations:**
- OAuth (needs a network call): `lib/setlistify_web/plugs/restore_spotify_token.ex`
- Long-lived token (no network call): `lib/setlistify_web/plugs/restore_apple_music_token.ex`

This plug runs on every request. If the user has a `tidal` session cookie but no live
GenServer process (e.g. after a server restart), it reconstructs the session from the
encrypted cookie.

**Key things to adapt:**

- Guard with `get_session(conn, :auth_provider) == "tidal"` — return `conn` unchanged for
  all other providers
- Verify the encrypted token with `Phoenix.Token.verify/4` using your `TokenSalts`
  constant (see Step 9)
- OAuth: on missing session, call `API.refresh_to_user_session/1` with the decrypted
  refresh token, then `SessionSupervisor.start_user_token/2`
- Long-lived token: on missing session, decrypt the stored user token and call
  `API.build_user_session/2` (or `/3`), then `SessionSupervisor.start_user_token/2`
- If anything fails (decrypt error, refresh failure), `clear_session/1` and
  `put_flash(:error, ...)` before returning

---

## Step 7: Update MusicService.API dispatch

Edit `lib/setlistify/music_service/api.ex`.

Add your provider's `UserSession` alias to the alias block, extend the `@type user_session`
union, and add a new `impl/1` clause:

```elixir
defp impl(%Tidal.UserSession{}) do
  OpenTelemetry.Tracer.set_attribute("peer.service", "tidal")
  Tidal.API
end
```

If your provider supports embed previews, also add a `get_embed/2` clause:

```elixir
def get_embed("tidal", url), do: Tidal.API.get_embed(url)
```

---

## Step 8: Update UserSessionManager dispatch

Edit `lib/setlistify/user_session_manager.ex`.

Add your provider's alias, extend both `@type` unions, and add two `impl/1` clauses —
one matching the `UserSession` struct (used at session creation) and one matching the
provider key tuple (used for lookups and teardown):

```elixir
defp impl(%Tidal.UserSession{}), do: Tidal.SessionManager
defp impl({:tidal, _}), do: Tidal.SessionManager
```

---

## Step 9: Add a TokenSalts constant

Edit `lib/setlistify/auth/token_salts.ex`.

Add a function that returns the salt string for your provider's encrypted cookie. The salt
must be identical at the sign site (controller) and the verify site (plug).

- OAuth: `def tidal_refresh_token, do: "tidal refresh token"`
- Long-lived token: `def tidal_user_token, do: "tidal user token"`

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
session fields before clearing the session and re-writes them after. Add your
provider-specific field(s) here — read them before `renew_session/1` and write them back
with `put_session/3`.

Use a dedicated session key (e.g. `:tidal_refresh_token`) rather than reusing `:refresh_token`
to avoid collisions if both providers could be active.

---

## Step 11: Wire up the router

Edit `lib/setlistify_web/router.ex`.

Add your restoration plug to the `:browser` pipeline after the existing provider plugs:

```elixir
plug SetlistifyWeb.Plugs.RestoreTidalToken
```

The OAuth callback routes (`get "/oauth/callbacks/:provider"` and
`get "/signin/:provider"`) already exist as wildcards — you only need to add matching
function heads in the controller. If the provider uses a non-standard auth flow (like
Apple Music's JS-based sign-in), add a dedicated POST route.

---

## Step 12: Update OAuthCallbackController

Edit `lib/setlistify_web/controllers/oauth_callback_controller.ex`.

Add three function heads:

- **`sign_in/2`** matching `%{"provider" => "tidal"}`: build the authorization URL with
  the provider's OAuth parameters, store an `:oauth_state` nonce in the session, and
  redirect externally
- **`new/2`** matching `%{"provider" => "tidal", "code" => code, "state" => state}`:
  verify the state nonce, call `Tidal.API.exchange_code/2`, encrypt the refresh token with
  `Phoenix.Token.sign/3` using your salt, call
  `Tidal.SessionSupervisor.start_user_token/2`, write session fields, and call
  `UserAuth.auth_user/2`
- **`sign_out/2`** case clause: `{"tidal", id} when not is_nil(id) -> Tidal.SessionSupervisor.stop_user_token(id)`

For long-lived token providers with a non-standard auth flow (e.g. a POST from JavaScript),
the callback handler follows the same shape but reads the user token from the request body
instead of exchanging a code.

---

## Step 13: Add sign-in UI

In `lib/setlistify_web/live/setlists/show_live.ex`:

- Add a `provider/1` clause so the redirect after playlist creation resolves the correct
  provider string: `defp provider(%Tidal.UserSession{}), do: "tidal"`
- Add a sign-in link in the render template:
  `<.link navigate={~p"/signin/tidal?redirect_to=#{@redirect_to}"}>Sign in with Tidal</.link>`

In `lib/setlistify_web/live/playlists/show_live.ex`, add a `handle_params/3` clause for
the new provider. If the provider supports embed previews, call
`MusicService.API.get_embed("tidal", url)`. If not, link to the library root (see the
Apple Music clause for an example).

---

## Step 14: Update Application

Edit `lib/setlistify/application.ex`.

### 14a. Add the track cache

Every provider needs its own Cachex cache for `search_for_track` results. Add it to
`children`:

```elixir
Supervisor.child_spec(
  {Cachex, name: :tidal_track_cache, expiration: Cachex.Spec.expiration(default: :timer.minutes(5))},
  id: :tidal_track_cache
)
```

The atom (`:tidal_track_cache`) must match what you pass to `Cachex.fetch/3` in
`Tidal.API.search_for_track/3`.

### 14b. Start DeveloperTokenManager (only if needed)

If you created a `DeveloperTokenManager` in Step 5, start it conditionally so tests can
disable it without valid credentials:

```elixir
defp tidal_children do
  if Application.get_env(:setlistify, :start_tidal_token_manager, true) do
    [Setlistify.Tidal.DeveloperTokenManager]
  else
    []
  end
end
```

Append `tidal_children()` to the `children` list alongside the existing provider helpers.

---

## Step 15: Register the test mock

Edit `test/test_helper.exs`. Add two lines before `ExUnit.start()`:

```elixir
Hammox.defmock(Setlistify.Tidal.API.MockClient, for: Setlistify.Tidal.API)
Application.put_env(:setlistify, :tidal_api_client, Setlistify.Tidal.API.MockClient)
```

If you added a `DeveloperTokenManager`, also add:

```elixir
Application.put_env(:setlistify, :start_tidal_token_manager, false)
```

Tests set expectations with `Hammox.expect/3` or `Hammox.stub/3`.

---

## Step 16: Add environment variables

Add credentials to `.env` (copy `.env.example` as a starting point) and wire them into
`config/runtime.exs`.

**OAuth provider:**
```
TIDAL_CLIENT_ID=...
TIDAL_CLIENT_SECRET=...
```

**Developer-token provider (app-level JWT):**
```
TIDAL_TEAM_ID=...
TIDAL_KEY_ID=...
TIDAL_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
```

Read them in `ExternalClient` (and `DeveloperTokenManager` if applicable) via
`Application.fetch_env!/2`.

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
