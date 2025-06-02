defmodule SetlistifyWeb.Components.SearchFormComponentTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SetlistifyWeb.Components.SearchFormComponent

  # Simple wrapper LiveView for testing component interactions
  defmodule TestLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      {:ok, assign(socket, input_id: "test-input", query_params: %{})}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={SearchFormComponent}
        id="test-component"
        input_id={@input_id}
        query_params={@query_params}
      />
      """
    end
  end

  test "component mounts with empty search form by default" do
    assigns = %{input_id: "test-input", id: "test-component"}

    component =
      render_component(SearchFormComponent, assigns)

    assert component =~ ~s(id="test-input")
    assert component =~ ~s(placeholder="Search for an artist or band...")
    # Empty input doesn't render value attribute
    refute component =~ ~s(value=)
  end

  test "component receives initial query from query_params" do
    assigns = %{
      input_id: "test-input",
      id: "test-component",
      query_params: %{"query" => "some artist"}
    }

    component =
      render_component(SearchFormComponent, assigns)

    assert component =~ ~s(value="some artist")
  end

  test "component handles empty query_params" do
    assigns = %{
      input_id: "test-input",
      id: "test-component",
      query_params: %{}
    }

    component =
      render_component(SearchFormComponent, assigns)

    # Empty input doesn't render value attribute
    refute component =~ ~s(value=)
  end

  test "component handles nil query_params" do
    assigns = %{
      input_id: "test-input",
      id: "test-component"
      # Don't pass query_params at all to test nil handling
    }

    component =
      render_component(SearchFormComponent, assigns)

    # Empty input doesn't render value attribute
    refute component =~ ~s(value=)
  end

  test "form attributes are correctly set" do
    assigns = %{input_id: "test-input", id: "test-component"}

    component =
      render_component(SearchFormComponent, assigns)

    assert component =~ ~s(name="search")
    assert component =~ ~s(phx-submit="search")
    assert component =~ ~s(name="search[query]")
    assert component =~ ~s(type="text")
    assert component =~ ~s(autocomplete="off")
  end

  test "form has correct CSS classes when no errors" do
    assigns = %{input_id: "test-input", id: "test-component"}

    component =
      render_component(SearchFormComponent, assigns)

    assert component =~ "border-gray-700 hover:border-gray-600"
    refute component =~ "border-rose-400"
  end

  test "form shows validation error when query is blank" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    result =
      view
      |> form("[name='search']", %{search: %{query: ""}})
      |> render_submit()

    assert result =~ "can&#39;t be blank"
    assert result =~ "border-rose-400"
    refute result =~ "border-gray-700 hover:border-gray-600"
  end

  test "form navigates to search results on valid submission" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    view
    |> form("[name='search']", %{search: %{query: "beatles"}})
    |> render_submit()

    assert_redirected(view, "/setlists?query=beatles")
  end

  test "form preserves query in URL when navigating" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    view
    |> form("[name='search']", %{search: %{query: "the beatles"}})
    |> render_submit()

    assert_redirected(view, "/setlists?query=the+beatles")
  end

  test "form handles special characters in query" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    view
    |> form("[name='search']", %{search: %{query: "AC/DC"}})
    |> render_submit()

    assert_redirected(view, "/setlists?query=AC%2FDC")
  end

  test "form handles unicode characters in query" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    view
    |> form("[name='search']", %{search: %{query: "Björk"}})
    |> render_submit()

    assert_redirected(view, "/setlists?query=Bj%C3%B6rk")
  end

  test "submit button has correct styling and icon" do
    assigns = %{input_id: "test-input", id: "test-component"}

    component =
      render_component(SearchFormComponent, assigns)

    assert component =~ ~s(type="submit")
    assert component =~ "bg-emerald-500"
    assert component =~ "hover:bg-emerald-400"
    assert component =~ "rounded-full"
    # Check for the SVG path instead of the component name
    assert component =~ "m21 21-5.197-5.197"
  end

  test "component respects different input_id values" do
    assigns_1 = %{input_id: "search-input-1", id: "test-component-1"}
    assigns_2 = %{input_id: "search-input-2", id: "test-component-2"}

    component_1 = render_component(SearchFormComponent, assigns_1)
    component_2 = render_component(SearchFormComponent, assigns_2)

    assert component_1 =~ ~s(id="search-input-1")
    assert component_2 =~ ~s(id="search-input-2")
  end

  test "error message display and styling" do
    {:ok, view, _html} = live_isolated(build_conn(), TestLive)

    result =
      view
      |> form("[name='search']", %{search: %{query: ""}})
      |> render_submit()

    # Check error is displayed
    assert result =~ "can&#39;t be blank"
    # Check error styling is applied
    assert result =~ "border-rose-400"
    # Check error container exists
    assert result =~ ~s(class="mt-2")
  end

  test "component updates when query_params change" do
    assigns = %{
      input_id: "test-input",
      id: "test-component",
      query_params: %{"query" => "initial"}
    }

    component_1 = render_component(SearchFormComponent, assigns)
    assert component_1 =~ ~s(value="initial")

    # Update with new query_params
    updated_assigns = %{
      input_id: "test-input",
      id: "test-component",
      query_params: %{"query" => "updated"}
    }

    component_2 = render_component(SearchFormComponent, updated_assigns)
    assert component_2 =~ ~s(value="updated")
  end
end
