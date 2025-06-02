defmodule Setlistify.SetlistFm.API.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.SetlistFm.API.ExternalClient

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  @search_response fixture_dir() |> Path.join("setlist_fm_search_response.json") |> File.read!()
  test "search/1" do
    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        assert conn.params["artistName"] == "modest mouse"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@search_response)))
    end)

    [event | _] = result = ExternalClient.search("modest mouse")

    assert length(result) == 20
    assert event.artist == "Modest Mouse"
    assert event.venue.name == "9:30 Club"
    assert event.date == Date.new!(2022, 12, 20)
    assert event.id

    # Check total song count - the first setlist has 15 + 5 = 20 songs total
    assert event.song_count == 20

    # Check venue location
    assert event.venue.location.city == "Washington"
    assert event.venue.location.state == "DC"
    assert event.venue.location.country == "United States"
  end

  test "search/1 handles international venues without state" do
    # Create a response with different venue formats
    response = %{
      "setlist" => [
        %{
          "artist" => %{"name" => "The Beatles"},
          "eventDate" => "01-01-2023",
          "id" => "test-id-1",
          "venue" => %{
            "name" => "Royal Albert Hall",
            "city" => %{
              "name" => "London",
              "country" => %{"name" => "United Kingdom"}
              # Note: no stateCode for UK venues
            }
          },
          "sets" => %{"set" => [%{"song" => [%{"name" => "Hey Jude"}]}]}
        },
        %{
          "artist" => %{"name" => "The Beatles"},
          "eventDate" => "02-01-2023",
          "id" => "test-id-2",
          "venue" => %{
            "name" => "Maple Leaf Gardens",
            "city" => %{
              "name" => "Toronto",
              "stateCode" => "ON",
              "country" => %{"name" => "Canada"}
            }
          },
          "sets" => %{"set" => [%{"song" => [%{"name" => "Let It Be"}]}]}
        }
      ]
    }

    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end)

    [uk_event, canada_event] = ExternalClient.search("beatles")

    # UK venue without state
    assert uk_event.venue.location.city == "London"
    assert uk_event.venue.location.state == nil
    assert uk_event.venue.location.country == "United Kingdom"

    # Canadian venue with state
    assert canada_event.venue.location.city == "Toronto"
    assert canada_event.venue.location.state == "ON"
    assert canada_event.venue.location.country == "Canada"
  end

  test "search/1 handles missing or malformed venue data" do
    response = %{
      "setlist" => [
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "01-01-2023",
          "id" => "test-id",
          "venue" => %{
            "name" => "Test Venue",
            # Empty city data
            "city" => %{}
          },
          "sets" => %{"set" => []}
        }
      ]
    }

    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end)

    [event] = ExternalClient.search("test")

    # Should handle missing data gracefully
    assert event.venue.location.city == "Unknown"
    assert event.venue.location.state == nil
    assert event.venue.location.country == "Unknown"
    assert event.song_count == 0
  end

  test "search/1 correctly calculates song counts for various set configurations" do
    response = %{
      "setlist" => [
        # Setlist with no songs
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "01-01-2023",
          "id" => "test-id-1",
          "venue" => %{
            "name" => "Empty Venue",
            "city" => %{
              "name" => "Austin",
              "stateCode" => "TX",
              "country" => %{"name" => "United States"}
            }
          },
          "sets" => %{"set" => []}
        },
        # Setlist with one set
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "02-01-2023",
          "id" => "test-id-2",
          "venue" => %{
            "name" => "Single Set Venue",
            "city" => %{
              "name" => "Seattle",
              "stateCode" => "WA",
              "country" => %{"name" => "United States"}
            }
          },
          "sets" => %{
            "set" => [
              %{
                "name" => "Main Set",
                "song" => [
                  %{"name" => "Song 1"},
                  %{"name" => "Song 2"},
                  %{"name" => "Song 3"}
                ]
              }
            ]
          }
        },
        # Setlist with multiple sets
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "03-01-2023",
          "id" => "test-id-3",
          "venue" => %{
            "name" => "Multi Set Venue",
            "city" => %{
              "name" => "Chicago",
              "stateCode" => "IL",
              "country" => %{"name" => "United States"}
            }
          },
          "sets" => %{
            "set" => [
              %{
                "name" => "Opening Set",
                "song" => [
                  %{"name" => "Opening Song 1"},
                  %{"name" => "Opening Song 2"}
                ]
              },
              %{
                "name" => "Main Set",
                "song" => [
                  %{"name" => "Main Song 1"},
                  %{"name" => "Main Song 2"},
                  %{"name" => "Main Song 3"}
                ]
              }
            ]
          }
        },
        # Setlist with set and encore
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "04-01-2023",
          "id" => "test-id-4",
          "venue" => %{
            "name" => "Encore Venue",
            "city" => %{
              "name" => "Nashville",
              "stateCode" => "TN",
              "country" => %{"name" => "United States"}
            }
          },
          "sets" => %{
            "set" => [
              %{
                "name" => "Main Set",
                "song" => [
                  %{"name" => "Main Song 1"},
                  %{"name" => "Main Song 2"},
                  %{"name" => "Main Song 3"},
                  %{"name" => "Main Song 4"}
                ]
              },
              %{
                "encore" => 1,
                "song" => [
                  %{"name" => "Encore Song 1"},
                  %{"name" => "Encore Song 2"}
                ]
              }
            ]
          }
        }
      ]
    }

    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end)

    [no_songs, one_set, multiple_sets, set_with_encore] = ExternalClient.search("test artist")

    # Test setlist with no songs
    assert no_songs.song_count == 0
    assert no_songs.venue.name == "Empty Venue"
    assert no_songs.venue.location.city == "Austin"

    # Test setlist with one set
    assert one_set.song_count == 3
    assert one_set.venue.name == "Single Set Venue"
    assert one_set.venue.location.city == "Seattle"

    # Test setlist with multiple sets
    assert multiple_sets.song_count == 5
    assert multiple_sets.venue.name == "Multi Set Venue"
    assert multiple_sets.venue.location.city == "Chicago"

    # Test setlist with set and encore
    assert set_with_encore.song_count == 6
    assert set_with_encore.venue.name == "Encore Venue"
    assert set_with_encore.venue.location.city == "Nashville"
  end

  @not_found_response fixture_dir()
                      |> Path.join("setlist_fm_search_404_response.json")
                      |> File.read!()
  test "search/1 returns empty list when no results found (404)" do
    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        assert conn.params["artistName"] == "nonexistent"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(404, @not_found_response)
    end)

    result = ExternalClient.search("nonexistent")
    assert result == []
  end

  test "search/1 handles sets with missing or empty song arrays" do
    response = %{
      "setlist" => [
        %{
          "artist" => %{"name" => "Test Artist"},
          "eventDate" => "01-01-2023",
          "id" => "test-id-1",
          "venue" => %{
            "name" => "Test Venue",
            "city" => %{
              "name" => "Portland",
              "stateCode" => "OR",
              "country" => %{"name" => "United States"}
            }
          },
          "sets" => %{
            "set" => [
              # Set with empty song array
              %{
                "name" => "Empty Set",
                "song" => []
              },
              # Set with missing song key (no songs)
              %{
                "name" => "No Song Key"
              },
              # Set with songs
              %{
                "name" => "Normal Set",
                "song" => [
                  %{"name" => "Song 1"},
                  %{"name" => "Song 2"}
                ]
              }
            ]
          }
        }
      ]
    }

    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end)

    [result] = ExternalClient.search("test artist")

    # Should count only the songs from the normal set
    assert result.song_count == 2
    assert result.venue.location.city == "Portland"
  end

  @get_response fixture_dir() |> Path.join("setlist_fm_setlist_response.json") |> File.read!()
  test "get_setlist/1" do
    id = Ecto.UUID.generate()

    Req.Test.stub(MySetlistFmStub, fn %{request_path: "/rest/1.0/setlist/" <> rest, method: "GET"} =
                                        conn ->
      assert rest == id

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@get_response)))
    end)

    result = ExternalClient.get_setlist(id)

    assert result.artist == "Modest Mouse"
    assert result.venue.name == "Terminal 5"
    assert result.venue.location.city == "New York"
    assert result.venue.location.state == "NY"
    assert result.venue.location.country == "United States"
    assert result.date == Date.new!(2022, 12, 19)
    assert length(result.sets) == 3
    assert Enum.count(result.sets, & &1.encore) == 1

    for %{songs: songs} <- result.sets do
      assert length(songs) > 0
    end
  end
end
