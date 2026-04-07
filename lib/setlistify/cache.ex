defmodule Setlistify.Cache do
  @moduledoc """
  Wrapper around Cachex for application caching.

  All caching in the application should go through this module rather than
  calling Cachex directly. This keeps the Cachex dependency contained to one
  place — if we swap the underlying library, only this module needs to change,
  and callers stay the same.

  In addition to delegating to Cachex, this module:
  - Propagates OpenTelemetry context into Cachex's worker process, so traces
    aren't broken across the process boundary
  - Sets a `cache.hit` span attribute on the current span, enabling cache hit
    rate tracking in traces
  """

  require OpenTelemetry.Tracer

  @doc """
  Fetches a value from the cache, calling `fetch_fn` on a miss.

  The callback receives the key and its return value determines caching behaviour.
  We mirror Cachex's semantics and intend to maintain this contract even if the
  underlying library changes:

  - Returning a plain value (e.g. `%{track_id: id}` or `nil`) commits it to
    cache and returns it.
  - Returning `{:commit, value}` explicitly commits `value` to cache and returns
    it. Useful when the callback needs to signal intent clearly.
  - Returning `{:ignore, value}` returns `value` without storing it in cache.
    Use this for transient errors or other results that should not be cached.
  - Returning `{:error, reason}` is treated by Cachex as a failed fetch — the
    value is not cached and `{:error, reason}` is returned to the caller.

  Sets `cache.hit` on the current OpenTelemetry span:
  - `true` when the value was already in cache
  - `false` when the callback was invoked (miss, error, or ignored result)
  """
  def fetch(cache, key, fetch_fn) do
    parent_ctx = OpenTelemetry.Ctx.get_current()
    parent_span = OpenTelemetry.Tracer.current_span_ctx(parent_ctx)

    cache
    |> Cachex.fetch(key, fn key ->
      OpenTelemetry.Ctx.attach(parent_ctx)
      OpenTelemetry.Tracer.set_current_span(parent_span)
      fetch_fn.(key)
    end)
    |> case do
      {:ok, result} ->
        OpenTelemetry.Tracer.set_attribute("cache.hit", true)
        result

      {:commit, result} ->
        OpenTelemetry.Tracer.set_attribute("cache.hit", false)
        result

      {:error, _} = error ->
        OpenTelemetry.Tracer.set_attribute("cache.hit", false)
        error
    end
  end
end
