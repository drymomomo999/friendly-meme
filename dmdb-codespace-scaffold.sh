#!/usr/bin/env bash
# DMDB Codespace scaffold — creates 14 files in the current directory.
# Generates a dual-provider setup: Kimi For Coding (test) + Volcengine (production).
#
# Usage (run inside an empty Codespace):
#   bash dmdb-codespace-scaffold.sh
#
# Companion playbook: docs/DMDB Codespace Setup Playbook.md
set -euo pipefail

echo "==> Creating directory structure..."
mkdir -p .devcontainer .pi .config/opencode .claude \
         skills/sql-helper scripts lab-data

echo "==> [1/14] .devcontainer/devcontainer.json"
cat > .devcontainer/devcontainer.json <<'DEVCONTAINER_EOF'
{
  "name": "DMDB 2026 Spring — Vibe Coding Lab",
  "image": "mcr.microsoft.com/devcontainers/universal:2-linux",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "postStartCommand": "echo 'Welcome to DMDB. Run: cat README.md'",
  "remoteEnv": {
    "PATH": "${containerEnv:PATH}:/home/codespace/.local/bin"
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-azuretools.vscode-postgresql",
        "redhat.vscode-yaml",
        "tamasfe.even-better-toml"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "forwardPorts": [5432, 4096],
  "portsAttributes": {
    "5432": { "label": "PostgreSQL", "onAutoForward": "silent" },
    "4096": { "label": "OpenCode Server", "onAutoForward": "silent" }
  },
  "remoteUser": "codespace",
  "updateRemoteUserUID": true
}
DEVCONTAINER_EOF

echo "==> [2/14] .devcontainer/setup.sh"
cat > .devcontainer/setup.sh <<'SETUP_EOF'
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
SETUP_EOF
chmod +x .devcontainer/setup.sh

echo "==> [3/14] .pi/settings.json"
cat > .pi/settings.json <<'PI_SETTINGS_EOF'
{
  "defaultProvider": "kimi-direct",
  "defaultModel": "kimi-for-coding",
  "defaultThinkingLevel": "medium",
  "theme": "dark",
  "skills": [
    "/home/codespace/.pi/agent/skills"
  ],
  "compaction": {
    "enabled": true,
    "thresholdTokens": 80000
  }
}
PI_SETTINGS_EOF

echo "==> [4/14] .pi/models.json"
cat > .pi/models.json <<'PI_MODELS_EOF'
{
  "providers": {
    "kimi-direct": {
      "baseUrl": "https://api.kimi.com/coding",
      "api": "anthropic-messages",
      "apiKey": "KIMI_API_KEY",
      "authHeader": true,
      "models": [
        { "id": "kimi-for-coding", "contextWindow": 262144, "maxTokens": 32768, "input": ["text", "image"] }
      ]
    },
    "volcengine-coding-plan": {
      "baseUrl": "https://ark.cn-beijing.volces.com/api/coding/v3",
      "api": "openai-completions",
      "apiKey": "ARK_API_KEY",
      "authHeader": true,
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
        "supportsStore": false,
        "supportsUsageInStreaming": true,
        "maxTokensField": "max_tokens"
      },
      "models": [
        { "id": "ark-code-latest",      "contextWindow": 256000, "maxTokens": 4096 },
        { "id": "kimi-k2.6",            "contextWindow": 256000, "maxTokens": 4096 },
        { "id": "kimi-k2.5",            "contextWindow": 256000, "maxTokens": 4096 },
        { "id": "doubao-seed-2.0-code", "contextWindow": 256000, "maxTokens": 4096 },
        { "id": "doubao-seed-code",     "contextWindow": 256000, "maxTokens": 4096 },
        { "id": "deepseek-v3.2",        "contextWindow": 128000, "maxTokens": 4096 },
        { "id": "glm-5.1",              "contextWindow": 200000, "maxTokens": 4096 },
        { "id": "minimax-latest",       "contextWindow": 200000, "maxTokens": 4096 }
      ]
    }
  }
}
PI_MODELS_EOF

