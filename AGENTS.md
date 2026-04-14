This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `SetlistifyWeb.Layouts` module is aliased in `setlistify_web.ex`, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">`) with your own values, no default classes are inherited, so your custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces
- Tailwind CSS v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/setlistify_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw CSS
- **Always** manually write your own Tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendored script `src` or link `href` in the layouts
  - You must import vendor deps into app.js and app.css to use them
  - **Never write inline `<script>custom js</script>` tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc.
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. Access struct fields directly (`my_struct.field`) or use higher level APIs where available
- Elixir's standard library has everything necessary for date and time manipulation. **Never** install additional dependencies unless asked or for date/time parsing (where you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark
- Elixir's built-in OTP primitives like `DynamicSupervisor` and `Registry` require names in the child spec, such as `{DynamicSupervisor, name: Setlistify.MyDynamicSup}`, then `DynamicSupervisor.start_child(Setlistify.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. Usually pass `timeout: :infinity`

## Mix guidelines

- Read the docs and options before using tasks (`mix help task_name`)
- To debug test failures, run `mix test test/my_test.exs` or `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

  - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages

<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions — the `scope` provides the alias:

      scope "/admin", SetlistifyWeb.Admin do
        pipe_through :browser
        live "/users", UserLive, :index
      end

  the `UserLive` route points to `SetlistifyWeb.Admin.UserLive`

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or `.html.heex` files (HEEx), **never** use `~E`
- **Always** use `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access fields via `@form[:field]`
- **Always** add unique DOM IDs to key elements (forms, buttons, etc.)
- For app-wide template imports, import/alias into `setlistify_web.ex`'s `html_helpers` block so they are available to all LiveViews and modules that `use SetlistifyWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  **Always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% other_condition -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx requires `phx-no-curly-interpolation` on parent tags when you need literal `{` or `}`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

- HEEx class attrs support lists — **always** use `[...]` syntax for multiple class values:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
      ]}>Text</a>

- **Never** use `<% Enum.each %>` for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use this syntax for template comments
- **Always** use `{...}` for interpolation within tag attributes, and `<%= ... %>` for block constructs (if, cond, case, for) within tag bodies:

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_condition do %>
          {@another_assign}
        <% end %>
      </div>

  **Never** do this — the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` in LiveViews
- **Avoid LiveComponents** unless you have a strong, specific need for them
- LiveViews should be named like `SetlistifyWeb.WeatherLive`, with a `Live` suffix

### LiveView streams

- **Always** use LiveView streams for collections to avoid memory ballooning:
  - append — `stream(socket, :items, [new_item])`
  - reset — `stream(socket, :items, new_items, reset: true)`
  - prepend — `stream(socket, :items, [new_item], at: -1)`
  - delete — `stream_delete(socket, :items, item)`

- The template must set `phx-update="stream"` on the parent element and use the stream id as the child DOM id:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- Streams are *not* enumerable. To filter, refetch the data and re-stream with `reset: true`
- Streams do not support counting or empty states natively — track counts with a separate assign
- When an assign change should affect streamed item content, re-stream the affected items via `stream_insert`
- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"`

### LiveView JavaScript interop

- Anytime you use `phx-hook="MyHook"` and that hook manages its own DOM, you **must** also set `phx-update="ignore"`
- **Always** provide a unique DOM id alongside `phx-hook`

<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
