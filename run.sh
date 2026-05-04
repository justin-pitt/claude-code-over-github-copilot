#!/bin/bash
# Windows-friendly replacement for the Makefile.
# Run from Git Bash on Windows.
#
# Usage:
#   ./run.sh setup           - venv + deps + .env keys
#   ./run.sh start           - launch LiteLLM proxy on :4444 (foreground)
#   ./run.sh stop            - kill litellm
#   ./run.sh test            - smoke-test the proxy (requires start running)
#   ./run.sh claude-enable   - patch ~/.claude/settings.json -> use proxy
#   ./run.sh claude-disable  - restore ~/.claude/settings.json from latest backup
#   ./run.sh claude-status   - show current Claude Code config

set -e

cd "$(dirname "$0")"

# This script is Windows-only (Git Bash). On macOS/Linux, use the Makefile.
case "$OSTYPE" in
  msys*|cygwin*|win32) ;;
  *)
    echo "ERR: run.sh is the Windows (Git Bash) path. On macOS/Linux, use the Makefile:"
    echo "       make setup"
    echo "       make start"
    echo "       make claude-enable"
    echo "     See README.md > 'Setup (macOS / Linux)'."
    exit 1
    ;;
esac

# Windows venv paths differ from Linux
VENV_BIN="venv/Scripts"
[[ -d "venv/bin" ]] && VENV_BIN="venv/bin"  # fallback if someone made a Linux venv

cmd_setup() {
  echo "[setup] creating venv + installing deps..."
  # Use Python 3.12 — orjson (LiteLLM dep) has no Windows wheels for 3.14 yet,
  # and source-building it requires a working MSVC toolchain.
  if py -3.12 --version >/dev/null 2>&1; then
    py -3.12 -m venv venv
  else
    echo "ERR: Python 3.12 not found. Install with: winget install Python.Python.3.12"
    exit 1
  fi
  ./$VENV_BIN/python -m pip install --upgrade pip
  ./$VENV_BIN/pip install -r requirements.txt
  if [[ ! -f .env ]]; then
    echo "[setup] generating .env keys..."
    python generate_env.py
  else
    echo "[setup] .env already present, leaving it alone"
  fi
  echo "[setup] done."
}

cmd_start() {
  if [[ ! -f .env ]]; then echo "ERR: run setup first"; exit 1; fi
  echo "[start] launching LiteLLM on http://localhost:4444 ..."
  echo "[start] first run will prompt GitHub device-code OAuth — paste the code at the URL shown."
  set -a; source .env; set +a
  ./$VENV_BIN/litellm --config copilot-config.yaml --port 4444
}

cmd_stop() {
  # Windows-friendly: find litellm processes via tasklist + taskkill
  taskkill //F //IM litellm.exe 2>/dev/null || true
  # Fallback: kill any python running litellm
  for pid in $(tasklist //FI "IMAGENAME eq python.exe" //FO CSV //NH 2>/dev/null \
                | awk -F'","' '/litellm/ {gsub(/"/,""); print $2}'); do
    taskkill //F //PID "$pid" 2>/dev/null || true
  done
  echo "[stop] killed any running litellm processes"
}

cmd_test() {
  if [[ ! -f .env ]]; then echo "ERR: run setup first"; exit 1; fi
  bash smoke-test.sh
}

cmd_claude_enable() {
  if [[ ! -f .env ]]; then echo "ERR: run setup first"; exit 1; fi
  KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2- | tr -d '"')
  if [[ -z "$KEY" ]]; then echo "ERR: LITELLM_MASTER_KEY missing from .env"; exit 1; fi
  SETTINGS="$HOME/.claude/settings.json"
  if [[ -f "$SETTINGS" ]]; then
    BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    echo "[claude-enable] backed up existing settings -> $BACKUP"
  fi
  python scripts/claude_enable.py "$KEY"
}

cmd_claude_disable() {
  SETTINGS="$HOME/.claude/settings.json"
  LATEST=$(ls -t "$SETTINGS".backup.* 2>/dev/null | head -1 || true)
  if [[ -n "$LATEST" ]]; then
    cp "$LATEST" "$SETTINGS"
    echo "[claude-disable] restored from $LATEST"
  else
    python scripts/claude_disable.py
    echo "[claude-disable] reset via claude_disable.py (no backup found)"
  fi
}

cmd_claude_status() {
  SETTINGS="$HOME/.claude/settings.json"
  if [[ ! -f "$SETTINGS" ]]; then
    echo "[status] no ~/.claude/settings.json — Claude Code is using defaults"
    return
  fi
  echo "[status] $SETTINGS:"
  python -m json.tool < "$SETTINGS" || cat "$SETTINGS"
  if grep -q "localhost:4444" "$SETTINGS"; then
    echo "[status] using LOCAL PROXY"
    if curl -sf http://localhost:4444/health/liveliness >/dev/null 2>&1; then
      echo "[status] proxy: RUNNING"
    else
      echo "[status] proxy: NOT RUNNING (run ./run.sh start in another terminal)"
    fi
  else
    echo "[status] using DEFAULT Anthropic servers"
  fi
}

case "${1:-help}" in
  setup)          cmd_setup ;;
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  test)           cmd_test ;;
  claude-enable)  cmd_claude_enable ;;
  claude-disable) cmd_claude_disable ;;
  claude-status)  cmd_claude_status ;;
  *)
    echo "usage: $0 {setup|start|stop|test|claude-enable|claude-disable|claude-status}"
    exit 1
    ;;
esac
