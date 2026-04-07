defmodule Setlistify.CacheTest do
  use Setlistify.DataCase, async: false

  require OpenTelemetry.Tracer
  require Record

  alias Setlistify.Cache

  Record.defrecord(
    :span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  setup do
    start_supervised!({Cachex, name: :cache_test})
    {:ok, cache: :cache_test}
  end

  describe "fetch/3 caching behavior" do
    test "stores successful result in cache on miss", %{cache: cache} do
      Cache.fetch(cache, "key", fn _ -> "value" end)
      assert {:ok, "value"} = Cachex.get(cache, "key")
    end

    test "returns result on cache miss", %{cache: cache} do
      assert "value" == Cache.fetch(cache, "key", fn _ -> "value" end)
    end

    test "returns cached result on cache hit", %{cache: cache} do
      Cachex.put(cache, "key", "cached_value")
      assert "cached_value" == Cache.fetch(cache, "key", fn _ -> "other_value" end)
    end

    test "calls fn only once for repeated fetches of the same key", %{cache: cache} do
      parent = self()

      Cache.fetch(cache, "key", fn _ ->
        send(parent, :fn_called)
        "value"
      end)

      Cache.fetch(cache, "key", fn _ ->
        send(parent, :fn_called)
        "value"
      end)

      assert_received :fn_called
      refute_received :fn_called
    end

    test "does not store error results in cache", %{cache: cache} do
      Cache.fetch(cache, "key", fn _ -> {:error, :some_error} end)
      assert {:ok, false} = Cachex.exists?(cache, "key")
    end

    test "returns full error tuple on error", %{cache: cache} do
      assert {:error, :some_error} = Cache.fetch(cache, "key", fn _ -> {:error, :some_error} end)
    end
  end

  describe "fetch/3 OpenTelemetry" do
    setup do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
      :ok
    end

    test "sets cache.hit=false on cache miss", %{cache: cache} do
      OpenTelemetry.Tracer.with_span "test" do
        Cache.fetch(cache, "key", fn _ -> "value" end)
      end

      assert_receive {:span, s}
      assert %{"cache.hit" => false} = span_attributes(s)
    end

    test "sets cache.hit=true on cache hit", %{cache: cache} do
      Cachex.put(cache, "key", "cached_value")

      OpenTelemetry.Tracer.with_span "test" do
        Cache.fetch(cache, "key", fn _ -> "other_value" end)
      end

      assert_receive {:span, s}
      assert %{"cache.hit" => true} = span_attributes(s)
    end

    test "sets cache.hit=false on error", %{cache: cache} do
      OpenTelemetry.Tracer.with_span "test" do
        Cache.fetch(cache, "key", fn _ -> {:error, :some_error} end)
      end

      assert_receive {:span, s}
      assert %{"cache.hit" => false} = span_attributes(s)
    end
  end

  defp span_attributes(span_record) do
    span_record |> span(:attributes) |> :otel_attributes.map()
  end
end
