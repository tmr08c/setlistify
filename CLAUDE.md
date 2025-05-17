# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup & Development
- `bin/init` - Initialize local development environment, creates .env file from .env.example
- `bin/setup` - Install dependencies via asdf and run mix setup
- `bin/server` - Run the Phoenix server in iex mode (runs setup first)

### Build & Dependencies
- `mix deps.get` - Fetch dependencies
- `mix setup` - Setup project (runs deps.get and assets.setup)
- `mix assets.setup` - Install tailwind and esbuild
- `mix assets.deploy` - Build and minify assets for production

### Testing
- `mix test` - Run all tests
- `mix test path/to/test.exs` - Run specific test file
- `mix test path/to/test.exs:LINE` - Run specific test at line

### Code Quality
- `mix dialyzer` - Run static type analysis

## Architecture

This is a Phoenix LiveView web application that integrates Setlist.fm and Spotify APIs to create playlists from concert setlists.

### Key Modules
- `Setlistify.SetlistFm.API` - Interface for Setlist.fm API operations
- `Setlistify.Spotify.API` - Interface for Spotify API operations  
- `SetlistifyWeb.SearchLive` - Main search page LiveView
- `SetlistifyWeb.Setlists.ShowLive` - Setlist display LiveView
- `SetlistifyWeb.Playlists.ShowLive` - Playlist management LiveView

### Dependency Injection Pattern
Both API modules use a dependency injection pattern for testability:
- Real implementations: `ExternalClient` modules
- Test mocks defined in `test_helper.exs` using Hammox
- Implementation selected via application configuration

### Caching
Uses Cachex for caching with 5-minute TTL:
- `:setlist_fm_search_cache` - Setlist.fm search results
- `:setlist_fm_setlist_cache` - Individual setlist data
- `:spotify_track_cache` - Spotify track search results

### OAuth Authentication
OAuth flow handled by `OAuthCallbackController` with routes:
- `/signin/:provider` - Initiate OAuth
- `/oauth/callbacks/:provider` - Handle OAuth callback
- `/signout` - Sign out

### LiveView Sessions
All live routes use `:default` session with `SetlistifyWeb.UserAuth` mount hook for authentication.