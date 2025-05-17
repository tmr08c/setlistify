defmodule SetlistifyWeb.Router do
  use SetlistifyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {SetlistifyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    # TODO Does this need to be a separate plug? Could we only check it if we try to auth the user and find we can't find them in the Registry look up
    plug SetlistifyWeb.Plugs.RestoreSpotifyToken
  end

  pipeline :require_authenticated_user do
    plug SetlistifyWeb.UserAuth, :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SetlistifyWeb do
    pipe_through :browser

    # TODO I may want to see if the user is already logged in and redirect
    # accordingly
    get "/oauth/callbacks/:provider", OAuthCallbackController, :new
    get "/signin/:provider", OAuthCallbackController, :sign_in
    get "/signout", OAuthCallbackController, :sign_out

    live_session :default, on_mount: SetlistifyWeb.Auth.LiveHooks do
      live "/", SearchLive
      live "/setlist/:id", Setlists.ShowLive
    end

    live_session :require_authenticated_user,
      on_mount: {SetlistifyWeb.Auth.LiveHooks, :ensure_authenticated} do
      live "/playlists", Playlists.ShowLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SetlistifyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:setlistify, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SetlistifyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