echo "==> [5/14] .pi/AGENTS.md"
cat > .pi/AGENTS.md <<'PI_AGENTS_EOF'
# DMDB Codespace — Pi Agent Guide

You are a coding agent inside a GitHub Codespace for the SUSTech 2026 Spring
DMDB course. The student is learning database design and AI-assisted coding
workflows.

## Environment
- Python 3.13 venv at `~/dmdb-venv/.venv` (use `uv pip install` to add packages)
- PostgreSQL 16 client (`psql`); server starts on demand via `sql-helper` skill
- Lab data under `./lab-data/`

## Style
- Default to short, working code over long explanations
- When asked to write SQL, ALSO show the explain-plan via `EXPLAIN`
- Cite course documents from `docs/labs/` when relevant

## Tools available
- `web_search` (via pi-web-access extension) — zero-signup web search via Exa MCP. Use sparingly; prefer cited course docs first.
- `sql-helper` skill — start Postgres, dump schema, run queries against `dmdb` DB

## What NOT to do
- Don't propose installing global Python packages with pip — use the project venv
- Don't `git push` without the student's explicit OK
- Don't write keys back into `.env` even if asked
PI_AGENTS_EOF

echo "==> [6/14] .config/opencode/opencode.json"
cat > .config/opencode/opencode.json <<'OPENCODE_EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "kimi-direct/kimi-for-coding",
  "autoupdate": false,
  "provider": {
    "kimi-direct": {
      "npm": "@ai-sdk/anthropic",
      "name": "Kimi For Coding",
      "options": {
        "baseURL": "https://api.kimi.com/coding/v1",
        "apiKey": "{env:KIMI_API_KEY}"
      },
      "models": {
        "kimi-for-coding": {
          "name": "kimi-for-coding",
          "limit": { "context": 262144, "output": 32768 },
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        }
      }
    },
    "volcengine-coding-plan": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Volcano Engine",
      "options": {
        "baseURL": "https://ark.cn-beijing.volces.com/api/coding/v3",
        "apiKey": "{env:ARK_API_KEY}"
      },
      "models": {
        "ark-code-latest":      { "name": "ark-code-latest",      "limit": { "context": 256000, "output": 4096 } },
        "kimi-k2.6":            { "name": "kimi-k2.6",            "limit": { "context": 256000, "output": 4096 }, "modalities": { "input": ["text", "image"], "output": ["text"] } },
        "kimi-k2.5":            { "name": "kimi-k2.5",            "limit": { "context": 256000, "output": 4096 } },
        "doubao-seed-2.0-code": { "name": "doubao-seed-2.0-code", "limit": { "context": 256000, "output": 4096 }, "modalities": { "input": ["text", "image"], "output": ["text"] } },
        "doubao-seed-code":     { "name": "doubao-seed-code",     "limit": { "context": 256000, "output": 4096 }, "modalities": { "input": ["text", "image"], "output": ["text"] } },
        "deepseek-v3.2":        { "name": "deepseek-v3.2",        "limit": { "context": 128000, "output": 4096 } },
        "glm-5.1":              { "name": "glm-5.1",              "limit": { "context": 200000, "output": 4096 } },
        "minimax-latest":       { "name": "minimax-latest",       "limit": { "context": 200000, "output": 4096 } }
      }
    }
  }
}
OPENCODE_EOF

echo "==> [7/14] .claude/settings.kimi.json"
cat > .claude/settings.kimi.json <<'CLAUDE_KIMI_EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding",
    "ANTHROPIC_MODEL": "kimi-for-coding"
  }
}
CLAUDE_KIMI_EOF
# ANTHROPIC_AUTH_TOKEN is set by the .bashrc snippet that maps KIMI_API_KEY/ARK_API_KEY
# to the Anthropic SDK's expected env var. settings.json env values are NOT
# interpolated by Claude Code, so embedding "${KIMI_API_KEY}" would write that
# literal string as the auth token.

