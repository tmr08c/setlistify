defmodule SetlistifyWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias SetlistifyWeb.CoreComponents

  defp classes(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("class")
    |> List.first("")
    |> String.split()
  end

  describe "input/1 default classes" do
    for type <- ~w(text select textarea) do
      @tag type: type
      test "#{type} uses only the valid border colors without errors", %{type: type} do
        html = render_component(&CoreComponents.input/1, name: "f", value: "", type: type, options: [])
        tag = if type == "text", do: "input", else: type
        classes = classes(html, tag)

        assert "border" in classes
        assert "border-gray-800" in classes
        refute "border-rose-400" in classes
      end

      @tag type: type
      test "#{type} replaces the valid border colors with error colors", %{type: type} do
        html =
          render_component(&CoreComponents.input/1,
            name: "f",
            value: "",
            type: type,
            options: [],
            errors: ["can't be blank"]
          )

        tag = if type == "text", do: "input", else: type
        classes = classes(html, tag)

        assert "border" in classes
        assert "border-rose-400" in classes
        refute "border-gray-800" in classes
        refute "focus:border-emerald-500" in classes
      end
    end

    test "checkbox shows a visible error outline" do
      valid = render_component(&CoreComponents.input/1, name: "f", type: "checkbox")
      invalid = render_component(&CoreComponents.input/1, name: "f", type: "checkbox", errors: ["required"])

      refute "outline-rose-400" in classes(valid, "input[type=checkbox]")
      assert "outline-rose-400" in classes(invalid, "input[type=checkbox]")
    end
  end

  describe "input/1 class overrides" do
    test "class replaces all default classes" do
      html = render_component(&CoreComponents.input/1, name: "f", value: "", class: "custom")

      assert classes(html, "input") == ["custom"]
    end

    test "error_class is appended to a custom class only when there are errors" do
      assigns = [name: "f", value: "", class: "custom", error_class: "custom-error"]

      assert classes(render_component(&CoreComponents.input/1, assigns), "input") == ["custom"]

      assert classes(render_component(&CoreComponents.input/1, [errors: ["bad"]] ++ assigns), "input") ==
               ["custom", "custom-error"]
    end

    test "error_class replaces the default error colors" do
      html = render_component(&CoreComponents.input/1, name: "f", value: "", errors: ["bad"], error_class: "my-error")
      classes = classes(html, "input")

      assert "my-error" in classes
      refute "border-rose-400" in classes
      refute "border-gray-800" in classes
    end

    test "hidden input renders class" do
      html = render_component(&CoreComponents.input/1, name: "f", value: "1", type: "hidden", class: "js-target")

      assert classes(html, "input[type=hidden]") == ["js-target"]
    end
  end

  describe "input/1 labels" do
    test "renders a label when given" do
      html = render_component(&CoreComponents.input/1, id: "f", name: "f", value: "", label: "Name")

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("label[for=f]") |> Enum.count() == 1
    end

    test "renders no label element without a label" do
      html = render_component(&CoreComponents.input/1, id: "f", name: "f", value: "")

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("label") |> Enum.count() == 0
    end
  end

  describe "button/1" do
    test "renders a button element by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button type="submit" disabled>Go</CoreComponents.button>
        """)

      doc = LazyHTML.from_fragment(html)
      assert doc |> LazyHTML.query("button[type=submit][disabled]") |> Enum.count() == 1
    end

    test "renders a link styled like a button when navigate is given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button navigate="/playlists" class="extra">Go</CoreComponents.button>
        """)

      classes = classes(html, "a[href='/playlists']")
      assert "rounded-full" in classes
      assert "extra" in classes
      refute "phx-submit-loading:opacity-75" in classes
    end

    test "link and button branches share the same base classes" do
      assigns = %{}

      link = rendered_to_string(~H|<CoreComponents.button href="/x">Go</CoreComponents.button>|)
      button = rendered_to_string(~H|<CoreComponents.button>Go</CoreComponents.button>|)

      assert classes(link, "a") == classes(button, "button") -- ["phx-submit-loading:opacity-75"]
    end

    test "raises when button-only attributes are passed with navigation" do
      assigns = %{}

      assert_raise ArgumentError, ~r/:disabled/, fn ->
        rendered_to_string(~H|<CoreComponents.button navigate="/x" disabled>Go</CoreComponents.button>|)
      end

      assert_raise ArgumentError, ~r/:type/, fn ->
        rendered_to_string(~H|<CoreComponents.button href="/x" type="submit">Go</CoreComponents.button>|)
      end
    end

    test "allows disabled={false} with navigation" do
      assigns = %{}

      html = rendered_to_string(~H|<CoreComponents.button navigate="/x" disabled={false}>Go</CoreComponents.button>|)

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("a[disabled]") |> Enum.count() == 0
    end
  end
end
