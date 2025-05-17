# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup & Running

```shell
# Initialize the project (first time setup)
bin/init

# Run the Phoenix server with iex
bin/server

# Install dependencies
mix deps.get

# Compile the project
mix compile

# Run tests
mix test

# Run a specific test file
mix test test/path/to/test_file.exs

# Run a specific test (line number)
mix test test/path/to/test_file.exs:123

# Format code
mix format

# Static analysis with Dialyzer
mix dialyzer
```

## Architecture

Setlistify is an Elixir/Phoenix application that integrates with:
1. Setlist.fm API - to fetch artist setlists
2. Spotify API - to create playlists from setlists

### Key Components

#### Setlist.fm Integration
- `Setlistify.SetlistFm.API` - Interface module with callbacks for searching and fetching setlists
- `Setlistify.SetlistFm.API.ExternalClient` - Implementation of the API for actual HTTP requests

#### Spotify Integration
- `Setlistify.Spotify.API` - Interface for Spotify API operations (search tracks, create playlists)
- `Setlistify.Spotify.API.ExternalClient` - Implementation for actual HTTP requests
- `Setlistify.Spotify.SessionManager` - GenServer for managing user Spotify sessions (tokens)
- `Setlistify.Spotify.SessionSupervisor` - Supervisor for session management processes

#### Token Management
- Each user has a separate token manager process identified by user ID
- Tokens are automatically refreshed before they expire
- Registry and DynamicSupervisor are used to track and manage token processes

#### Web Interface
- Phoenix LiveView for interactive UI components
- Main paths:
  - `/` - Search interface
  - `/setlist/:id` - View specific setlist
  - `/playlists` - View playlists

#### Authentication
- OAuth integration with Spotify
- Token refreshing handled with GenServer processes

### Testing

The application uses Hammox for mocking:
- `Setlistify.SetlistFm.API.MockClient` for setlist.fm API
- `Setlistify.Spotify.API.MockClient` for Spotify API
- Recommendation: use Hammox for mocks, not Mox. It has the same API as Mox.

## Environment Configuration

Required environment variables:
- `SETLIST_FM_API_SECRET` - API key for Setlist.fm
- `SPOTIFY_CLIENT_ID` - OAuth client ID for Spotify
- `SPOTIFY_CLIENT_SECRET` - OAuth client secret for Spotify

These values are automatically loaded from `.env` in development. You can copy `.env.example` to `.env` and fill in the values.

## Development Reminders

- run mix format after making changes
- mix test to run all tests
- Run format frequently to avoid style warnings