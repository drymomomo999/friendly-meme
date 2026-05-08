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
