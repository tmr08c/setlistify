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

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

if ! dpkg -s libssl3 libncurses6 unzip ca-certificates gh >/dev/null 2>&1; then
  echo "==> Installing system packages (libssl3, libncurses6, unzip, gh)..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    libssl3 libncurses6 unzip ca-certificates gh >/dev/null
fi

export MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

if ! command -v mise >/dev/null 2>&1; then
  echo "==> Installing mise..."
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$MISE_DATA_DIR/shims:$PATH"

echo "==> Installing Erlang/Elixir via mise (precompiled)..."
mise install

echo "export PATH=\"$HOME/.local/bin:$MISE_DATA_DIR/shims:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# runtime.exs loads `.env` for :dev (and `.env.example` for :test). Seed `.env`
# with the same placeholders so dev compile/boot doesn't blow up on
# System.fetch_env! calls. .env is gitignored.
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
fi

mix local.hex --force --if-missing >/dev/null
mix local.rebar --force --if-missing >/dev/null

echo "==> Fetching mix dependencies..."
mix deps.get

echo "==> Setup complete."
