defmodule Setlistify.Cache do
  @moduledoc """
  Wrapper around Cachex for application caching.

  All caching in the application should go through this module rather than
  calling Cachex directly. This keeps the Cachex dependency contained to one
  place — if we swap the underlying library, only this module needs to change,
  and callers stay the same.

  In addition to delegating to Cachex, this module:

    * Propagates OpenTelemetry context into Cachex's worker process, so traces
      aren't broken across the process boundary
    * Sets a `cache.hit` span attribute on the current span, enabling cache hit
      rate tracking in traces
  """

  require OpenTelemetry.Tracer

  @doc """
  Fetches a value from `cache` by `key`, calling `fetch_fn` on a miss.

  The return value of `fetch_fn` determines caching behaviour. We mirror
  Cachex's semantics and intend to maintain this contract even if the
  underlying library changes:

    * Plain value (e.g. `%{track_id: id}` or `nil`) — committed to cache
      and returned.
    * `{:commit, value}` — `value` committed to cache and returned.
    * `{:ignore, value}` — `value` returned without caching.
    * `{:error, reason}` — treated as a failed fetch; not cached, and
      `{:error, reason}` is returned to the caller.

  `{:ignore, value}` and `{:error, reason}` are equivalent when `value` is
  an error tuple — both skip caching and return `{:error, reason}`. Prefer
  `{:ignore, {:error, reason}}` to make the intent explicit.

  ## OpenTelemetry

  Sets `cache.hit` on the current span:

    * `true` — value was served from cache
    * `false` — callback was invoked (miss, ignored, or error)

  ## Examples

      iex> {:ok, _} = Cachex.start_link(name: :cachex_doctest_fetch)
      iex> Setlistify.Cache.fetch(:cachex_doctest_fetch, "hit", fn _ -> %{track_id: "abc"} end)
      %{track_id: "abc"}
      iex> Cachex.exists?(:cachex_doctest_fetch, "hit")
      {:ok, true}
      iex> Setlistify.Cache.fetch(:cachex_doctest_fetch, "miss", fn _ -> {:ignore, {:error, :transient}} end)
      {:error, :transient}
      iex> Cachex.exists?(:cachex_doctest_fetch, "miss")
      {:ok, false}

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

      {:ignore, result} ->
        OpenTelemetry.Tracer.set_attribute("cache.hit", false)
        result

      {:error, _} = error ->
        OpenTelemetry.Tracer.set_attribute("cache.hit", false)
        error
    end
  end
end
