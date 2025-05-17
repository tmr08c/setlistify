# Setlistify

Setlistify is a Phoenix application that allows users to create Spotify playlists from concert setlists found on Setlist.fm.

## Features

- Search for artist setlists from Setlist.fm
- View detailed setlist information
- Create Spotify playlists from setlists with a single click
- Automatic track matching between setlist songs and Spotify catalog
- Secure OAuth authentication with Spotify

## Authentication Flow

Setlistify uses OAuth2 for Spotify authentication with automatic token management:

1. **Initial Sign In**: Users are redirected to Spotify's authorization page
2. **Authorization**: After granting permissions, users are redirected back with an authorization code
3. **Token Exchange**: The code is exchanged for access and refresh tokens
4. **Session Management**: A dedicated SessionManager process manages tokens and user data
5. **Automatic Refresh**: Tokens are automatically refreshed before expiration
6. **Protected Routes**: Certain pages require authentication and redirect unauthenticated users

### SessionManager Architecture

The application uses a GenServer-based SessionManager for each authenticated user:

- Stores UserSession data (tokens, user info)
- Automatically refreshes tokens 5 minutes before expiration
- Broadcasts refresh events to LiveViews via PubSub
- Supervised by SessionSupervisor for fault tolerance
- Registered in UserSessionRegistry for easy lookup

### Protected Routes

Routes that require authentication are configured in the router:

```elixir
# HTTP routes
pipeline :require_authenticated_user do
  plug SetlistifyWeb.UserAuth, :require_authenticated_user
end

# LiveView routes
live_session :require_authenticated_user,
  on_mount: {SetlistifyWeb.Auth.LiveHooks, :ensure_authenticated} do
  live "/playlists", Playlists.ShowLive
end
```

## Development

### Getting set up

When setting up the application for the first time, run:

``` shell
bin/init
```

This will create a local `.env` file with placeholders for any secrets the application needs. To actually use the application, you will need to fill these in with valid values.

#### Required Environment Variables

- `SETLIST_FM_API_SECRET`: API key for Setlist.fm
- `SPOTIFY_CLIENT_ID`: OAuth client ID for Spotify
- `SPOTIFY_CLIENT_SECRET`: OAuth client secret for Spotify

### Running the server

``` shell
bin/server
```

This will ensure you are set up with the latest dependencies and then run the server under `iex`.

### Running tests

``` shell
mix test
```

### Code formatting

``` shell
mix format
```

## API Integration

### Setlist.fm API

- Search for setlists by artist name
- Fetch detailed setlist information
- No authentication required (API key only)

### Spotify API

- Search for tracks to match setlist songs
- Create playlists in user's account
- Add tracks to playlists
- Requires OAuth authentication with `playlist-modify-private` scope

## Architecture

The application follows standard Phoenix patterns with some custom components:

- **LiveView**: Interactive UI without JavaScript
- **SessionManager**: GenServer-based token management
- **API Clients**: Separate modules for external API integration
- **Hammox**: Mocking framework for testing external APIs

For more details, see the module documentation and tech specs in the `docs/` directory.
