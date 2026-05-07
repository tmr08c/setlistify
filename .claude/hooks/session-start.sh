#!/usr/bin/env bash
# SessionStart hook: install Erlang/Elixir + mix deps so Claude Code on the
# web can run `mix test`, `mix format`, and `mix credo` immediately.
#
# - Only runs in remote (web) sessions; no-ops locally where mise is used.
# - Installs precompiled OTP & Elixir from builds.hex.pm (same artifacts the
#   erlef/setup-beam GitHub Action uses in CI). Versions come from .mise.toml.
# - Idempotent: subsequent runs reuse the cached install + deps.

set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

ERLANG_VERSION=$(awk -F'"' '/^erlang/{print $2}' .mise.toml)
ELIXIR_VERSION=$(awk -F'"' '/^elixir/{print $2}' .mise.toml)
UBUNTU_VERSION=$(. /etc/os-release && echo "$VERSION_ID")

INSTALL_ROOT="$HOME/.beam"
ERLANG_HOME="$INSTALL_ROOT/otp-$ERLANG_VERSION"
ELIXIR_HOME="$INSTALL_ROOT/elixir-$ELIXIR_VERSION"

if ! dpkg -s libssl3 libncurses6 unzip ca-certificates gh >/dev/null 2>&1; then
  echo "==> Installing system packages (libssl3, libncurses6, unzip, gh)..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    libssl3 libncurses6 unzip ca-certificates gh >/dev/null
fi

if [ ! -x "$ERLANG_HOME/bin/erl" ]; then
  echo "==> Downloading precompiled OTP $ERLANG_VERSION (ubuntu-$UBUNTU_VERSION)..."
  rm -rf "$ERLANG_HOME"
  mkdir -p "$ERLANG_HOME"
  curl -fsSL "https://builds.hex.pm/builds/otp/ubuntu-${UBUNTU_VERSION}/OTP-${ERLANG_VERSION}.tar.gz" \
    | tar -xz -C "$ERLANG_HOME" --strip-components=1
  (cd "$ERLANG_HOME" && ./Install -minimal "$ERLANG_HOME" >/dev/null)
fi
export PATH="$ERLANG_HOME/bin:$PATH"

if [ ! -x "$ELIXIR_HOME/bin/elixir" ]; then
  echo "==> Downloading precompiled Elixir $ELIXIR_VERSION..."
  rm -rf "$ELIXIR_HOME"
  mkdir -p "$ELIXIR_HOME"
  TMPZIP=$(mktemp /tmp/elixir.XXXXXX.zip)
  curl -fsSL -o "$TMPZIP" "https://builds.hex.pm/builds/elixir/v${ELIXIR_VERSION}.zip"
  unzip -q -o "$TMPZIP" -d "$ELIXIR_HOME"
  rm -f "$TMPZIP"
fi
export PATH="$ELIXIR_HOME/bin:$PATH"

echo "export PATH=\"$ELIXIR_HOME/bin:$ERLANG_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

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

echo "==> Compiling (dev)..."
mix compile

echo "==> Compiling (test)..."
MIX_ENV=test mix compile

echo "==> Setup complete."
