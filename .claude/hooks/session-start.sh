#!/usr/bin/env bash
# SessionStart hook: install Erlang/Elixir + mix deps so Claude Code on the
# web can run `mix test`, `mix format`, and `mix credo` immediately.
#
# - Only runs in remote (web) sessions; no-ops locally where mise is already set up.
# - Uses mise to install the versions pinned in .mise.toml. The repo sets
#   `[settings.erlang] compile = false`, so mise pulls precompiled OTP from
#   builds.hex.pm instead of compiling from source.
# - Idempotent: subsequent runs reuse the cached install + deps.

set -euo pipefail

# Retry a command up to 3 times with exponential backoff (2s, 4s). hex.pm
# occasionally returns 503 from builds.hex.pm or trips transient DNS errors
# on this base image; without retries one blip leaves the environment
# half-installed and breaks `mix test` for the rest of the session.
# Progress messages go to stderr so callers can `>/dev/null` the wrapped
# command's stdout without hiding the retry log.
retry() {
  local attempt=1 delay=2
  until "$@"; do
    if [ "$attempt" -ge 3 ]; then
      return 1
    fi
    echo "==> ${*@Q} failed (attempt $attempt); retrying in ${delay}s..." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

SYSTEM_PACKAGES=(libssl3 libncurses6 unzip ca-certificates gh)

if ! dpkg -s "${SYSTEM_PACKAGES[@]}" >/dev/null 2>&1; then
  echo "==> Installing system packages (${SYSTEM_PACKAGES[*]})..."
  retry apt-get update -qq
  retry env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    "${SYSTEM_PACKAGES[@]}" >/dev/null
fi

export MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

# `curl | sh` is a pipeline, so wrap it in a function — that way retry retries
# the whole pipeline (including the inherited `pipefail`) instead of just curl.
install_mise() {
  curl -fsSL https://mise.run | sh
}

# `mise --version` rather than `command -v mise` so a half-installed binary
# from a previous failed run is replaced instead of silently passing the check.
if ! mise --version >/dev/null 2>&1; then
  echo "==> Installing mise..."
  retry install_mise
fi
export PATH="$HOME/.local/bin:$MISE_DATA_DIR/shims:$PATH"

# Trust the project's mise config so `mise install` doesn't refuse to run.
mise trust "$CLAUDE_PROJECT_DIR/.mise.toml" >/dev/null

echo "==> Installing Erlang/Elixir via mise (precompiled)..."
retry mise install

# Point Hex/Erlang at the system CA bundle. Without this, `mix deps.get` fails
# with "TLS client: Unknown CA" against repo.hex.pm on this base image.
export HEX_CACERTS_PATH="/etc/ssl/certs/ca-certificates.crt"

# Hex's parallel registry fetch trips spurious "DNS resolution failure" errors
# in this sandbox; serialising the requests avoids them. Scoped to this script
# only — persisting it would slow every later `mix deps.get` in the session
# even when the DNS issue isn't biting.
export HEX_HTTP_CONCURRENCY=1

# Persist env exports for later shells in this session. Guard against duplicate
# appends so re-runs of the hook (resume, etc.) don't pile up the same lines.
append_env() {
  local line="$1"
  if ! grep -qxF "$line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    echo "$line" >> "$CLAUDE_ENV_FILE"
  fi
}

append_env "export PATH=\"$HOME/.local/bin:$MISE_DATA_DIR/shims:\$PATH\""
append_env "export HEX_CACERTS_PATH=\"/etc/ssl/certs/ca-certificates.crt\""

# runtime.exs loads `.env` for :dev (and `.env.example` for :test). Seed `.env`
# with the same placeholders so dev compile/boot doesn't blow up on
# System.fetch_env! calls. .env is gitignored.
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
fi

retry mix local.hex --force --if-missing >/dev/null
retry mix local.rebar --force --if-missing >/dev/null

echo "==> Fetching mix dependencies..."
retry mix deps.get

echo "==> Setup complete."
