# Architecture Decision Record: Tidal Integration

**Title**: Tidal Integration as a Third Music Provider
**Status**: Proposed
**Date**: 2026-06-02
**Decision Makers**: Troy (Project Lead), Claude Code (Development Assistant)

## Context and Problem Statement

Setlistify supports Spotify and Apple Music for playlist creation (see ADR-003). Issue #135 adds Tidal as a third provider with full feature parity: song search, playlist creation, and playlist display. It exists for two reasons:

1. **Direct value** — Tidal users get the same setlist-to-playlist UX as Spotify and Apple Music users.
2. **Rule-of-Three evidence for #130** — The artist-validation + cover-artist-fallback policy currently byte-duplicated in `Spotify.API.ExternalClient` and `AppleMusic.API.ExternalClient` will be re-derived a third time in `Tidal.API.ExternalClient` following the same pattern. The shape of that third derivation tells us whether #130's proposed `MusicService.TrackSearch` lift is the right abstraction.

The bulk of the supporting architecture is already in place from ADR-003: `Setlistify.MusicService.API` dispatches by `UserSession` struct, `Setlistify.UserSessionManager` dispatches by `{provider, user_id}` key, OTel attributes are already provider-agnostic (`music.*`, `playlist.*`, `track.id`), Registry keys are already namespaced, and `docs/adding-a-music-provider.md` is current. So Tidal does **not** need a "preparatory Spotify refactors" wave — most of that work happened during the Apple Music rollout.

The novelty in Tidal is in the protocol details:

- OAuth 2.1 with **mandatory PKCE**
- **JSON:API content type** (`application/vnd.api+json`)
- A **path-segment search** endpoint (`/v2/searchResults/{url-encoded-query}`)
- A required `countryCode` on every catalog call
- **24-hour access tokens** with standard refresh-token rotation
- A documented **~1 req/5 sec rate limit per token**
- No app-level signed token (no `DeveloperTokenManager` equivalent)

### Constraints

- No database — everything in-memory with GenServer (established by ADR-001)
- One service active at a time per user
- Must preserve full test coverage with Hammox mocking pattern
- TDD approach throughout
- Tidal uses server-side OAuth 2.1 (PKCE mandatory) with short-lived access tokens that require refresh

## Decision Drivers

1. **Feature parity** — Tidal users should have an experience identical to Spotify/Apple Music users
2. **Minimal web layer coupling** — LiveViews should not need to know which provider is active (already achieved by ADR-003)
3. **Test compatibility** — existing mock infrastructure should require minimal changes
4. **Observability** — cross-provider trace filtering in Grafana/Tempo without per-provider attribute namespaces
5. **Provider isolation** — Tidal-specific logic must not bleed into Spotify/Apple Music
6. **Incremental delivery** — Tidal's protocol uncertainties (PKCE, JSON:API, rate limits) should be validated before broad implementation
7. **Avoid premature abstraction** — defer the #130 policy lift until a third concrete data point exists

## Phase Shape

Three phases — no separate "preparatory Spotify refactors" wave (none needed):

- **Phase 0 — Auth spike.** Validate the uncertainty hot-spots end-to-end (PKCE flow, path-segment search with JSON:API parsing, `meta.positionBefore` semantics for add-tracks, real-world rate-limit behavior, ISRC availability). Gates Phase 1. Spike code may be throwaway.
- **Phase 1 — Implementation.** Seven issues, each a single PR-sized unit. Follows `docs/adding-a-music-provider.md` end-to-end.
- **Phase 2 — Wrap-up.** Three issues: #130 evaluation with a third data point; rate-limit telemetry review after real traffic; doc updates.

## Considered Options

Only Tidal-specific decisions warrant options analysis. The dispatch architecture (separate `UserSession` structs + thin `MusicService.API` dispatch) is already decided in ADR-003 and is not reopened here.

### PKCE state storage

**Option A — Dedicated `Auth.PKCEStore` GenServer + ETS table.** A new process holds `{state_nonce → code_verifier}` across the auth redirect, with a periodic sweep of stale entries.

- Pros: handles concurrent same-browser sign-in attempts cleanly; reusable for the next OAuth provider.
- Cons: new module, new supervision child, new ETS table, new test file; introduces a second pattern for short-lived per-flow OAuth state when one already exists.

