defmodule SetlistifyWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SetlistifyWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SetlistifyWeb.Endpoint

      use SetlistifyWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SetlistifyWeb.ConnCase

      # Import test helpers
      import Setlistify.Test.RegistryHelpers

      # Find elements using the test-specific identifier pattern set up in
      # `UrlStordenerWeb.html_helper`
      defp tid(id), do: "[data-test-#{id}]"

      def assert_has_element(html, selector, opts \\ []) do
        expected = Keyword.get(opts, :count, 1)
        actual = html |> Floki.find(selector) |> length()

        assert expected == actual,
               "expected #{expected} elements matching #{selector}, found #{actual}"
      end
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def authenticate_conn(conn, user_id) do
    Plug.Test.init_test_session(conn, user_id: user_id, auth_provider: "spotify")
  end
end
