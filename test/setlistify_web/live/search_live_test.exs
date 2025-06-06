defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.SetlistFm

  # Cache fetching happens in another process, managed by Cachex. The process we
  # start in our application tree is a supervisor, so explictly `allow`ing with
  # that PID does not work. This will enable "global" mode which means  any
  # process will respect our `expect` at the cost of not being able to run with
  # `async: true`
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(fn ->
      Cachex.clear!(:setlist_fm_search_cache)
    end)
  end

  test "redirects to home when no search params provided", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists")
  end

  test "searching for setlists", %{conn: conn} do
    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :search, 1, fn "beatles", 1 ->
      {:ok,
       %{
         setlists: [
           %{
             artist: "The Beatles",
             venue: %{
               name: "Compaq Center",
               location: %{city: "Houston", state: "TX", country: "United States"}
             },
             date: Date.new!(2023, 01, 01),
             id: setlist_id,
             song_count: 12
           }
         ],
         pagination: %{page: 1, total: 1, items_per_page: 20}
       }}
    end)

    {:ok, view, html} = live(conn, ~p"/setlists?query=beatles")

    # Check that search results are displayed
    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "Houston, TX, United States"
    assert html =~ "2023-01-01"

    view |> element(tid("setlist-#{setlist_id}")) |> render_click()
    assert_redirected(view, ~p"/setlist/#{setlist_id}")
  end

  test "displays 'No results found' when search returns empty list", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "nonexistent", 1 ->
      {:error, :not_found}
    end)

    {:ok, _view, html} = live(conn, ~p"/setlists?query=nonexistent")

    assert html =~ "No results found"
  end

  test "search form is pre-filled with query parameter", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "some band", 1 ->
      {:error, :not_found}
    end)

    {:ok, _view, html} = live(conn, ~p"/setlists?query=some+band")

    # Check that the search input is pre-filled with the query
    assert html =~ ~s(value="some band")
  end

  test "displays song count in search results", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "test artist", 1 ->
      {:ok,
       %{
         setlists: [
           %{
             artist: "Test Artist",
             venue: %{
               name: "Test Venue 1",
               location: %{city: "Austin", state: "TX", country: "United States"}
             },
             date: Date.new!(2023, 01, 01),
             id: "test-id-1",
             song_count: 0
           },
           %{
             artist: "Test Artist",
             venue: %{
               name: "Test Venue 2",
               location: %{city: "Seattle", state: "WA", country: "United States"}
             },
             date: Date.new!(2023, 01, 02),
             id: "test-id-2",
             song_count: 15
           },
           %{
             artist: "Test Artist",
             venue: %{
               name: "Test Venue 3",
               location: %{city: "Nashville", state: "TN", country: "United States"}
             },
             date: Date.new!(2023, 01, 03),
             id: "test-id-3",
             song_count: 1
           }
         ],
         pagination: %{page: 1, total: 3, items_per_page: 20}
       }}
    end)

    {:ok, _view, html} = live(conn, ~p"/setlists?query=test+artist")

    # Check that song counts are displayed
    assert html =~ "0 songs"
    assert html =~ "15 songs"
    assert html =~ "1 song"
  end

  describe "URL validation and manipulation protection" do
    test "redirects to home when query parameter is empty string", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?query=")
    end

    test "redirects to home when query parameter is only whitespace", %{conn: conn} do
      # Test various whitespace scenarios
      # single space
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=%20")
      # multiple spaces
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=%20%20%20")
      # tab
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=%09")
      # newline
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=%0A")
      # mixed whitespace
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=%20%09%0A")
    end

    test "redirects to home when query parameter has wrong type", %{conn: conn} do
      # Test non-string query parameters
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query[]=array")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query[key]=value")
    end

    test "redirects to home when using wrong parameter names", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?search=beatles")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?q=beatles")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?term=beatles")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?artist=beatles")
    end

    test "redirects to home when query parameter is missing but other params exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?page=1")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/setlists?sort=date&order=desc")

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists?filter=recent")
    end

    test "handles malformed URL parameters gracefully", %{conn: conn} do
      # no value
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query")
      # no key
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?=beatles")
      # empty with ampersand
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/setlists?query=&")
    end

    test "properly handles URL-encoded queries with valid content", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "the beatles", 1 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "The Beatles",
               venue: %{
                 name: "Abbey Road Studios",
                 location: %{city: "London", state: nil, country: "UK"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id",
               song_count: 10
             }
           ],
           pagination: %{page: 1, total: 1, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=the%20beatles")
      assert html =~ "The Beatles"
    end

    test "handles special characters in query parameters", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "AC/DC", 1 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "AC/DC",
               venue: %{
                 name: "Rock Arena",
                 location: %{city: "Sydney", state: nil, country: "Australia"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id-acdc",
               song_count: 15
             }
           ],
           pagination: %{page: 1, total: 1, items_per_page: 20}
         }}
      end)

      # AC/DC URL encoded
      {:ok, _view, html} = live(conn, "/setlists?query=AC%2FDC")
      assert html =~ "AC/DC"
    end

    test "handles very long query strings appropriately", %{conn: conn} do
      long_query = String.duplicate("a", 1000)

      expect(SetlistFm.API.MockClient, :search, 1, fn ^long_query, 1 ->
        {:error, :not_found}
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=#{URI.encode(long_query)}")
      assert html =~ "No results found"
    end

    test "handles unicode characters in queries", %{conn: conn} do
      unicode_query = "Björk"

      expect(SetlistFm.API.MockClient, :search, 1, fn ^unicode_query, 1 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Björk",
               venue: %{
                 name: "Reykjavik Hall",
                 location: %{city: "Reykjavik", state: nil, country: "Iceland"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id-bjork",
               song_count: 12
             }
           ],
           pagination: %{page: 1, total: 1, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=#{URI.encode(unicode_query)}")
      assert html =~ "Björk"
    end

    test "trims whitespace from valid queries", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "radiohead", 1 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Radiohead",
               venue: %{
                 name: "Oxford Venue",
                 location: %{city: "Oxford", state: nil, country: "UK"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id-radiohead",
               song_count: 18
             }
           ],
           pagination: %{page: 1, total: 1, items_per_page: 20}
         }}
      end)

      # Test that leading/trailing spaces are trimmed but query still works
      {:ok, _view, html} = live(conn, "/setlists?query=%20%20radiohead%20%20")
      assert html =~ "Radiohead"
    end
  end

  describe "pagination with page parameter" do
    test "defaults to page 1 when page parameter is not provided", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "test band", 1 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Test Band",
               venue: %{
                 name: "Test Venue",
                 location: %{city: "Austin", state: "TX", country: "United States"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id",
               song_count: 10
             }
           ],
           pagination: %{page: 1, total: 50, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, ~p"/setlists?query=test+band")
      assert html =~ "Test Band"
    end

    test "uses correct page when page parameter is provided", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "test band", 3 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Test Band Page 3",
               venue: %{
                 name: "Page 3 Venue",
                 location: %{city: "Seattle", state: "WA", country: "United States"}
               },
               date: Date.new!(2023, 01, 03),
               id: "test-id-page3",
               song_count: 12
             }
           ],
           pagination: %{page: 3, total: 50, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, ~p"/setlists?query=test+band&page=3")
      assert html =~ "Test Band Page 3"
      assert html =~ "Page 3 Venue"
    end

    test "defaults to page 1 when page parameter is empty string", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=")
    end

    test "defaults to page 1 when page parameter has spaces", %{conn: conn} do
      # With cache clearing in setup, the first call will hit the API and subsequent
      # calls will hit the cache since they all use the same {query, page} key
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      # Test various space scenarios - all parse to page 1
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=%20%20%20")
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=%20")
      # tab
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=%09")
    end

    test "defaults to page 1 when page parameter is not a number", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      # Various non-numeric inputs - all parse to page 1
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=abc")
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=two")
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=2a")
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=a2")
    end

    test "defaults to page 1 when page parameter is zero", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=0")
    end

    test "defaults to page 1 when page parameter is negative", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      # Both negative values parse to page 1
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=-1")
      {:ok, _view, _html} = live(conn, ~p"/setlists?query=artist&page=-100")
    end

    test "handles very large page numbers", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 999_999 ->
        {:error, :not_found}
      end)

      {:ok, _view, html} = live(conn, ~p"/setlists?query=artist&page=999999")
      assert html =~ "No results found"
    end

    test "handles decimal page numbers by truncating to integer", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 2 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Artist",
               venue: %{
                 name: "Venue",
                 location: %{city: "City", state: "ST", country: "Country"}
               },
               date: Date.new!(2023, 01, 01),
               id: "id",
               song_count: 5
             }
           ],
           pagination: %{page: 2, total: 30, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, ~p"/setlists?query=artist&page=2.5")
      assert html =~ "Artist"
    end

    test "handles page parameter with special characters", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      # Special characters should default to page 1
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=@#$")
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=1%2B1")
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page=<script>")
    end

    test "handles page parameter as array or map", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 1 ->
        {:error, :not_found}
      end)

      # Arrays and maps should default to page 1
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page[]=1")
      {:ok, _view, _html} = live(conn, "/setlists?query=artist&page[key]=value")
    end

    test "handles multiple page parameters by using the last one", %{conn: conn} do
      # Phoenix uses the last parameter value when duplicates exist
      expect(SetlistFm.API.MockClient, :search, 1, fn "artist", 3 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Artist Page 3",
               venue: %{
                 name: "Venue",
                 location: %{city: "City", state: nil, country: "Country"}
               },
               date: Date.new!(2023, 01, 01),
               id: "id",
               song_count: 8
             }
           ],
           pagination: %{page: 3, total: 40, items_per_page: 20}
         }}
      end)

      # Phoenix uses the last parameter value when there are duplicates
      {:ok, _view, html} = live(conn, "/setlists?query=artist&page=2&page=3")
      assert html =~ "Artist Page 3"
    end

    test "preserves query parameter when navigating with page parameter", %{conn: conn} do
      unicode_query = "Sigur Rós"

      expect(SetlistFm.API.MockClient, :search, 1, fn ^unicode_query, 2 ->
        {:ok,
         %{
           setlists: [
             %{
               artist: "Sigur Rós",
               venue: %{
                 name: "Harpa",
                 location: %{city: "Reykjavik", state: nil, country: "Iceland"}
               },
               date: Date.new!(2023, 01, 01),
               id: "test-id",
               song_count: 15
             }
           ],
           pagination: %{page: 2, total: 40, items_per_page: 20}
         }}
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=#{URI.encode(unicode_query)}&page=2")
      assert html =~ "Sigur Rós"
      assert html =~ "Harpa"
    end
  end
end