echo "==> [8/14] .claude/settings.volcengine.json"
cat > .claude/settings.volcengine.json <<'CLAUDE_VOLCANO_EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://ark.cn-beijing.volces.com/api/coding",
    "ANTHROPIC_MODEL": "ark-code-latest"
  }
}
CLAUDE_VOLCANO_EOF

echo "==> [9/14] skills/sql-helper/SKILL.md"
cat > skills/sql-helper/SKILL.md <<'SQLHELPER_SKILL_EOF'
---
name: sql-helper
description: >
  Lab Postgres helper. Use whenever the user asks to run SQL, inspect a
  schema, or load lab data into the local Postgres.

  Subcommands:
    init       — start Postgres, create the `dmdb` database, load lab data
    schema     — dump schema of the `dmdb` database
    query "Q"  — run SQL Q against `dmdb`, return rows
    explain "Q"— run EXPLAIN ANALYZE Q

  Usage: bash skills/sql-helper/helper.sh <subcommand> [args]
---
SQLHELPER_SKILL_EOF

echo "==> [10/14] skills/sql-helper/helper.sh"
cat > skills/sql-helper/helper.sh <<'SQLHELPER_SH_EOF'
#!/usr/bin/env bash
set -euo pipefail

DB_NAME="dmdb"
PG_USER="codespace"

ensure_pg_running() {
  if ! pg_isready -q 2>/dev/null; then
    sudo service postgresql start
    sleep 2
  fi
}

ensure_pg_role() {
  # postgresql feature creates only the `postgres` superuser. The OS user
  # `codespace` has no Postgres role until we create one.
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" \
    | grep -q 1 || sudo -u postgres psql -c "CREATE ROLE $PG_USER LOGIN SUPERUSER;"
}