**Option B — Session cookie, mirroring the existing `:oauth_state` pattern. (Chosen.)** The `code_verifier` is generated before the authorize redirect and stored in the session cookie next to the existing `:oauth_state` nonce, then replayed (and deleted) in the token exchange.

- Pros: ~12 LOC beyond Spotify's existing flow; no new module/process/table; reuses a pattern the team already understands.
- Cons: concurrent multi-tab sign-in attempts can overwrite each other's verifier — an edge case Spotify already accepts for `:oauth_state`.

**Decision: Option B.** Matching the existing pattern beats introducing a new one. The cookie is signed/encrypted, same-site, and already survives the OAuth round-trip for `:oauth_state`.

### Rate-limit handling

**Option A — Per-user `Tidal.RateLimiter` GenServer in v1.** Coordinate request pacing to stay under the ~1 req/5 sec budget.

- Pros: smooth UX under burst.
- Cons: over-engineering before we have real usage data; the search fan-out pattern's real-world 429 incidence is unknown.

**Option B — Telemetry only in v1, evaluate in Phase 2. (Chosen.)** Surface 429s as `{:error, :rate_limited, retry_after}`, instrument with OTel, and decide on coordination after observing real traffic.

**Decision: Option B.** Ship a possibly-rough UX for Tidal-heavy users in exchange for not over-engineering before we have data. The per-user limiter is a well-understood follow-up if Phase 2 telemetry shows it's needed.

### Country code storage

**Option A — Fetch `countryCode` per call from `/v2/users/me`.** Adds a network round-trip to every catalog operation.

**Option B — Store `:country_code` in the `UserSession` struct + session cookie. (Chosen.)** Fetched once at auth-code exchange; restoration is a pure constructor.

**Decision: Option B**, mirroring Apple Music's `storefront` handling.

## Decision

Implement Tidal as a third provider following the ADR-003 dispatch architecture, with these Tidal-specific decisions:

### 1. `Tidal.UserSession` carries `:country_code`

```elixir
defmodule Setlistify.Tidal.UserSession do
  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :username, :country_code]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :username, :country_code]
end
```

Tidal requires `countryCode` on essentially every catalog request, mirroring Apple Music's `storefront`. It is fetched once from `/v2/users/me` during the auth-code exchange and stored in the struct + session cookie so restoration is a pure constructor (no `/me` round-trip). On missing/invalid `country` at sign-in: **fail loud with a flash**, do not default to `"US"`.

### 2. PKCE state lives in the session cookie

Tidal requires OAuth 2.1 with mandatory PKCE. The flow needs a `code_verifier` (43–128 char random unreserved string) generated before the authorize redirect and replayed in the token exchange — identical in lifecycle to the existing `:oauth_state` nonce that Spotify's `sign_in/2` already puts in the session.

- `sign_in/2`: `put_session(:pkce_code_verifier, verifier)` next to the existing `put_session(:oauth_state, state)`.
- `new/2`: `get_session(:pkce_code_verifier)`, `delete_session(:pkce_code_verifier)` (single-use), pass to `Tidal.API.exchange_code(code, redirect_uri, verifier)`.

Crypto (built into OTP, no library needed):

```elixir
verifier  = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
```

This adds ~12 LOC beyond Spotify's existing flow. No new module, supervision child, or ETS table.

### 3. Rate limiting — telemetry only in v1

The `ExternalClient` will:

