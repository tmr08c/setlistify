defmodule SetlistifyWeb.AuthHelpers do
  @moduledoc """
  Helper functions for authentication in tests.
  """

  import Phoenix.ConnTest

  def log_in_user(conn, %{id: user_id}) do
    init_test_session(conn, %{"user_id" => user_id})
  end
end
