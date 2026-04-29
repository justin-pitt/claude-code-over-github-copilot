#!/bin/bash
# Smoke-test the LiteLLM -> GitHub Copilot proxy across the surfaces
# Claude Code actually uses: chat, tool calling, streaming, and Anthropic-format /v1/messages.
#
# Run AFTER `make start` is up in another terminal.

set -e

if [[ ! -f .env ]]; then
  echo "ERR: .env missing — run 'make setup' first."
  exit 1
fi

KEY=$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2- | tr -d '"')
BASE="http://localhost:4444"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; echo "$2" | head -40; exit 1; }

echo "[1/5] Health check"
curl -fsS "$BASE/health/liveliness" >/dev/null && pass "proxy alive" || fail "proxy not alive"

echo "[2/5] Plain chat completion (OpenAI format) -> claude-opus-4-7"
RESP=$(curl -fsS -X POST "$BASE/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-opus-4-7","messages":[{"role":"user","content":"reply with just the word PONG"}]}')
echo "$RESP" | grep -qi 'PONG' && pass "chat works" || fail "chat failed" "$RESP"

echo "[3/5] Anthropic-format /v1/messages -> claude-opus-4-7 (this is the path Claude Code uses)"
RESP=$(curl -fsS -X POST "$BASE/v1/messages" \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-opus-4-7","max_tokens":64,"messages":[{"role":"user","content":"reply with just the word PONG"}]}')
echo "$RESP" | grep -qi 'PONG' && pass "/v1/messages works" || fail "/v1/messages failed" "$RESP"

echo "[4/5] Tool calling -> claude-opus-4-7"
RESP=$(curl -fsS -X POST "$BASE/v1/messages" \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"claude-opus-4-7",
    "max_tokens":256,
    "tools":[{"name":"get_weather","description":"Get current weather for a city","input_schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}],
    "messages":[{"role":"user","content":"What is the weather in Pittsburgh? Use the tool."}]
  }')
echo "$RESP" | grep -q '"type":"tool_use"' && pass "tool_use block returned" || fail "no tool_use block" "$RESP"

echo "[5/5] Streaming -> claude-haiku-4-5"
COUNT=$(curl -fsSN -X POST "$BASE/v1/messages" \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":32,"stream":true,"messages":[{"role":"user","content":"count from 1 to 5"}]}' \
  | grep -c '^data:' || true)
[[ "$COUNT" -gt 2 ]] && pass "streamed $COUNT chunks" || fail "streaming broken (chunks=$COUNT)"

echo
echo "All smoke tests passed. Safe to 'make claude-enable' and run 'claude' in a project."
