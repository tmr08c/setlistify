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

Optional environment variables for Grafana Cloud observability:
- `GRAFANA_CLOUD_API_KEY` - API key for Grafana Cloud (shared for all services)
- `GRAFANA_CLOUD_USER_ID` - User ID for Tempo from Grafana Cloud
- `GRAFANA_CLOUD_TEMPO_ENDPOINT` - Tempo endpoint for traces
- `GRAFANA_CLOUD_LOKI_ENDPOINT` - Loki endpoint for logs (must include /loki/api/v1/push)
- `GRAFANA_CLOUD_LOKI_USER_ID` - User ID for Loki (usually different from Tempo)
- `GRAFANA_CLOUD_REGION` - Cloud region (defaults to "us-central1")
- `GRAFANA_CLOUD_ZONE` - Cloud zone (optional)

These values are automatically loaded from `.env` in development. You can copy `.env.example` to `.env` and fill in the values.

## Tidewave MCP

When the server is running, Tidewave MCP tools are available. Prefer them over static analysis when they can give a more direct answer.

- **Debugging errors or unexpected behavior** — call `get_logs` first to see what actually happened at runtime before reading code
- **Inspecting live state** — use `project_eval` to query the running app (e.g., check Registry entries, GenServer state, ETS tables)
- **Looking up library APIs** — use `package_docs_search` instead of relying on training data; Elixir ecosystem moves fast
- **Finding where something is defined** — `get_source_location` resolves module/function to file + line faster than grepping deps

If Tidewave tools are unavailable (server not running), fall back to static tools normally.

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Use the appropriate type prefix:

| Type | When to use |
|------|-------------|
| `feat` | A new end-user-facing feature |
| `fix` | A bug fix visible to users |
| `chore` | Internal changes: refactors, dependency updates, tooling, code organization |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `ci` | CI/CD configuration changes |
| `perf` | Performance improvements |

**Key distinction:** `feat` is for things users notice; `chore` is for everything else internal. For example, adopting a new code pattern, migrating a framework API, or adding a struct for internal use are all `chore`, not `feat`.

## Development Reminders

- Run `mix format` after making changes (includes Styler auto-rewrites)
- Run `mix credo --strict` to check for static analysis issues
- Run `mix test` to run all tests
- Run format frequently to avoid style warnings, especially before planning to commit
