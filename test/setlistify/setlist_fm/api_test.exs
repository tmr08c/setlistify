defmodule Setlistify.SetlistFm.APITest do
  use Setlistify.DataCase, async: false

  import Hammox

  alias Setlistify.SetlistFm.API
  alias Setlistify.SetlistFm.API.MockClient

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(fn ->
      Cachex.clear!(:setlist_fm_search_cache)
      Cachex.clear!(:setlist_fm_setlist_cache)
    end)
  end

  describe "search/2 caching" do
    test "caches successful results — impl called only once for the same query" do
      expect(MockClient, :search, 1, fn _query, _page ->
        {:ok, %{setlists: [], pagination: %{page: 1, total: 0, items_per_page: 20}}}
      end)

      assert {:ok, _} = API.search("artist")
      assert {:ok, _} = API.search("artist")
    end

    test "caches :not_found — impl called only once for the same query" do
      expect(MockClient, :search, 1, fn _query, _page ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = API.search("unknown artist")
      assert {:error, :not_found} = API.search("unknown artist")
    end

    test "does not cache transient errors — impl called again on retry" do
      expect(MockClient, :search, 1, fn _query, _page ->
        {:error, {:api_error, 500}}
      end)

      assert {:error, {:api_error, 500}} = API.search("artist")

      expect(MockClient, :search, 1, fn _query, _page ->
        {:ok, %{setlists: [], pagination: %{page: 1, total: 0, items_per_page: 20}}}
      end)

      assert {:ok, _} = API.search("artist")
    end
  end

  describe "get_setlist/1 caching" do
    test "caches successful results — impl called only once for the same id" do
      setlist = %{
        artist: "The Beatles",
        venue: %{name: "Venue", location: %{city: "NYC", state: nil, country: "US"}},
        date: ~D[2024-01-01],
        sets: []
      }

      expect(MockClient, :get_setlist, 1, fn _id ->
        {:ok, setlist}
      end)

      assert {:ok, ^setlist} = API.get_setlist("setlist-id")
      assert {:ok, ^setlist} = API.get_setlist("setlist-id")
    end

    test "does not cache errors — impl called again on retry" do
      expect(MockClient, :get_setlist, 1, fn _id ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = API.get_setlist("bad-id")

      setlist = %{
        artist: "The Beatles",
        venue: %{name: "Venue", location: %{city: "NYC", state: nil, country: "US"}},
        date: ~D[2024-01-01],
        sets: []
      }

      expect(MockClient, :get_setlist, 1, fn _id ->
        {:ok, setlist}
      end)

      assert {:ok, ^setlist} = API.get_setlist("bad-id")
    end
  end
end