- Surface 429s as `{:error, :rate_limited, retry_after_seconds}` rather than retrying silently.
- Use **provider-agnostic OTel attributes** (per ADR-003's generalization away from `<provider>.*` namespaces): the standard `http.status_code` semconv attribute on every span; on 429, a `http.rate_limited` span event with `http.response.header.retry_after` as its attribute. Provider identity is carried by `peer.service`, set by `MusicService.API.impl/1`.
- Add a telemetry metric for 429 counts, labeled by `music.service`, so per-provider filtering works in Grafana without a provider-prefixed namespace.

The LiveView already runs track searches concurrently via `assign_async` — that fan-out will probably 429 under burst. The Phase 2 telemetry review reads the real data and decides whether to add coordination then.

### 3a. Possible batch-lookup optimization via ISRC

Tidal v2 has no batch search-by-query endpoint (one `searchResults/{query}` per call — search remains rate-limit-bound). But `GET /v2/tracks?filter[isrc]=A,B,C&countryCode=US` supports batch lookup by ISRC, up to 20 per call. If setlist.fm provides ISRCs in the song data Setlistify already fetches, the spike should test ISRC-first lookup with search as the fallback for songs without ISRCs. For a setlist with full ISRC coverage this drops ~25 search calls to ~2 batched lookup calls. Validated in the Phase 0 spike; implemented only if data confirms.

### 4. Embed previews included (like Spotify)

`MusicService.API.get_embed("tidal", url)` wires through to the Tidal oEmbed endpoint or returns a deterministic `https://embed.tidal.com/tracks/{id}` iframe. `Playlists.ShowLive.handle_params/3` gets a `"tidal"` clause that mirrors the Spotify path, not the Apple Music link-to-library path.

### 5. `:tidal_refresh_token` as a dedicated session key

Do not reuse Spotify's `:refresh_token` session key — disambiguate so both providers can coexist in `UserAuth.auth_user/2`. Add `Setlistify.Auth.TokenSalts.tidal_refresh_token/0` returning `"tidal refresh token"`. Leave Spotify's existing salt + key unchanged to avoid invalidating existing cookies.

### 6. #130 evaluation is a Phase 2 deliverable

A dedicated Phase 2 issue compares the three `ExternalClient` modules side-by-side once Tidal's exists. It comments on #130 with the decision (full lift, partial lift, or no lift) and either files a follow-up implementation issue or closes #130 with rationale.

## Implementation Details

### PKCE Flow + Code Verifier Lifecycle

```
sign_in/2   state     = :crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false)   # existing CSRF nonce
            verifier  = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)    # NEW
            challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)  # NEW
            put_session(:oauth_state, state)
            put_session(:pkce_code_verifier, verifier)                                         # NEW
            redirect → https://login.tidal.com/authorize?
                       client_id & response_type=code & redirect_uri & state &
                       scope & code_challenge=CHALLENGE & code_challenge_method=S256           # NEW

[user approves at Tidal — Tidal binds {code, challenge} server-side]

new/2       assert state == get_session(:oauth_state)            # existing CSRF check
            verifier = get_session(:pkce_code_verifier)          # NEW
            delete_session(:pkce_code_verifier)                  # single-use
            Tidal.API.exchange_code(code, redirect_uri, verifier)
              → POST token endpoint with grant_type, code, redirect_uri,
                client_id, client_secret, code_verifier          # code_verifier is NEW
            ← { access_token, refresh_token, expires_in, ... }
            fetch country from /v2/users/me; build UserSession
            start session process, auth_user(...)
```

The token-endpoint host (`login.tidal.com` vs `auth.tidal.com`) and exact `scope` values are confirmed in the Phase 0 spike before this is written.

### Rate Limit Strategy (deferred)

In v1, no coordination layer. `ExternalClient` returns `{:error, :rate_limited, retry_after}` on 429 and records:

- `http.status_code` (semconv) on every HTTP span
- on 429, a `http.rate_limited` span event carrying `http.response.header.retry_after`

Provider identity is `peer.service` (set by `MusicService.API.impl/1`) — **never** a `tidal.*` attribute namespace. A 429-count telemetry metric is labeled by `music.service`.

Phase 2 reviews real traffic (filtered on `peer.service = "tidal"`) and decides whether a per-user `Tidal.RateLimiter` GenServer is warranted.

### JSON:API Request/Response Shape

Tidal v2 speaks JSON:API:

- Requests set `content-type` and `accept` to `application/vnd.api+json`.
- Search: `GET /v2/searchResults/{url-encoded-query}?countryCode=US&include=tracks,tracks.artists` — the query is a path segment, and related artists arrive in the top-level `included` array, resolved by `relationships` references rather than nesting.
- Playlist creation: `POST /v2/playlists` with a JSON:API `data` body and an `Idempotency-Key` header.
- Add tracks: `POST /v2/playlists/{id}/relationships/items` in 20-track chunks; whether `meta.positionBefore` is required is confirmed in the spike.

The artist-match + cover-fallback policy is re-derived **verbatim** from the Spotify/Apple Music implementations inside `Tidal.API.ExternalClient.search_for_track/4` — this duplication is the deliberate third data point for #130.

### Track ID Abstraction

Already in place from ADR-003. Tidal track IDs (numeric catalog IDs) fit the existing provider-opaque `:track_id` convention; `add_tracks_to_playlist/3` knows how to interpret them. No changes to the search-result type.

### Telemetry Attribute Conventions

Follow ADR-003's provider-agnostic mapping (`music.artist`, `music.track`, `track.id`, `playlist.*`). Tidal adds no new namespaced attributes. The one Tidal-relevant addition is HTTP rate-limit handling, expressed entirely in OTel semantic conventions: `http.status_code` plus a `http.rate_limited` span event with `http.response.header.retry_after`. There is **no `tidal.*` namespace**.

### File Structure

```
lib/setlistify/
  auth/
    token_salts.ex                      # extend — add tidal_refresh_token/0
  tidal/
    user_session.ex                     # new
    session_manager.ex                  # new — OAuth+refresh variant
    session_supervisor.ex               # new — thin DynamicSupervisor wrapper
    api.ex                              # new — @behaviour MusicService.API + exchange_code/3, refresh_*
    api/
      external_client.ex                # new — HTTP impl + policy re-derivation
  music_service/
    api.ex                              # extend — Tidal dispatch + get_embed clause
  user_session_manager.ex               # extend — Tidal clauses
  application.ex                        # extend — :tidal_track_cache

lib/setlistify_web/
  plugs/
    restore_tidal_token.ex              # new — network-call variant (short-lived tokens)
  controllers/
    oauth_callback_controller.ex        # extend — Tidal sign_in/new/sign_out (PKCE)
    user_auth.ex                        # extend — preserve :tidal_refresh_token, :tidal_country_code
  auth/
    live_hooks.ex                       # extend — "tidal" to_provider_key clause
  router.ex                             # extend — RestoreTidalToken in :browser pipeline
  live/
    setlists/show_live.ex               # extend — provider/1 clause, sign-in option
    playlists/show_live.ex              # extend — "tidal" handle_params clause (embed)
  components/
    layouts/app.html.heex               # extend — Tidal header button + icon

config/runtime.exs                      # extend — TIDAL_CLIENT_ID, TIDAL_CLIENT_SECRET
test/test_helper.exs                    # extend — Tidal mock registration
.env.example                            # extend — TIDAL_* env vars
```

### Existing Functions / Utilities to Reuse

- **`Setlistify.Cache.fetch/3`** — OTel-aware Cachex wrapper used by both existing providers; Tidal's `search_for_track/4` calls through it identically.
- **`Setlistify.Spotify.SessionManager`** — template for `Tidal.SessionManager` (OAuth-with-refresh variant); same shape, different aliases and Registry keys.
- **`Setlistify.Spotify.API.ExternalClient.with_token_refresh/3`** — template for Tidal's 401-retry wrapper.
- **`SetlistifyWeb.Plugs.RestoreSpotifyToken`** — template for `RestoreTidalToken` (network-call variant, since Tidal access tokens are short-lived).
- **`Setlistify.Spotify.API.ExternalClient.artist_match?/2`** and **`normalize_artist/1`** — duplicated verbatim in `Tidal.API.ExternalClient`; the duplication is the #130 evidence.
- **`OpenTelemetry.Tracer` patterns** — copy the span-naming convention `"Setlistify.<Module>.<function>"` and the generic attribute keys.

## Implementation Plan

The work is tracked as a GitHub project mirroring the Apple Music project (#2). Issue numbers below are placeholders for the GitHub issues to be filed.

### Phase 0 — Auth Spike (gate to Phase 1)

**Validate Tidal API end-to-end.** Spike code may be a Mix task, IEx session, or temporary controller — disposable.

- Register an app at developer.tidal.com; record Client ID + Client Secret format
- Throwaway PKCE auth flow: generate verifier + challenge, redirect to `https://login.tidal.com/authorize`, handle callback, exchange code; record **which host the code exchange wants** (`login.tidal.com` vs `auth.tidal.com`)
- Call `GET /v2/users/me`; record response shape and the `country` value format (alpha-2? alpha-3? null possible?)
- Call `GET /v2/searchResults/{query}?countryCode=US&include=tracks,tracks.artists` with two real artist/track pairs; record JSON:API `included` resolution
- Create one playlist via `POST /v2/playlists`; record accepted `accessType` values
- Add 3 tracks via `POST /v2/playlists/{id}/relationships/items` — **with and without `meta.positionBefore`** — record what works
- Burst 30 sequential search requests with 200 ms gaps; record 429 incidence and `Retry-After` values
- Confirm `https://embed.tidal.com/tracks/{id}` renders without auth
- **Check whether setlist.fm song data already includes ISRC codes.** If yes, test `GET /v2/tracks?filter[isrc]=A,B,C&countryCode=US` with 5–20 ISRCs and record the response shape (informs §3a)
- Document all answers in the issue body before closing

**Gate:** Phase 1 may not begin until this issue closes with documented answers.

### Phase 1 — Implementation (7 issues)

Each PR is independently mergeable. Issues numbered in dependency order.

1. **chore: add Tidal env vars + `TokenSalts.tidal_refresh_token`**
   - `TIDAL_CLIENT_ID`, `TIDAL_CLIENT_SECRET` in `.env.example` + `config/runtime.exs`
   - `Setlistify.Auth.TokenSalts.tidal_refresh_token/0` returns `"tidal refresh token"`

2. **feat: implement `Tidal.UserSession`, `SessionManager`, `SessionSupervisor`**
   - `@enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :username, :country_code]`
   - `SessionManager` mirrors `Spotify.SessionManager` (OAuth + refresh timer); Registry key `{:tidal, user_id}`; PubSub `{:token_refreshed, session}` on `"user:#{user_id}"`
   - `SessionSupervisor` thin wrapper around `Setlistify.UserSessionSupervisor`
   - Unit tests parallel to existing Spotify session tests

3. **feat: implement `Tidal.API` + `Tidal.API.ExternalClient`**
   - `Tidal.API`: `@behaviour Setlistify.MusicService.API`; declares `exchange_code/3` (PKCE verifier), `refresh_token/1`, `refresh_to_user_session/1`, `get_embed/1`; `search_for_track/4` wraps `Cachex.fetch(:tidal_track_cache, ...)` with OTel context propagation
   - `Tidal.API.ExternalClient` full HTTP impl: JSON:API client; `with_token_refresh/3` for 401 → refresh → retry once; path-segment search with `countryCode` and JSON:API `included` artist resolution; re-derived artist-match + cover-fallback policy (the #130 evidence); optional `filter[isrc]` fast path if the spike confirms ISRC availability; `create_playlist/3` with `Idempotency-Key`; `add_tracks_to_playlist/3` in 20-track chunks; `exchange_code/3` chasing `country` from `/v2/users/me`; refresh paths preserving `country_code`; 429 surfaced as `{:error, :rate_limited, retry_after}` with semconv `http.status_code` + `http.rate_limited` span event — **no `tidal.*` attributes**
   - Unit tests via `Req.Test` plug intercept

4. **chore: register Tidal Cachex cache + Hammox mock**
   - `:tidal_track_cache` Cachex child in `Setlistify.Application`
   - `Hammox.defmock(Setlistify.Tidal.API.MockClient, for: Setlistify.Tidal.API)` and `Application.put_env(:setlistify, :tidal_api_client, ...)` in `test/test_helper.exs`

5. **feat: Tidal OAuth+PKCE callback + sign-in handlers**
   - `OAuthCallbackController.sign_in/2` Tidal clause: generate state + verifier + challenge; put both in session; redirect with `code_challenge`, `code_challenge_method=S256`, `scope`, `state`
   - `new/2` Tidal clause: validate state, read + delete `:pkce_code_verifier`, `exchange_code/3`, encrypt refresh token with `tidal_refresh_token` salt, start session, set session keys, `UserAuth.auth_user/2`
   - `sign_out/2` Tidal case clause
   - `UserAuth.auth_user/2` extended to preserve `:tidal_refresh_token` and `:tidal_country_code` across `renew_session/1`
   - Controller tests: state mismatch, missing verifier, success, exchange failure

6. **feat: `RestoreTidalToken` plug + router wiring**
   - Mirrors `RestoreSpotifyToken`, guarded by `auth_provider == "tidal"`; decrypts refresh token; if no live session process, calls `refresh_to_user_session/1` then `start_user_token/2`; clears session + flashes on failure
   - Added to `:browser` pipeline after the Apple Music plug
   - Plug tests parallel to `restore_spotify_token_test.exs`

7. **feat: dispatch + UI wiring for Tidal**
   - `MusicService.API`: alias Tidal; extend `@type user_session` union; `impl/1` clause for `%Tidal.UserSession{}` setting `peer.service: "tidal"`; `get_embed("tidal", url)` clause
   - `UserSessionManager`: extend `@type` unions; `impl/1` clauses for `%Tidal.UserSession{}` and `{:tidal, _}`
   - `LiveHooks.to_provider_key("tidal", user_id)` clause
   - `Setlists.ShowLive.provider/1` clause; `Playlists.ShowLive.handle_params/3` `"tidal"` clause (embed, Spotify-style)
   - `Layouts` user-display helpers; Tidal header sign-in button; Tidal added to the unauthenticated sign-in options on `Setlists.ShowLive`

### Phase 2 — Wrap-Up (3 issues)

1. **chore: evaluate #130 policy lift with three providers**
   - Side-by-side diff of `artist_match?/2` / `normalize_artist/1` / cover-fallback / policy-boundary telemetry across all three providers
   - Identify provider-specific leakage (e.g., Tidal's JSON:API `included` walking)
   - Comment outcome on #130 (full / partial / no lift); file a follow-up issue or close with rationale

2. **chore: review Tidal rate-limit telemetry, decide on per-user limiter**
   - After ~2 weeks of real traffic, query Grafana (filtered on `peer.service = "tidal"`): 429 incidence, `http.response.header.retry_after` distribution from `http.rate_limited` events, playlist-creation duration p50/p95
   - Decide: ship as-is / add per-user `Tidal.RateLimiter` / add UI progress hints; file follow-up if needed

3. **docs: update `adding-a-music-provider.md` with Tidal lessons**
   - PKCE callout (generate verifier + challenge in `sign_in/2`, store in session next to `:oauth_state`, replay in token exchange)
   - Rate-limiting callout (surface 429 as `{:error, :rate_limited, retry_after}`; record via semconv `http.status_code` + `http.rate_limited` span event — never a `<provider>.*` namespace)
   - Region-scoping callout (Apple Music `storefront`, Tidal `country_code`) as a per-user session field
   - JSON:API note if Tidal's response shape needed nontrivial parsing
   - Confirm the existing checklist still accurate

## Consequences

### Positive

- ✅ Tidal users get full feature parity with Spotify and Apple Music
- ✅ Reuses the ADR-003 dispatch architecture wholesale — no web-layer changes beyond provider clauses
- ✅ PKCE adds ~12 LOC with no new process or table by reusing the `:oauth_state` cookie pattern
- ✅ Provides the third data point needed to settle the #130 abstraction question with evidence rather than speculation
- ✅ OTel stays provider-agnostic — Grafana queries filter by `peer.service`, not by attribute namespace

### Negative

- ❌ Tidal's ~1 req/5 sec rate limit may produce a rough UX under burst until Phase 2 evaluates a limiter
- ❌ The artist-match/cover-fallback policy is duplicated a third time before any lift (deliberate, but it is debt until #130 resolves)
- ❌ Concurrent multi-tab sign-in can overwrite the cookie-stored PKCE verifier (edge case, already accepted for `:oauth_state`)

### Neutral

- Tidal access tokens are short-lived (24h), so `RestoreTidalToken` makes a network call on restoration — unlike Apple Music's pure-cookie restoration, like Spotify's refresh path
- Tidal IDs fit the existing provider-opaque `:track_id` convention with no type changes

## Implementation Status

### Completed

*(None yet — this ADR is Proposed.)*

### Remaining Work

- Phase 0: Tidal auth spike
- Phase 1: Implementation (7 issues)
- Phase 2: Wrap-up (3 issues)

## Success Metrics

- Tidal sign-in → view setlist → create playlist → playlist appears in the Tidal app → embed renders on `/playlists`, end-to-end
- A 20+ song setlist exercises real rate-limit behavior (feeds the Phase 2 telemetry review)
- `mix test` passes with full coverage across all three providers
- `grep -rn "Spotify.API" lib/setlistify_web/live/` still returns 0 results (provider-agnosticism preserved)
- All three providers' `search_for_track` callbacks share identical `@callback` signatures (Dialyzer-enforced)
- 429 events are filterable in Grafana by `peer.service = "tidal"` with no `tidal.*` attribute namespace

## References

- [TIDAL API Reference](https://tidal-music.github.io/tidal-api-reference/)
- [TIDAL Developer Portal](https://developer.tidal.com/)
- [OAuth 2.1 / PKCE (RFC 7636)](https://datatracker.ietf.org/doc/html/rfc7636)
- [JSON:API Specification](https://jsonapi.org/)
- [ADR-001: Token Session Management](001-token-session-management.md)
- [ADR-003: Apple Music Integration](003-apple-music-integration.md)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- `docs/adding-a-music-provider.md`
