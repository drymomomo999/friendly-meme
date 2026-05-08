#!/usr/bin/env bash
# Runs on Codespace creation (postCreateCommand) and rebuilds.
# Idempotent — npm i -g is no-op if already installed.
set -euo pipefail

# Retry helper for transient network failures (apt mirror hiccups, npm registry
# blips, PyPI timeouts). Up to 3 attempts; sleeps 5s after attempt 1, 10s after
# attempt 2 (~15s total wait budget). Returns 1 after exhaustion so set -e fires.
retry() {
  local n=0 max=3
  while ! "$@"; do
    n=$((n + 1))
    if [ $n -ge $max ]; then
      echo "ERROR: failed after $max attempts: $*" >&2
      return 1
    fi
    local delay=$((n * 5))
    echo "WARN: attempt $n failed, retrying in ${delay}s: $*" >&2
    sleep $delay
  done
}

echo "==> Installing PostgreSQL..."
# Devcontainer postgresql feature was unreliable on Universal:2 — install via apt directly.
# Universal:2 is on Ubuntu 20.04 (focal), which ships PostgreSQL 12 — fine for our SQL labs.
# Universal:2 also ships a stale Yarn apt source with an expired GPG key; remove it so
# apt-get update doesn't return exit code 100 and abort `set -e`. The `|| true`
# is a safety net in case any other upstream repo breaks similarly in the future.
sudo rm -f /etc/apt/sources.list.d/yarn.list /etc/apt/sources.list.d/yarn.sources 2>/dev/null || true
sudo apt-get update -qq || true
retry sudo apt-get install -y postgresql postgresql-contrib
pg_isready -q 2>/dev/null || sudo service postgresql start
sleep 2
# Codespaces sudoers grants passwordless sudo as root only — `sudo -u postgres` would
# prompt for a password and hang in the no-TTY postCreateCommand context. Use the
# two-step pattern: sudo (→ root, passwordless) + su -l postgres (→ no password from root).
sudo su -l postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='codespace'\"" \
  | grep -q 1 || sudo su -l postgres -c "psql -c \"CREATE ROLE codespace LOGIN SUPERUSER;\""

echo "==> Installing coding agents..."
# Pinned versions for semester stability. Bump intentionally between weeks.
retry npm install -g \
  @mariozechner/pi-coding-agent@0.70.6 \
  opencode-ai@1.14.30 \
  @anthropic-ai/claude-code@2.1.123

echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

echo "==> Pre-building lab Python venv..."
mkdir -p ~/dmdb-venv
uv venv ~/dmdb-venv/.venv --python 3.13
retry uv pip install --python ~/dmdb-venv/.venv/bin/python \
  psycopg2-binary flask sqlalchemy openai anthropic

echo "==> Wiring Pi config..."
# Pi auto-loads ~/.pi/agent/APPEND_SYSTEM.md globally; AGENTS.md at agent/ is ignored.
# Symlinks (not cp) so workspace edits flow through to Pi after a restart — eliminates
# the "two-files-of-same-name" trap where students edit the workspace copy and Pi keeps
# loading the stale home copy.
mkdir -p ~/.pi/agent/skills
ln -sfn "$(pwd)/.pi/settings.json" ~/.pi/agent/settings.json
ln -sfn "$(pwd)/.pi/models.json"   ~/.pi/agent/models.json
ln -sfn "$(pwd)/.pi/AGENTS.md"     ~/.pi/agent/APPEND_SYSTEM.md
ln -sfn "$(pwd)/skills/sql-helper" ~/.pi/agent/skills/sql-helper

echo "==> Installing pi-web-access (zero-signup web search via Exa MCP)..."
# Third-party Pi extension by nicobailon. Free, no API key needed.
# Pi-only — OpenCode uses a different extension model and doesn't get web search.
pi install npm:pi-web-access || echo "WARN: pi-web-access install failed; agent continues without web search"

echo "==> Wiring OpenCode config..."
mkdir -p ~/.config/opencode/skills
ln -sfn "$(pwd)/.config/opencode/opencode.json" ~/.config/opencode/opencode.json
ln -sfn "$(pwd)/skills/sql-helper" ~/.config/opencode/skills/sql-helper

echo "==> Wiring Claude Code config (defaulting to Kimi For Coding)..."
mkdir -p ~/.claude
cp .claude/settings.kimi.json ~/.claude/settings.json
[ -f ~/.claude.json ] || echo '{"hasCompletedOnboarding": true}' > ~/.claude.json

echo "==> Auto-loading .env on every new shell + mapping to ANTHROPIC_AUTH_TOKEN..."
# The .env file may be empty at this point — that's fine. The bashrc snippet
# re-evaluates on every new shell, so once the student pastes a key and opens
# a fresh terminal, all three agents pick up the token.
grep -q 'DMDB_AUTO_ENV' ~/.bashrc || cat >> ~/.bashrc <<'BASHRC_EOF'

# DMDB_AUTO_ENV: source workspace .env on every shell + map to Anthropic SDK
if [ -d /workspaces ]; then
  for d in /workspaces/*/; do
    [ -f "$d.env" ] && { set -a; . "$d.env"; set +a; }
  done
fi
export ANTHROPIC_AUTH_TOKEN="${KIMI_API_KEY:-${ARK_API_KEY:-}}"
BASHRC_EOF

echo "==> Scaffolding .env..."
[ -f .env ] || cp .env.example .env

cat <<BANNER

====================================================
  DMDB Codespace ready.

  Currently configured for:  Kimi For Coding (test)
  To switch to Volcengine:   cp .claude/settings.volcengine.json ~/.claude/settings.json
                             + edit ~/.pi/agent/settings.json defaultProvider
                             + change ~/.config/opencode/opencode.json model

  Next steps:
    1. Open .env in the file tree → paste KIMI_API_KEY=sk-kimi-...
    2. Open a NEW terminal tab (auto-loads .env via bashrc)
    3. bash scripts/verify.sh
    4. opencode run "say OK"
====================================================
BANNER
