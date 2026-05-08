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