cmd_init() {
  ensure_pg_running
  ensure_pg_role
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
    | grep -q 1 || sudo -u postgres createdb -O "$PG_USER" "$DB_NAME"
  if [ -d lab-data ]; then
    for f in lab-data/*.sql; do
      [ -f "$f" ] || continue
      echo "Loading $f..."
      psql -d "$DB_NAME" -f "$f"
    done
  fi
  echo "✓ DB ready. Connect: psql -d $DB_NAME"
}

cmd_schema()  { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "\d+"; }
cmd_query()   { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "$1"; }
cmd_explain() { ensure_pg_running; ensure_pg_role; psql -d "$DB_NAME" -c "EXPLAIN ANALYZE $1"; }

case "${1:-}" in
  init)    cmd_init ;;
  schema)  cmd_schema ;;
  query)   cmd_query "${2:?query required}" ;;
  explain) cmd_explain "${2:?query required}" ;;
  *)       echo "usage: helper.sh {init|schema|query|explain} [SQL]" >&2; exit 2 ;;
esac
SQLHELPER_SH_EOF
chmod +x skills/sql-helper/helper.sh

echo "==> [11/14] scripts/verify.sh"
cat > scripts/verify.sh <<'VERIFY_EOF'
#!/usr/bin/env bash
# Auto-detects which provider key is set and tests that one.
set -uo pipefail

PASS=0; FAIL=0
ok()   { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }

[ -f .env ] && { set -a; source .env; set +a; }

# --- Toolchain ---
# Pi has no `--version` flag in 0.70.x — just check it's on PATH.
command -v pi       >/dev/null 2>&1 && ok "Pi installed"                                              || fail "Pi missing — run: bash .devcontainer/setup.sh"
command -v opencode >/dev/null 2>&1 && ok "OpenCode installed ($(opencode --version 2>&1 | head -1))" || fail "OpenCode missing"
command -v claude   >/dev/null 2>&1 && ok "Claude Code installed ($(claude --version 2>&1 | head -1))" || fail "Claude Code missing"
command -v psql     >/dev/null 2>&1 && ok "Postgres client present"                                   || fail "psql missing"

# --- Provider checks (only for keys that are set) ---
TESTED_ANY=0
if [ -n "${KIMI_API_KEY:-}" ]; then
  TESTED_ANY=1
  HTTP=$(curl -sS -o /tmp/kimi.json -w "%{http_code}" -X POST \
    https://api.kimi.com/coding/v1/messages \
    -H "x-api-key: $KIMI_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d '{"model":"kimi-for-coding","max_tokens":5,"messages":[{"role":"user","content":"reply with the single word OK"}]}')
  if [ "$HTTP" = "200" ] && grep -q "OK" /tmp/kimi.json; then
    ok "Kimi For Coding key works (kimi-for-coding responded)"
  else
    fail "Kimi For Coding HTTP $HTTP — see /tmp/kimi.json"
  fi
fi

if [ -n "${ARK_API_KEY:-}" ]; then
  TESTED_ANY=1
  HTTP=$(curl -sS -o /tmp/ark.json -w "%{http_code}" -X POST \
    https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions \
    -H "Authorization: Bearer $ARK_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"ark-code-latest","messages":[{"role":"user","content":"reply with the single word OK"}],"max_tokens":5}')
  if [ "$HTTP" = "200" ] && grep -q "OK" /tmp/ark.json; then
    ok "Volcengine Coding Plan key works (ark-code-latest responded)"
  else
    fail "Volcengine HTTP $HTTP — see /tmp/ark.json (check subscription is active)"
  fi
fi

if [ "$TESTED_ANY" = "0" ]; then
  fail "Neither KIMI_API_KEY nor ARK_API_KEY is set in .env (open a fresh terminal after pasting)"
fi

# --- End-to-end smoke test (catches misconfigured agent → provider wiring) ---
if [ "$TESTED_ANY" = "1" ] && command -v opencode >/dev/null 2>&1; then
  if timeout 30 opencode run "say OK in one word" 2>/tmp/opencode.err | head -3 | grep -qi "ok"; then
    ok "OpenCode end-to-end works"
  else
    fail "OpenCode invocation failed (see /tmp/opencode.err)"
  fi
fi

if [ "$TESTED_ANY" = "1" ] && command -v claude >/dev/null 2>&1 && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  if timeout 30 claude -p "say OK in one word" 2>/tmp/claude.err | head -3 | grep -qi "ok"; then
    ok "Claude Code end-to-end works"
  else
    fail "Claude Code invocation failed (see /tmp/claude.err) — did you open a fresh terminal after pasting .env?"
  fi
fi

echo ""
echo "$PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
VERIFY_EOF
chmod +x scripts/verify.sh

echo "==> [12/14] .env.example"
cat > .env.example <<'ENV_EXAMPLE_EOF'
# DMDB Codespace — paste at least ONE provider key.

# 1. Kimi For Coding (sk-kimi-...) — Anthropic-compat to https://api.kimi.com/coding
#    Use this for the initial test (instructor's existing key).
KIMI_API_KEY=

# 2. Volcengine Ark Coding Plan — for the production student flow.
#    Subscribe: https://www.volcengine.com/experience/ark
#    Get key:   https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey
ARK_API_KEY=

ENV_EXAMPLE_EOF

echo "==> [13/14] .gitignore"
cat > .gitignore <<'GITIGNORE_EOF'
.env
node_modules/
__pycache__/
*.pyc
.dmdb-pg/
*.sqlite
*.log
/tmp/
GITIGNORE_EOF

echo "==> [14/14] README.md"
cat > README.md <<'README_EOF'
# DMDB 2026 Spring — Codespace Lab Environment

> Ships dual provider: Kimi For Coding (test) + Volcengine Ark Coding Plan (production).
> Default is Kimi. Switch to Volcengine before semester start.

## Before week 9 — install VS Code Desktop (one-time, ~10 min)

Do this on your laptop **before** the first lab. Don't burn class time on a download.

1. Install **VS Code Desktop**: <https://code.visualstudio.com>
   - macOS / Windows / Linux all supported. ~100 MB.
   - In China, download direct from code.visualstudio.com (Microsoft CDN works);
     if slow, try the "System Installer" link or wait off-peak.
2. Open VS Code → click the **Extensions** icon (left sidebar, four squares)
   → search **"GitHub Codespaces"** → Install the official extension by GitHub.
3. ⌘⇧P (Ctrl+Shift+P on Win/Linux) → type `Codespaces: Sign In` → browser
   opens → log in with your GitHub account → return to VS Code.

Done. Your laptop is now ready for every lab in weeks 9–16.

## First-launch checklist (~5 min)

### 1. Connect to your Codespace
In VS Code Desktop:
- ⌘⇧P → `Codespaces: Create New Codespace…` (first time)
  → pick this repo → branch `main` → machine `2-core`.
- Or, if you already have one: `Codespaces: Connect to Codespace…` → pick from list.

VS Code reattaches to the cloud VM. Wait ~60 s for `setup.sh` to install
Pi, OpenCode, Claude Code, uv, and pre-build the lab venv. Banner prints
`DMDB Codespace ready.` when done.

### 2. Paste your API key
- Click `.env` in the file tree (left side)
- Paste `KIMI_API_KEY=sk-kimi-...` (or `ARK_API_KEY=<volcengine-key>`)
- Save: ⌘S / Ctrl+S

### 3. Open a NEW terminal tab
**Terminal menu → New Terminal** (or `` Ctrl+Shift+` ``). The new shell auto-loads
`.env` via `~/.bashrc` and exports `ANTHROPIC_AUTH_TOKEN` for Claude Code. The
old terminal still has empty env vars — don't reuse it.

### 4. Verify
```bash
bash scripts/verify.sh
```
Expect: ✓ Pi, ✓ OpenCode, ✓ Claude Code, ✓ Postgres, ✓ provider key, ✓ end-to-end.

### 5. Try each agent
```bash
opencode run "Write a SQL query for top 5 students by GPA from students(id,name,gpa)"
pi       "Same question."
claude   "Same question."
```

## Switching providers

**OpenCode**: type `/models` in TUI

**Pi**: `Ctrl+L` cycles, OR edit `~/.pi/agent/settings.json` `defaultProvider` to `volcengine-coding-plan`

**Claude Code**: copy the right template, then open a fresh terminal so bashrc re-exports the right token:
```bash
cp .claude/settings.kimi.json       ~/.claude/settings.json   # Kimi
cp .claude/settings.volcengine.json ~/.claude/settings.json   # Volcengine
```

## If something breaks

- **Codespace stuck on "Setting up remote connection..."** → ⌘⇧P → `Codespaces: Stop Current Codespace`, wait 30s, then `Connect to Codespace` again.
- **`verify.sh` fails on the provider key** → did you open a NEW terminal after pasting `.env`? The old one has empty env vars. Close it, open a fresh one, retry.
- **Browser fallback** (only if VS Code Desktop is unavailable on a borrowed machine): on github.com, repo → Code → Codespaces → resume your existing one. The browser path works but is more sensitive to network drops; prefer Desktop.

## Help
- Volcengine docs: <https://www.volcengine.com/docs/82379/1925114?lang=zh>
- OpenCode docs: <https://opencode.ai/docs>
- Pi docs: <https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent>
README_EOF

echo ""
echo "===================================================="
echo "  Scaffold complete. 14 files created."
echo ""
echo "  Next steps:"
echo "    1. cp .env.example .env"
echo "    2. Click .env in file tree → paste KIMI_API_KEY=sk-kimi-..."
echo "    3. git add . && git commit -m 'scaffold' && git push"
echo "    4. F1 / Cmd+Shift+P → 'Codespaces: Rebuild Container'"
echo "    5. (after rebuild) open a NEW terminal → bash scripts/verify.sh"
echo "===================================================="
