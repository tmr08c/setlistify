defmodule SetlistifyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: SetlistifyWeb.Gettext

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-900 text-emerald-100 ring-emerald-500",
        @kind == :error && "bg-rose-900 text-rose-100 shadow-md ring-rose-500"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" /> {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button
        type="button"
        class="group absolute top-1 right-1 p-2 cursor-pointer"
        aria-label={gettext("close")}
      >
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a button.

  When `href`, `navigate`, or `patch` is passed, renders a `<.link>` styled as
  a button. Otherwise renders a `<button>` element.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
      <.button navigate={~p"/playlists"}>View Playlists</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch method download disabled form name value)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link
        class={[
          "phx-submit-loading:opacity-75 inline-flex items-center justify-center rounded-full",
          "bg-emerald-500 hover:bg-emerald-400 px-8 py-3",
          "text-base font-semibold text-black transition-colors",
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button
        type={@type}
        class={[
          "phx-submit-loading:opacity-75 rounded-full bg-emerald-500 hover:bg-emerald-400 px-8 py-3",
          "text-base font-semibold text-black transition-colors",
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range search select tel text textarea time url week)

  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      id={@id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      {@rest}
    />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-gray-300">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            @class || "rounded border-gray-700 bg-gray-800 text-emerald-500 focus:ring-emerald-500",
            @errors != [] && (@error_class || "border-rose-400")
          ]}
          {@rest}
        /> {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          @class ||
            "mt-2 block w-full rounded-lg border border-gray-800 bg-gray-900 text-white focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500 sm:text-sm",
          @errors != [] && (@error_class || "border-rose-400 focus:border-rose-400")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class ||
            "mt-2 block w-full rounded-lg bg-gray-900 text-white focus:ring-2 focus:ring-emerald-500 sm:text-sm sm:leading-6 min-h-[6rem] border-gray-800 focus:border-emerald-500",
          @errors != [] && (@error_class || "border-rose-400 focus:border-rose-400")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class ||
            "mt-2 block w-full rounded-lg bg-gray-900 text-white border border-gray-800 focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500 sm:text-sm sm:leading-6",
          @errors != [] && (@error_class || "border-rose-400 focus:border-rose-400")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-gray-300">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-white">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-gray-400">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-gray-400">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-gray-800 border-t border-gray-800 text-sm leading-6 text-gray-300"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-gray-900">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-gray-900 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-white"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-gray-900 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-emerald-400 hover:text-emerald-300"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-gray-800">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-gray-400">{item.title}</dt>
          <dd class="text-white">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SetlistifyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SetlistifyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders the Setlistify logo (a vinyl record with grooves).
  """
  def logo(assigns) do
    ~H"""
    <div class="w-8 h-8 bg-emerald-500 rounded-full flex items-center justify-center relative">
      <%!-- Record grooves with better spacing and contrast --%>
      <div class="absolute w-7 h-7 border-[1.5px] border-black/20 rounded-full"></div>
      <div class="absolute w-5 h-5 border-[1.5px] border-black/20 rounded-full"></div>
      <div class="absolute w-3 h-3 border border-black/20 rounded-full"></div>

      <%!-- Center hole --%>
      <div class="w-2 h-2 bg-black rounded-full"></div>
    </div>
    """
  end

  @doc """
  Renders a search input with integrated button.
  """
  attr :placeholder, :string, default: "Search..."
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :rest, :global

  def search_input(assigns) do
    ~H"""
    <div class="relative w-full max-w-2xl">
      <input
        type="text"
        id={@id}
        name={@name}
        value={@value}
        class="w-full px-4 sm:px-6 py-3 sm:py-4 pr-14 sm:pr-16 text-sm sm:text-base text-white bg-gray-900 border border-gray-800 rounded-full placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent"
        placeholder={@placeholder}
        {@rest}
      />
      <button
        type="submit"
        class="absolute right-2 sm:right-3 top-1/2 -translate-y-1/2 w-9 h-9 sm:w-10 sm:h-10 bg-emerald-500 rounded-full flex items-center justify-center hover:bg-emerald-400 transition-colors"
      >
        <.icon name="hero-magnifying-glass" class="w-4 h-4 sm:w-5 sm:h-5 text-black" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a hero section with centered content.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def hero_section(assigns) do
    ~H"""
    <section class={["h-[calc(100vh-6rem)] flex flex-col", @class]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders rotating text with animation.
  """
  attr :texts, :list, required: true
  attr :class, :string, default: nil
  attr :text_class, :string, default: nil

  def rotating_text(assigns) do
    # When @text_class is provided, it completely replaces the default text styles
    assigns =
      assign(
        assigns,
        :computed_text_classes,
        if assigns[:text_class] do
          assigns.text_class
        else
          "text-emerald-300 text-lg sm:text-xl md:text-2xl font-medium text-center px-4"
        end
      )

    ~H"""
    <div class={["w-full h-12 flex justify-center items-center", @class]}>
      <div
        id="rotating-text"
        class={[@computed_text_classes]}
        phx-hook="RotatingText"
        phx-update="ignore"
        data-texts={JSON.encode!(@texts)}
      >
        <span>{List.first(@texts)}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a step card for the "How it Works" section.
  """
  attr :number, :integer, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def step_card(assigns) do
    ~H"""
    <div class={[
      "bg-black/30 backdrop-blur-sm border border-gray-800 rounded-xl p-6 flex flex-col items-center text-center",
      @class
    ]}>
      <div class="w-16 h-16 bg-emerald-500 rounded-full flex items-center justify-center text-black font-bold text-2xl mb-4">
        {@number}
      </div>
      <h3 class="text-xl font-semibold mb-3">{@title}</h3>
      <p class="text-gray-400 leading-relaxed">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  @doc """
  Renders a section container with consistent padding.
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def section_container(assigns) do
    ~H"""
    <section id={@id} class={["py-8 sm:py-20 px-4", @class]}>
      <div class="max-w-6xl mx-auto">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
