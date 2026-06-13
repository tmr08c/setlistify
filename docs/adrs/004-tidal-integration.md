# Architecture Decision Record: Tidal Integration

**Title**: Tidal Integration as a Third Music Provider
**Status**: Accepted
**Date**: 2026-06-02 (Phase 0 spike findings incorporated 2026-06-08, see #137)
**Decision Makers**: Troy (Project Lead), Claude Code (Development Assistant)

## Context and Problem Statement

Setlistify supports Spotify and Apple Music for playlist creation (see ADR-003). Issue #135 adds Tidal as a third provider with full feature parity: song search, playlist creation, and playlist display. It exists for two reasons:

1. **Direct value** — Tidal users get the same setlist-to-playlist UX as Spotify and Apple Music users.
2. **Rule-of-Three evidence for #130** — The artist-validation + cover-artist-fallback policy currently byte-duplicated in `Spotify.API.ExternalClient` and `AppleMusic.API.ExternalClient` will be re-derived a third time in `Tidal.API.ExternalClient` following the same pattern. The shape of that third derivation tells us whether #130's proposed `MusicService.TrackSearch` lift is the right abstraction.

The bulk of the supporting architecture is already in place from ADR-003: `Setlistify.MusicService.API` dispatches by `UserSession` struct, `Setlistify.UserSessionManager` dispatches by `{provider, user_id}` key, OTel attributes are already provider-agnostic (`music.*`, `playlist.*`, `track.id`), Registry keys are already namespaced, and `docs/adding-a-music-provider.md` is current. So Tidal does **not** need a "preparatory Spotify refactors" wave — most of that work happened during the Apple Music rollout.

The novelty in Tidal is in the protocol details:

- OAuth 2.1 with **mandatory PKCE for all clients** ([per Tidal's docs](https://developer.tidal.com/documentation/api-sdk/api-sdk-authorization): *"TIDAL (and OAuth 2.1) enforces Proof Key for Code Exchange (PKCE) for all clients"*) — no carve-out for confidential clients. Authorize endpoint is `https://login.tidal.com/authorize`; **token endpoint is `https://auth.tidal.com/v1/oauth2/token`** (verified in Phase 0 spike — ADR previously listed both hosts as candidates).
- **JSON:API content type** (`application/vnd.api+json`)
- A **path-segment search** endpoint (`/v2/searchResults/{url-encoded-query}`)
- A required `countryCode` on every catalog call
- **4-hour access tokens** (`expires_in: 14400`, verified in spike — ADR originally said 24h based on documentation guess) with refresh via `grant_type=refresh_token`. **Tidal does NOT rotate refresh tokens** (verified in spike — refresh response carries only `access_token`, `expires_in`, `scope`, `token_type`, `user_id`; no new `refresh_token` field). The same refresh token is reused indefinitely until revoked or replaced by a fresh user sign-in.
- **Access tokens are ES256-signed JWTs (not opaque)** carrying `uid` and `cc` claims (verified in spike). This enables a JWT-derivation shortcut for `user_id` + `country_code` instead of calling `/v2/users/me` — see §1 below for the chosen approach and risk mitigations.
- **Rate limits measured in spike**: ~8-request burst capacity, then ~2-3 sustained req/sec, with a flat `Retry-After: 4` on every 429. Tidal publishes no numeric thresholds; the spike is the only source of these numbers. See §3 below.
- **Dev redirect URI must be `127.0.0.1`, not `localhost`** — Tidal's dev portal enforces "no localhost" on save regardless of app mode (verified in spike). Prod URIs must be HTTPS on a real domain.
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
- **Phase 2 — Wrap-up.** Three issues: #130 evaluation with a third data point; rate-limit telemetry review after real traffic; doc updates. Plus one conditional ISRC fast-path issue, gated on the spike + telemetry findings.

## Considered Options

Only Tidal-specific decisions warrant options analysis. The dispatch architecture (separate `UserSession` structs + thin `MusicService.API` dispatch) is already decided in ADR-003 and is not reopened here.

### PKCE state storage

**Option A — Dedicated `Auth.PKCEStore` GenServer + ETS table.** A new process holds `{state_nonce → code_verifier}` across the auth redirect, with a periodic sweep of stale entries.

- Pros: handles concurrent same-browser sign-in attempts cleanly; reusable for the next OAuth provider.
- Cons: new module, new supervision child, new ETS table, new test file; introduces a second pattern for short-lived per-flow OAuth state when one already exists.

**Option B — Session cookie, mirroring the existing `:oauth_state` pattern. (Chosen.)** The `code_verifier` is generated before the authorize redirect and stored in the session cookie next to the existing `:oauth_state` nonce, then replayed (and deleted) in the token exchange.

- Pros: small, contained change beyond Spotify's existing flow; no new module/process/table; reuses a pattern the team already understands.
- Cons: concurrent multi-tab sign-in attempts can overwrite each other's verifier — an edge case Spotify already accepts for `:oauth_state`.

**Decision: Option B.** Matching the existing pattern beats introducing a new one. The cookie is signed/encrypted, same-site, and already survives the OAuth round-trip for `:oauth_state`.

### Rate-limit handling

(Originally considered as a two-option choice before the Phase 0 spike supplied real rate-limit numbers. The spike measured a ~8-request burst capacity, then ~2-3 sustained req/sec with `Retry-After: 4` flat. With that data in hand the original "telemetry only, decide later" stance is partially superseded by a known-needed concurrency cap; see §3 below.)

**Option A — Per-user `Tidal.RateLimiter` GenServer in v1.** Coordinate request pacing to stay under the budget.

- Pros: smooth UX under burst.
- Cons: over-engineering before we have real usage data; the search fan-out pattern's real-world 429 incidence was unknown at original ADR time.

**Option B — Telemetry only in v1, evaluate in Phase 2. (Originally chosen.)** Surface 429s as `{:error, {:rate_limited, retry_after}}` (2-tuple, fits the existing callback's `{:error, atom() | {atom(), term()}}` union), instrument with OTel, and decide on coordination after observing real traffic.

**Option C — Lightweight per-app concurrency cap inside `Tidal.API.ExternalClient` in v1 + telemetry. (Chosen after spike.)** Cap in-flight Tidal requests at a small number (e.g. 4) via a small semaphore inside the Tidal module — calls above the cap queue. Plus telemetry per Option B. No impact on Spotify or Apple Music. Still defer the full per-user `Tidal.RateLimiter` to Phase 2 if telemetry shows the simple cap is insufficient.

**Decision: Option C.** The spike data showed the LiveView's `assign_async` fan-out across 20+ songs WILL 429 about halfway through — it's no longer a "maybe needed in Phase 2," it's a "known broken in Phase 1." A small Tidal-scoped concurrency cap is cheap and provider-isolated. The Phase 2 review still happens — it just decides on per-user pacing vs. accepting the cap as sufficient.

### Country code storage

**Option A — Fetch `countryCode` per call from `/v2/users/me`.** Adds a network round-trip to every catalog operation.

**Option B — Store `:country_code` in the `UserSession` struct + session cookie. (Chosen.)** Fetched once at auth-code exchange; restoration is a pure constructor.

**Decision: Option B**, mirroring Apple Music's `storefront` handling.

## Decision

Implement Tidal as a third provider following the ADR-003 dispatch architecture, with these Tidal-specific decisions:

### 1. `Tidal.UserSession` carries `:country_code`; derived from the access-token JWT (not `/me`)

```elixir
defmodule Setlistify.Tidal.UserSession do
  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :country_code]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :country_code]
end
```

No `:username` field — Tidal's `/me` username is just the user's email, and we don't display it. Mirrors Apple Music's no-username pattern; UX is fine.

Tidal requires `countryCode` on essentially every catalog request, mirroring Apple Music's `storefront`. It is stored in the struct + session cookie under the unprefixed key `:country_code` (consistent with Apple Music's unprefixed `:storefront`). Restoration reads it from the cookie without a network round-trip.

**Where `:country_code` and `:user_id` come from**: decoded from the access-token JWT claims (`cc` and `uid` respectively), NOT from a `GET /v2/users/me` call. Verified in the Phase 0 spike — the JWT's `cc`/`uid` values match `/me`'s `country`/`id` exactly, and using the JWT saves a network round-trip at sign-in.

**This is a deliberate non-standard reliance on JWT internals** (the OAuth spec says treat access tokens as opaque). Risk mitigations are load-bearing here:

- Use `Map.fetch!/2` on the decoded claims so a missing or renamed claim **blows up loudly at sign-in** rather than producing a silently broken session.
- Add a clear comment at the JWT-decode call site naming the deliberate non-standard choice and the fallback recipe: *"if Tidal rotates JWT claims or moves to opaque access tokens, switch this back to a `GET /v2/users/me` call — response shape documented in ADR-004 §1 and the issue #137 findings."*
- Do NOT add graceful fallback inside the constructor. One failing sign-in is preferable to a silently broken session.

The Apple Music `/me`-equivalent decision (Option B, kept `/me` for durability) was considered and rejected in favor of Option A (JWT-derived) per the §1 spike-findings discussion in issue #137.

On missing/invalid `cc` claim at sign-in: **fail loud with a flash**, do not default to `"US"`.

### 2. PKCE state lives in the session cookie

Tidal mandates PKCE for *all* clients, including confidential ones with a `client_secret` ([per their authorization docs](https://developer.tidal.com/documentation/api-sdk/api-sdk-authorization)). The flow needs a `code_verifier` (43–128 char random unreserved string) generated before the authorize redirect and replayed in the token exchange — identical in lifecycle to the existing `:oauth_state` nonce that Spotify's `sign_in/2` already puts in the session.

- `sign_in/2`: `put_session(:pkce_code_verifier, verifier)` next to the existing `put_session(:oauth_state, state)`.
- `new/2`: `get_session(:pkce_code_verifier)`, `delete_session(:pkce_code_verifier)` (single-use), pass to `Tidal.API.exchange_code(code, redirect_uri, verifier)`.

Crypto (built into OTP, no library needed):

```elixir
verifier  = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
```

The helpers are inlined as private functions in `OAuthCallbackController` — no separate `Setlistify.Auth.PKCE` module. If a second OAuth-PKCE provider arrives and the crypto duplicates, extract then. No new supervision child or ETS table.

### 3. Rate limiting — Tidal-scoped concurrency cap in v1 + telemetry

**Spike-measured behavior** (Phase 0, 30 sequential search requests at 200 ms gaps): ~8-request burst capacity before first 429, then a ~2-success/~2-failure alternating pattern (≈ 2–3 sustained req/sec). `Retry-After: 4` seconds flat on every 429 — never varying, never exponential. Real recovery is faster than the advertised 4 s (got 200s within ~400 ms of 429s in some windows), so honoring `Retry-After` literally is safe but pessimistic.

With LiveView's `assign_async` firing searches concurrently for every song in a setlist, a 20-song setlist **will** 429 about halfway through. This is no longer hypothetical.

The `ExternalClient` will:

- **Cap in-flight Tidal HTTP calls at 4** via a small semaphore (`Setlistify.Tidal.RequestThrottle` GenServer or `:counters`-based; named singleton supervised under the Tidal subtree). All `ExternalClient` HTTP-issuing functions acquire-then-release around the Req call. Calls above the cap queue rather than fire-and-429. This is fully encapsulated inside the Tidal module — Spotify and Apple Music are not affected and the LiveView fan-out logic does not change. The cap value (4) is sized to stay inside the spike's measured burst capacity (8) with headroom; it's a `@throttle_concurrency` module attribute that can be tuned without touching call sites.
- Surface 429s that DO occur (despite the cap — e.g., across multiple users sharing the same app credential, or transient spikes) as `{:error, {:rate_limited, retry_after_seconds}}` — a **2-tuple** preserving the existing `MusicService.API` callback shape (`{:error, atom() | {atom(), term()}}`). The callback type widens slightly; Spotify and Apple Music remain free to emit only the bare `{:error, atom()}` variants they already do, so no behavioral change there. The LiveView pattern-matches the inner `{:rate_limited, retry_after}` tuple to surface a retry hint if desired.
- Use **provider-agnostic OTel attributes** (per ADR-003's generalization away from `<provider>.*` namespaces): the standard `http.status_code` semconv attribute on every span; on 429, a `http.rate_limited` span event with `http.response.header.retry_after` as its attribute. Provider identity is carried by `peer.service`, set by `MusicService.API.impl/1`.
- Add a telemetry metric for 429 counts, labeled by `music.service`, so per-provider filtering works in Grafana without a provider-prefixed namespace. Also emit a metric for queue wait time on the throttle so we can see whether the cap is squeezing concurrency too tight.

The Phase 2 telemetry review then has two questions instead of one: (a) is the simple cap sufficient, or do we need per-user pacing for multi-user scenarios? (b) is the cap value of 4 correct, or should it be tuned up/down?

### 3a. ISRC batch-lookup — deferred indefinitely (setlist.fm doesn't carry ISRCs)

Tidal v2 has no batch search-by-query endpoint (one `searchResults/{query}` per call — search remains rate-limit-bound). However, `GET /v2/tracks?filter[isrc]=A,B,C&countryCode=US` supports batch lookup by ISRC, up to 20 per call. For a setlist where every song has an ISRC, this could drop ~25 search calls to ~2 batched lookup calls.

**Phase 0 finding (verified via direct `curl` against setlist.fm, bypassing our internal parser)**: setlist.fm song objects carry exactly one key (`name`), plus optional `cover`/`tape`/`info`/`with` fields. **Zero ISRC-related fields anywhere** in the response shape. Sample: setlist `2b75983e` (Tim Kasher, 15 songs) — every song was just `{"name": "..."}`.

The Tidal `filter[isrc]` endpoint itself was NOT verified in the spike because we have no clean source of ISRC values to test with — which is itself the evidence supporting the decision below.

**Decision**: downgrade from "Phase 2 follow-up after data justifies it" to **"deferred indefinitely"**. The optimization would require a secondary ISRC lookup (e.g., MusicBrainz by artist+title) per song before Tidal could be called — adding a third API hop to save one search call. Net loss in most scenarios. Re-open only if a future feature naturally surfaces ISRCs in the data pipeline (e.g., Spotify library import that carries full track metadata for some subset of songs).

### 4. Default playlist visibility = `UNLISTED`; link-out (like Apple Music), not embed (like Spotify)

**Spike findings that drove this decision**:

- `accessType` accepted values from `POST /v2/playlists`: `"PUBLIC"`, `"UNLISTED"`. `"PRIVATE"` is rejected with `INVALID_REQUEST_BODY`.
- `https://embed.tidal.com/playlists/{id}` returns **HTTP 200 with an error-dialog body for UNLISTED playlists** — only PUBLIC playlists actually render in the embed player. (Track embeds `https://embed.tidal.com/tracks/{id}` work without auth for any catalog track regardless.)
- **Tidal's "UNLISTED" is owner-only access**, not "link-shareable" in the YouTube sense: `https://tidal.com/playlist/{unlisted-id}` opens correctly for the playlist's owner (signed-in browser) but returns a 404-equivalent for any other user or signed-out session. So UNLISTED in Tidal is semantically closer to "PRIVATE" than to "unlisted" elsewhere.

Two coupled decisions:

1. **Default `accessType` for Setlistify-created playlists**: `UNLISTED`. Owner-only access matches the privacy preference; the user creates the playlist for themselves to play in their own Tidal client. (Sharing with friends is out of scope for Setlistify — users do that in Tidal's own UI if at all.)
2. **`/playlists` page behavior**: link out to tidal.com, do NOT embed. This mirrors Apple Music's existing `Playlists.ShowLive` clause (which links out to the library because Apple Music doesn't expose user-playlist embeds). Tidal's `Playlists.ShowLive.handle_params/3` clause uses the same link-out shape, NOT the Spotify embed shape. The link target is `https://tidal.com/playlist/{id}` — verified working for the owner.

`MusicService.API.get_embed("tidal", url)` is **not implemented** for Tidal — there is no `get_embed/2` Tidal clause. The `/playlists` page renders a "View on Tidal" link with the canonical `https://tidal.com/playlist/{id}` URL instead. (Track-level embeds for setlist preview, if ever needed elsewhere, remain available at `https://embed.tidal.com/tracks/{id}` — but no current code path needs them.)

If a future preference reverses to PUBLIC default + embed: re-add the `get_embed` Tidal clause and the `Playlists.ShowLive` embed clause; they're small, self-contained changes that would mirror the existing Spotify pattern.

### 5. Share the `:refresh_token` session key with Spotify; disambiguate by salt + `:auth_provider`

Tidal's refresh token has the same semantic shape as Spotify's (an OAuth refresh token). The existing codebase's pattern for per-provider session storage is:

| Layer | Pattern |
|---|---|
| Session cookie keys (e.g. `:refresh_token`, `:user_token`) | **Unprefixed** — each provider owns its own keys; only one provider is active at a time |
| Provider discriminator | `:auth_provider` (`"spotify"` / `"apple_music"`) |
| Phoenix token salts | **Prefixed** — `spotify_refresh_token`, `apple_music_user_token` |
| LiveHook assigns / events | **Prefixed** — e.g. `:apple_music_trigger`, `:apple_music_user_token` |

Tidal follows that pattern: reuse the `:refresh_token` session key, add `Setlistify.Auth.TokenSalts.tidal_refresh_token/0` returning `"tidal refresh token"` as a distinct salt, and rely on `:auth_provider` to discriminate at read sites. The encryption salt is the real safety boundary — a Tidal-encrypted token will fail to decrypt under the Spotify salt and vice versa, so even a degenerate state where `:auth_provider == "tidal"` coexists with a Spotify-encrypted `:refresh_token` resolves correctly: decryption fails, `RestoreTidalToken` clears the session, the user re-authenticates.

The (briefly considered) alternative was `:tidal_refresh_token` as a distinct session key — bulletproof against stale-cookie races but introduces a third storage pattern that's inconsistent with how Apple Music sits next to Spotify today. The shared-key + distinct-salt approach matches precedent.

`UserAuth.auth_user/2` already reads + re-puts `:refresh_token` across `renew_session/1`; no change is needed there. `OAuthCallbackController.sign_out/2` adds a `"tidal"` clause to its existing `{auth_provider, id}` match. `RestoreTidalToken` selects the `tidal_refresh_token` salt because the plug is provider-specific (`auth_provider == "tidal"` guard).

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
              → POST https://auth.tidal.com/v1/oauth2/token      # confirmed in Phase 0 spike
                with grant_type, code, redirect_uri,
                client_id, client_secret, code_verifier
            ← { access_token, refresh_token, expires_in: 14400, scope, token_type, user_id }
            decode access_token JWT → extract uid + cc claims    # NEW (see §1)
            build UserSession from JWT claims (NO /me call)
            start session process, auth_user(...)
```

**Confirmed in Phase 0 spike**:

- Authorize host: `https://login.tidal.com/authorize`
- Token endpoint: `https://auth.tidal.com/v1/oauth2/token` (the ADR originally listed both `login.tidal.com` and `auth.tidal.com` as candidates — `auth.tidal.com` is the winner)
- Scopes used: `user.read playlists.write` (space-separated). `user.read` covers the JWT `cc` claim availability; `playlists.write` covers create + add-tracks. `playlists.read` is NOT requested — we never list user playlists.
- Access token TTL: 14400 seconds = 4 hours (not 24 — the ADR's original guess was wrong).
- Refresh-token rotation: NONE. Refresh response carries only `access_token`/`expires_in`/`scope`/`token_type`/`user_id`. SessionManager keeps the existing refresh token in state; no cookie rewrite needed on refresh.
- Dev redirect URI gotcha: Tidal's portal saves `127.0.0.1` URIs immediately but rejects `localhost` URIs (the portal's "no localhost" production rule applies regardless of app mode).

#### Why not `oidcc`?

[`oidcc`](https://oidcc.hexdocs.pm/readme.html) is an OpenID Connect library that bundles PKCE alongside provider discovery (`.well-known/openid-configuration`), ID-token JWT/JWK validation, userinfo, and nonce handling. Tidal is plain OAuth 2.1 + PKCE — no ID token, no discovery endpoint, no `openid` scope. Adopting `oidcc` would mean dragging in OIDC abstractions and discovery configuration for an OAuth-only provider, in exchange for skipping ~5 LOC of `:crypto`. Not worth it. If we add a second OAuth-PKCE provider later and the crypto duplicates, extract a `Setlistify.Auth.PKCE` helper at that point.

### Rate Limit Strategy (concurrency cap in v1 + telemetry)

Per §3 above, v1 adds a small Tidal-scoped concurrency cap. Sketch:

```elixir
defmodule Setlistify.Tidal.RequestThrottle do
  # Small semaphore: caps in-flight Tidal HTTP requests at @max_concurrent.
  # Calls above the cap block until a slot frees up. Scoped to the Tidal
  # subtree only — Spotify and Apple Music are not throttled here.
  use GenServer
  @max_concurrent 4

  def with_slot(fun), do: GenServer.call(__MODULE__, {:acquire, fun}, :infinity)
  # ... acquire/release + queue impl
end
```

Every `Tidal.API.ExternalClient` HTTP-issuing function wraps its Req call in `RequestThrottle.with_slot/1`. Calls above the cap queue — they never even hit Tidal's `/authorize` or `/v2/...` endpoints until a slot is free, so no wasted 429 traffic.

429s that DO occur (despite the cap, e.g. transient bursts or multi-user contention) return `{:error, {:rate_limited, retry_after}}` — a 2-tuple that fits the existing `MusicService.API` callback's `{:error, atom() | {atom(), term()}}` shape. The callback union widens; Spotify and Apple Music keep emitting their existing bare `{:error, atom()}` shapes (no behavioral change), and the LiveView pattern-matches the inner tuple to render retry hints if desired.

Telemetry records:

- `http.status_code` (semconv) on every HTTP span
- on 429, a `http.rate_limited` span event carrying `http.response.header.retry_after`
- a metric for throttle queue wait time, so we can see whether the cap value of 4 is squeezing too tight

Provider identity is `peer.service` (set by `MusicService.API.impl/1`) — **never** a `tidal.*` attribute namespace. A 429-count telemetry metric is labeled by `music.service`.

Phase 2 reviews real traffic (filtered on `peer.service = "tidal"`) and answers: (a) is the simple cap sufficient, or do we need per-user pacing? (b) is `@max_concurrent = 4` correct?

### JSON:API Request/Response Shape

Tidal v2 speaks JSON:API:

- Requests set `content-type` and `accept` to `application/vnd.api+json`.
- Search: `GET /v2/searchResults/{url-encoded-query}?countryCode=US&include=tracks,tracks.artists` — the query is a path segment, and related artists arrive in the top-level `included` array, resolved by `relationships` references rather than nesting. (Spike note: `included` is FLAT across all search-result tracks' relationships — must always resolve by `{type, id}` lookup, never by index.)
- Playlist creation: `POST /v2/playlists` with a JSON:API `data` body and an `Idempotency-Key` header. Body sets `"accessType": "UNLISTED"` (see §4). Returns **201 Created** with a UUIDv4 `id`. Spike-verified accepted values: `PUBLIC`, `UNLISTED`. `PRIVATE` is rejected with `INVALID_REQUEST_BODY`.
- Add tracks: `POST /v2/playlists/{id}/relationships/items` in 20-track chunks; **`meta.positionBefore` is OMITTED** (spike-verified: it's a no-op for the add-new-items case — natural append-to-end is the actual behavior and is what we want).

The artist-match + cover-fallback policy is re-derived **verbatim** from the Spotify/Apple Music implementations inside `Tidal.API.ExternalClient.search_for_track/4` — this duplication is the deliberate third data point for #130.

#### JSON:API tooling

We do not adopt a JSON:API client library. The Elixir `jsonapi` hex package is a Phoenix-side *serializer* (for emitting responses), not a client. Req's existing `decode_body` step already handles the `application/vnd.api+json` content type as JSON via the `*+json` match, so the response body arrives as a parsed map without configuration. The only JSON:API mechanics we touch are setting the `content-type` / `accept` headers in `client/1` and walking the `included` array to resolve `relationships` references. The latter is encapsulated in a small private helper:

```elixir
# Resolves a {type, id} relationships reference against the top-level included list.
defp extract_included(%{"included" => included}, type, id) when is_list(included) do
  Enum.find(included, fn entry -> entry["type"] == type && entry["id"] == id end)
end
defp extract_included(_body, _type, _id), do: nil
```

Edge cases to handle at the call site: responses with no `relationships` at all (no `included` key in the body), tracks whose artist references resolve to nothing in `included` (treat as unknown artist; falls into the existing cover-fallback path), and the `data` array being empty (no search hits — return `nil`).

Code-generation from an OpenAPI/JSON:API schema is net-negative for ~5 endpoints — the wrappers would be larger than the call sites.

### Session-Building Pattern (Spotify-shaped flow, JWT-derived inputs)

Two existing patterns:

- **Spotify** has a *private* `build_user_session_from_tokens/1` that `exchange_code/2` and `refresh_to_user_session/1` both call internally. It chases `/me` to get user_id + username, then builds the struct. There is no public constructor — callers always get a fresh session from a tokens response.
- **Apple Music** has a *public* `build_user_session/3` because its inputs (user_token, storefront, generated UUID) come from the browser hook, not from an API response. Both first-auth and the cookie-only restoration path call it.

**Tidal: Spotify-shaped flow, JWT-derived inputs (no `/me` chase).** A private `build_user_session_from_tokens/1` is called by both `exchange_code/3` and `refresh_to_user_session/1`. It does NOT call `/v2/users/me`. Instead it decodes the access-token JWT and pulls `user_id` from the `uid` claim and `country_code` from the `cc` claim. No `:username` field exists (see §1).

```elixir
# Sketch — actual implementation lives in Setlistify.Tidal.API.ExternalClient.
# DELIBERATE NON-STANDARD: we treat Tidal's JWT internals as a stable interface.
# OAuth spec says treat access tokens as opaque. If Tidal ever rotates these
# claim names or moves to opaque tokens, switch to GET /v2/users/me — its
# response shape is documented in ADR-004 §1 and the issue #137 findings.
# Map.fetch! intentionally so a missing claim blows up sign-in instead of
# silently corrupting the session.
defp build_user_session_from_tokens(%{"access_token" => at, "refresh_token" => rt, "expires_in" => ttl}) do
  claims = decode_jwt_payload!(at)
  %Tidal.UserSession{
    access_token: at,
    refresh_token: rt,
    expires_at: DateTime.add(DateTime.utc_now(), ttl, :second),
    user_id: Map.fetch!(claims, "uid") |> to_string(),
    country_code: Map.fetch!(claims, "cc")
  }
end
```

Session restoration goes through the refresh path (Tidal access tokens are short-lived at 4 h, so we always need a fresh access token after process restart). No public `build_user_session/N` constructor is needed.

**Refresh subtlety** (verified in spike): Tidal does NOT rotate refresh tokens. The refresh response carries only `access_token`/`expires_in`/`scope`/`token_type`/`user_id` — no new `refresh_token`. `SessionManager.handle_info(:refresh_token, ...)` therefore preserves the existing refresh_token field on the struct rather than reading it from the response. The encrypted cookie does NOT need a rewrite on every refresh — only on first sign-in and sign-out.

### Idempotency keys — open implementation question

Tidal's `POST /v2/playlists` accepts an `Idempotency-Key` header. Two consideration points to resolve at implementation time:

- **Value strategy.** A random UUID per call is useless for retries (each retry generates a different key). A hash of `(user_id, name, normalized_description, setlist_id?)` survives retries within a setlist session but would collide across two distinct same-named playlists — usually fine for our flow, since duplicate-named playlists for the same setlist are the bug case we *want* idempotency to prevent.
- **Whether `add_tracks_to_playlist/3` carries one too.** Add-tracks is naturally near-idempotent for our use (duplicate adds just add the track twice), but with 20-track chunking + 429 retries, chunk-level idempotency keys would prevent double-adds when the server processed the request but the response was lost. Implementation should make the call.

These are flagged here so they get addressed when issue #140 is picked up. The ADR does not pre-commit to a specific scheme.

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
    session_manager.ex                  # new — OAuth+refresh variant (preserves refresh_token across refreshes; no rotation)
    session_supervisor.ex               # new — thin DynamicSupervisor wrapper
    request_throttle.ex                 # new — Tidal-scoped concurrency cap (§3, max_concurrent=4)
    api.ex                              # new — @behaviour MusicService.API + exchange_code/3, refresh_*
    api/
      external_client.ex                # new — HTTP impl + policy re-derivation; JWT-derived session; throttle-wrapped HTTP calls
  music_service/
    api.ex                              # extend — Tidal dispatch (NO get_embed clause; Tidal links out)
  user_session_manager.ex               # extend — Tidal clauses
  application.ex                        # extend — :tidal_track_cache + Tidal.RequestThrottle child

lib/setlistify_web/
  plugs/
    restore_tidal_token.ex              # new — network-call variant (short-lived tokens)
  controllers/
    oauth_callback_controller.ex        # extend — Tidal sign_in/new/sign_out (PKCE; redirect_uri uses 127.0.0.1 in dev)
    user_auth.ex                        # extend — preserve :country_code (refresh_token preservation already in place)
  auth/
    live_hooks.ex                       # extend — "tidal" to_provider_key clause
  router.ex                             # extend — RestoreTidalToken in :browser pipeline
  live/
    setlists/show_live.ex               # extend — provider/1 clause, sign-in option
    playlists/show_live.ex              # extend — "tidal" handle_params clause (link-out, mirrors Apple Music — NOT embed)
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

**New helpers that don't exist yet** (will be written as part of Phase 1):

- **`decode_jwt_payload!/1`** — small private helper in `Tidal.API.ExternalClient` to base64url-decode the access-token JWT's payload segment and `Jason.decode!` it. No signature verification (we're not validating someone else's tokens — these came from Tidal in response to our own request). Used by `build_user_session_from_tokens/1` to pull `uid` and `cc` claims. ~5 LOC.
- **`Setlistify.Tidal.RequestThrottle`** — the concurrency-cap GenServer described in §3 / "Rate Limit Strategy". One new module + tests.

## Implementation Plan

The work is tracked as a GitHub project. Issue numbers below are the filed GitHub issues (Tidal Integration project).

### Phase 0 — Auth Spike (COMPLETE — see issue #137)

Validated all 10 checklist items in issue #137. Key findings, summarized:

| # | Question | Answer |
|---|---|---|
| 1 | Client ID/Secret format | ~16-char ID, opaque secret |
| 2 | Token endpoint host | **`https://auth.tidal.com/v1/oauth2/token`** |
| 3 | `/me` `country` format | alpha-2 uppercase (`"US"`); access-token JWT carries it in `cc` claim — we skip `/me` |
| 4 | Search JSON:API shape | `data.relationships.tracks.data` (ordered refs) + flat `included`; resolve by `{type, id}` |
| 5 | `accessType` values | `PUBLIC`, `UNLISTED` accepted; `PRIVATE` rejected. Default: `UNLISTED` (§4) |
| 6 | `meta.positionBefore` required? | **No, and it's a no-op for new appends** — omit it |
| 7 | Refresh-token rotation? | **No** — refresh response has no `refresh_token` field |
| 8 | Real rate limits | ~8-request burst, then ~2-3/sec sustained, `Retry-After: 4` flat — drives §3's concurrency cap |
| 9 | Embed renders unauth? | Tracks yes (200, real player); PUBLIC playlists yes; **UNLISTED playlists: NO** (200 but error-dialog body) → drives §4's link-out |
| 10 | ISRCs in setlist.fm? | **No** — `name`-only song objects; ISRC fast-path deferred indefinitely (§3a) |

Additional incidental findings:

- Dev redirect URI must be `127.0.0.1`, not `localhost` (portal rejects localhost regardless of app mode)
- Access tokens are 4-hour TTL (not 24 as ADR originally guessed); they are ES256-signed JWTs carrying `uid` + `cc` claims
- `UNLISTED` is owner-only access (link works for owner, 404 for anyone else) — not "link-shareable" in the YouTube sense

**Gate**: passed. Phase 1 unblocked.

### Phase 1 — Implementation (7 issues)

Each PR is independently mergeable. Issues numbered in dependency order. **Updates from Phase 0 spike findings are marked `(Phase 0 update)`.**

1. **#138 — chore: add Tidal env vars + `TokenSalts.tidal_refresh_token`**
   - `TIDAL_CLIENT_ID`, `TIDAL_CLIENT_SECRET` in `.env.example` + `config/runtime.exs`
   - `Setlistify.Auth.TokenSalts.tidal_refresh_token/0` returns `"tidal refresh token"`
   - *(Phase 0 update)* Document `127.0.0.1` (not `localhost`) for the dev `TIDAL_REDIRECT_URI` if we read one from env; the dev portal will not save `localhost` URIs

2. **#139 — feat: implement `Tidal.UserSession`, `SessionManager`, `SessionSupervisor`**
   - *(Phase 0 update)* `@enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :country_code]` — **no `:username`** (Tidal's `/me` username is just the email, and we don't display it; mirrors Apple Music's no-username pattern)
   - `SessionManager` mirrors `Spotify.SessionManager` (OAuth + refresh timer); Registry key `{:tidal, user_id}`; PubSub `{:token_refreshed, session}` on `"user:#{user_id}"`
   - *(Phase 0 update)* **Refresh timer schedules for ~3.5 h, NOT ~23 h** — access tokens are 4-hour TTL (`expires_in: 14400`), confirmed by spike
   - *(Phase 0 update)* `handle_info(:refresh_token, state)` preserves the existing `refresh_token` field on the struct rather than reading a (non-existent) new one from the refresh response — **Tidal does not rotate refresh tokens**. Verified in spike.
   - `SessionSupervisor` thin wrapper around `Setlistify.UserSessionSupervisor`
   - Unit tests parallel to existing Spotify session tests

3. **#140 — feat: implement `Tidal.API` + `Tidal.API.ExternalClient` (+ `RequestThrottle`)**
   - `Tidal.API`: `@behaviour Setlistify.MusicService.API`; declares `exchange_code/3` (PKCE verifier), `refresh_token/1`, `refresh_to_user_session/1`; **no `get_embed/1`** *(Phase 0 update — playlists link out, not embed; see §4)*; `search_for_track/4` wraps `Cachex.fetch(:tidal_track_cache, ...)` with OTel context propagation
   - `Tidal.API.ExternalClient` full HTTP impl:
     - JSON:API client (`application/vnd.api+json` content-type/accept; Req's `decode_body` step handles it automatically)
     - `with_token_refresh/3` for 401 → refresh → retry once
     - Path-segment search with `countryCode` and JSON:API `included` artist resolution via the `extract_included/3` helper
     - Re-derived artist-match + cover-fallback policy (the #130 evidence)
     - `create_playlist/3` with `Idempotency-Key`, default `accessType: "UNLISTED"` *(Phase 0 update — see §4)*
     - `add_tracks_to_playlist/3` in 20-track chunks, **no `meta.positionBefore`** *(Phase 0 update — it's a no-op for new appends; natural append-to-end is the actual behavior and what we want)*
     - *(Phase 0 update)* `exchange_code/3` and `refresh_to_user_session/1` build the `UserSession` from JWT claims (`uid`, `cc`) via `decode_jwt_payload!/1` + `Map.fetch!/2` — **no `/v2/users/me` call**. See §1 for risk mitigations.
     - 429 surfaced as `{:error, {:rate_limited, retry_after}}` with semconv `http.status_code` + `http.rate_limited` span event — **no `tidal.*` attributes**
   - *(Phase 0 update)* **`Tidal.RequestThrottle`** new module: small concurrency-cap semaphore (`@max_concurrent 4`, supervised under the Tidal subtree); every `ExternalClient` HTTP-issuing function wraps its Req call in `RequestThrottle.with_slot/1`. Calls above the cap queue rather than fire-and-429. Spotify and Apple Music are NOT throttled here — this is fully encapsulated inside the Tidal module. Emits a queue-wait-time metric so we can tune `@max_concurrent` later if needed.
   - Unit tests via `Req.Test` plug intercept

4. **#141 — chore: register Tidal Cachex cache + Hammox mock**
   - `:tidal_track_cache` Cachex child in `Setlistify.Application`
   - `Setlistify.Tidal.RequestThrottle` child also added to `Setlistify.Application` *(Phase 0 update)*
   - `Hammox.defmock(Setlistify.Tidal.API.MockClient, for: Setlistify.Tidal.API)` and `Application.put_env(:setlistify, :tidal_api_client, ...)` in `test/test_helper.exs`

5. **#142 — feat: Tidal OAuth+PKCE callback + sign-in handlers**
   - `OAuthCallbackController.sign_in/2` Tidal clause: generate state + verifier + challenge; put both in session; redirect to `https://login.tidal.com/authorize?...` with `code_challenge`, `code_challenge_method=S256`, `scope=user.read playlists.write` *(Phase 0 update — scopes confirmed)*, `state`
   - `new/2` Tidal clause: validate state, read + delete `:pkce_code_verifier`, `exchange_code/3` *(Phase 0 update — POSTs to `https://auth.tidal.com/v1/oauth2/token`, the confirmed token host)*, encrypt refresh token with `tidal_refresh_token` salt, start session, `put_session(:auth_provider, "tidal")`, `put_session(:refresh_token, encrypted)` (shared key with Spotify; salt disambiguates per §5), `put_session(:country_code, code)` (unprefixed, matches Apple Music's `:storefront`), `put_session(:user_id, ...)`, `UserAuth.auth_user/2`
   - `sign_out/2` Tidal case clause
   - `UserAuth.auth_user/2` extended to preserve `:country_code` across `renew_session/1` (`:refresh_token` is already preserved by the existing block)
   - Controller tests: state mismatch, missing verifier, success, exchange failure

6. **#143 — feat: `RestoreTidalToken` plug + router wiring**
   - Mirrors `RestoreSpotifyToken`, guarded by `auth_provider == "tidal"`; decrypts refresh token; if no live session process, calls `refresh_to_user_session/1` then `start_user_token/2`; clears session + flashes on failure
   - *(Phase 0 update)* `refresh_to_user_session/1` derives `user_id` + `country_code` from the new access-token JWT (not `/me`), and preserves the existing refresh token in the resulting struct (no rotation per spike)
   - Added to `:browser` pipeline after the Apple Music plug
   - Plug tests parallel to `restore_spotify_token_test.exs`

7. **#144 — feat: dispatch + UI wiring for Tidal**
   - `MusicService.API`: alias Tidal; extend `@type user_session` union; `impl/1` clause for `%Tidal.UserSession{}` setting `peer.service: "tidal"`; **NO `get_embed("tidal", url)` clause** *(Phase 0 update — Tidal links out, see §4)*
   - `UserSessionManager`: extend `@type` unions; `impl/1` clauses for `%Tidal.UserSession{}` and `{:tidal, _}`
   - `LiveHooks.to_provider_key("tidal", user_id)` clause
   - `Setlists.ShowLive.provider/1` clause
   - *(Phase 0 update)* `Playlists.ShowLive.handle_params/3` `"tidal"` clause: **link out** to `https://tidal.com/playlist/{id}` (mirrors the Apple Music link-out clause). NOT the Spotify embed clause.
   - `Layouts` user-display helpers (no username displayed for Tidal — mirrors Apple Music); Tidal header sign-in button; Tidal added to the unauthenticated sign-in options on `Setlists.ShowLive`

### Phase 2 — Wrap-Up (3 issues)

1. **#145 — chore: evaluate #130 policy lift with three providers**
   - Side-by-side diff of `artist_match?/2` / `normalize_artist/1` / cover-fallback / policy-boundary telemetry across all three providers
   - Identify provider-specific leakage (e.g., Tidal's JSON:API `included` walking)
   - Comment outcome on #130 (full / partial / no lift); file a follow-up issue or close with rationale

2. **#146 — chore: review Tidal rate-limit telemetry, decide on per-user limiter and throttle tuning**
   - *(Phase 0 update)* Scope expanded: with `Tidal.RequestThrottle` now landing in Phase 1, the Phase 2 review answers TWO questions:
     - (a) Is the simple concurrency cap sufficient, or do we need per-user pacing (multi-user contention can still 429 the app even with the cap)?
     - (b) Is `@max_concurrent = 4` correct? Spike baseline: 8-request burst capacity, 2-3 sustained req/sec, `Retry-After: 4` flat. Real traffic may diverge.
   - After ~2 weeks of real traffic, query Grafana (filtered on `peer.service = "tidal"`): 429 incidence, `http.response.header.retry_after` distribution from `http.rate_limited` events, playlist-creation duration p50/p95, `RequestThrottle` queue-wait-time metric
   - Decide: ship as-is / tune `@max_concurrent` / add per-user `Tidal.RateLimiter` / add UI progress hints; file follow-up if needed

3. **#147 — docs: update `adding-a-music-provider.md` with Tidal lessons**
   - PKCE callout (generate verifier + challenge in `sign_in/2`, store in session next to `:oauth_state`, replay in token exchange)
   - Rate-limiting callout: surface 429 as `{:error, {:rate_limited, retry_after}}`; record via semconv `http.status_code` + `http.rate_limited` span event — never a `<provider>.*` namespace. Also: the `RequestThrottle` pattern for providers with low documented limits.
   - Region-scoping callout (Apple Music `storefront`, Tidal `country_code`) as a per-user session field
   - JSON:API note if Tidal's response shape needed nontrivial parsing
   - *(Phase 0 update)* Dev redirect URI gotcha: some providers reject `localhost`; use `127.0.0.1` and document the discrepancy
   - *(Phase 0 update)* JWT-derivation as an alternative to `/me` when the provider issues JWTs and the claims are stable enough (with the risk callout)
   - Confirm the existing checklist still accurate

(The previously-conditional ISRC fast-path issue is dropped — Phase 0 confirmed setlist.fm doesn't carry ISRCs, so the optimization is not viable. See §3a.)

## Consequences

### Positive

- ✅ Tidal users get full feature parity with Spotify and Apple Music
- ✅ Reuses the ADR-003 dispatch architecture wholesale — no web-layer changes beyond provider clauses
- ✅ PKCE is a small, contained change with no new process or table — it reuses the `:oauth_state` cookie pattern
- ✅ Provides the third data point needed to settle the #130 abstraction question with evidence rather than speculation
- ✅ OTel stays provider-agnostic — Grafana queries filter by `peer.service`, not by attribute namespace

### Negative

- ❌ Tidal's measured rate limit (~8-request burst, ~2-3 sustained req/sec) requires a Tidal-scoped concurrency cap; the cap value of 4 is an educated guess from spike data, may need tuning in Phase 2
- ❌ The artist-match/cover-fallback policy is duplicated a third time before any lift (deliberate, but it is debt until #130 resolves)
- ❌ Concurrent multi-tab sign-in can overwrite the cookie-stored PKCE verifier (edge case, already accepted for `:oauth_state`)
- ❌ Deliberate non-standard reliance on Tidal's access-token JWT claims (`uid`, `cc`) — OAuth spec says treat tokens as opaque. Mitigations are in place (loud failure on missing claims, documented fallback recipe), but this is a real coupling to Tidal's JWT format
- ❌ Tidal playlists from Setlistify are not embeddable in-page (UNLISTED default + Tidal's embed player rejects UNLISTED); `/playlists` page links out instead, a minor UX regression vs. the Spotify embed

### Neutral

- Tidal access tokens are short-lived (4 h), so `RestoreTidalToken` makes a network call on restoration — unlike Apple Music's pure-cookie restoration, like Spotify's refresh path
- Tidal IDs fit the existing provider-opaque `:track_id` convention with no type changes
- Tidal's "UNLISTED" means owner-only access (link works for owner, 404 for anyone else) — semantically closer to "PRIVATE" in other vocabularies. Fine for Setlistify since sharing playlists with others is out of scope.

## Implementation Status

### Completed

- **Phase 0: Tidal auth spike (issue #137, 2026-06-08)** — all 10 checklist items answered with real API calls. Findings incorporated into this ADR and into the Phase 1/2 issue descriptions. Spike code (throwaway) deleted.

### Remaining Work

- Phase 1: Implementation (#138 – #144, 7 issues)
- Phase 2: Wrap-up (#145 – #147, 3 issues)

## Success Metrics

- Tidal sign-in → view setlist → create playlist → playlist appears in the Tidal app → embed renders on `/playlists`, end-to-end
- A 20+ song setlist exercises real rate-limit behavior (feeds the Phase 2 telemetry review)
- `mix test` passes with full coverage across all three providers
- `grep -rn "Spotify.API" lib/setlistify_web/live/` still returns 0 results (provider-agnosticism preserved)
- All three providers' `search_for_track` callbacks share identical `@callback` signatures (Dialyzer-enforced)
- 429 events are filterable in Grafana by `peer.service = "tidal"` with no `tidal.*` attribute namespace

## References

- [TIDAL API SDK Quick Start](https://developer.tidal.com/documentation/api-sdk/api-sdk-quick-start) — start here in the Phase 0 spike
- [TIDAL Authorization Docs](https://developer.tidal.com/documentation/api-sdk/api-sdk-authorization) — PKCE-for-all-clients statement, refresh-token example response
- [TIDAL API Reference](https://tidal-music.github.io/tidal-api-reference/)
- [TIDAL Developer Portal](https://developer.tidal.com/)
- [tidal-music discussion #135 — Retry-After on 429](https://github.com/orgs/tidal-music/discussions/135) — only official statement on rate-limit behavior
- [OAuth 2.1 / PKCE (RFC 7636)](https://datatracker.ietf.org/doc/html/rfc7636)
- [JSON:API Specification](https://jsonapi.org/)
- [ADR-001: Token Session Management](001-token-session-management.md)
- [ADR-003: Apple Music Integration](003-apple-music-integration.md)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- `docs/adding-a-music-provider.md`
