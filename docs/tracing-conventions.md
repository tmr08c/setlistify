# OpenTelemetry Tracing Conventions

## Span Naming Convention

All spans use the full module and function name for easy correlation between traces and code:

```
Module.Name.function_name
```

This makes it trivial to find the exact function when looking at traces, as the span name directly maps to the code location.

## Examples

### Spotify Integration
- `Setlistify.Spotify.API.search_for_track` - API layer track search
- `Setlistify.Spotify.API.create_playlist` - API layer playlist creation
- `Setlistify.Spotify.API.ExternalClient.search_for_track` - HTTP client implementation
- `Setlistify.Spotify.API.ExternalClient.refresh_token` - OAuth token refresh

### Web Layer
- `SetlistifyWeb.SearchLive.handle_params` - LiveView search handling
- `SetlistifyWeb.Setlists.ShowLive.enrich_setlist` - LiveView setlist enrichment
- `SetlistifyWeb.Telemetry.LiveViewTelemetry.on_mount` - LiveView mount operation

### Testing
- `Setlistify.Observability.test_trace` - Test trace creation
- `Setlistify.Observability.test_trace.nested` - Nested test operation

## Attribute Conventions

Standard attributes should follow OpenTelemetry semantic conventions where applicable:
- `service.name` - The service name (e.g., "spotify", "setlist_fm")
- `user.id` - The user identifier
- `enduser.id` - Same as user.id for end-user identification
- `http.status_code` - HTTP response status codes
- `http.url` - The full URL being requested

Service-specific attributes use the service name as prefix:
- `spotify.operation` - The Spotify operation type
- `spotify.playlist.id` - Spotify playlist identifier
- `spotify.tracks.count` - Number of tracks being added

## Context Propagation

For operations that cross process boundaries (e.g., Cachex), explicit context propagation is required:

```elixir
parent_ctx = OpenTelemetry.Ctx.get_current()
parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

Cachex.fetch(cache, key, fn ->
  OpenTelemetry.Ctx.attach(parent_ctx)
  OpenTelemetry.Tracer.set_current_span(parent_span)
  # Perform operation
end)
```