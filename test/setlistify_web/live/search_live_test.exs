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

  test "redirects to home when no search params provided", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/setlists")
  end

  test "searching for setlists", %{conn: conn} do
    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :search, 1, fn "beatles" ->
      [
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
      ]
    end)

    {:ok, view, html} = live(conn, ~p"/setlists?query=beatles")

    # Test validation first
    assert view |> form("[name='search']", %{search: %{query: ""}}) |> render_submit() =~
             "can&#39;t be blank"

    # Check that search results are displayed
    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "Houston, TX, United States"
    assert html =~ "2023-01-01"

    view |> element(tid("setlist-#{setlist_id}")) |> render_click()
    assert_redirected(view, ~p"/setlist/#{setlist_id}")
  end

  test "displays 'No results found' when search returns empty list", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "nonexistent" ->
      []
    end)

    {:ok, _view, html} = live(conn, ~p"/setlists?query=nonexistent")

    assert html =~ "No results found"
  end

  test "search form is pre-filled with query parameter", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "some band" ->
      []
    end)

    {:ok, _view, html} = live(conn, ~p"/setlists?query=some+band")

    # Check that the search input is pre-filled with the query
    assert html =~ ~s(value="some band")
  end

  test "displays song count in search results", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "test artist" ->
      [
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
      ]
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
      expect(SetlistFm.API.MockClient, :search, 1, fn "the beatles" ->
        [
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
        ]
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=the%20beatles")
      assert html =~ "The Beatles"
    end

    test "handles special characters in query parameters", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "AC/DC" ->
        [
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
        ]
      end)

      # AC/DC URL encoded
      {:ok, _view, html} = live(conn, "/setlists?query=AC%2FDC")
      assert html =~ "AC/DC"
    end

    test "handles very long query strings appropriately", %{conn: conn} do
      long_query = String.duplicate("a", 1000)

      expect(SetlistFm.API.MockClient, :search, 1, fn ^long_query ->
        []
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=#{URI.encode(long_query)}")
      assert html =~ "No results found"
    end

    test "handles unicode characters in queries", %{conn: conn} do
      unicode_query = "Björk"

      expect(SetlistFm.API.MockClient, :search, 1, fn ^unicode_query ->
        [
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
        ]
      end)

      {:ok, _view, html} = live(conn, "/setlists?query=#{URI.encode(unicode_query)}")
      assert html =~ "Björk"
    end

    test "trims whitespace from valid queries", %{conn: conn} do
      expect(SetlistFm.API.MockClient, :search, 1, fn "radiohead" ->
        [
          %{
            artist: "Radiohead",
            venue: %{name: "Oxford Venue", location: %{city: "Oxford", state: nil, country: "UK"}},
            date: Date.new!(2023, 01, 01),
            id: "test-id-radiohead",
            song_count: 18
          }
        ]
      end)

      # Test that leading/trailing spaces are trimmed but query still works
      {:ok, _view, html} = live(conn, "/setlists?query=%20%20radiohead%20%20")
      assert html =~ "Radiohead"
    end
  end
end
