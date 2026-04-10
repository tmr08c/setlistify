defmodule SetlistifyWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use SetlistifyWeb, :controller
      use SetlistifyWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: SetlistifyWeb.Layouts]

      import Plug.Conn
      import SetlistifyWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {SetlistifyWeb.Layouts, :app}

      unquote(html_helpers())

      # Handle token refresh messages from PubSub
      def handle_info({:token_refreshed, new_session}, socket) do
        {:noreply, Phoenix.Component.assign(socket, :user_session, new_session)}
      end
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import SetlistifyWeb.CoreComponents
      import SetlistifyWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())

      # Helpers to add test-specific identifiers
      #
      # WARNING: If you change the pattern, you may need to update our selector
      # in `SetlistifyWeb.ConnCase`
      if Mix.env() == :prod do
        def tid(_), do: []
      else
        def tid(list) when is_list(list), do: [{:data, [{:"test-#{Enum.join(list, "-")}", true}]}]
        def tid(id), do: [{:data, [{:"test-#{id}", true}]}]
      end
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: SetlistifyWeb.Endpoint,
        router: SetlistifyWeb.Router,
        statics: SetlistifyWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
