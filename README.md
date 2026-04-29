# Claude Code over GitHub Copilot

Use the [Claude Code](https://claude.com/claude-code) harness with models served by your **GitHub Copilot** subscription, so company data stays inside an already-approved LLM provider instead of going to a personal Anthropic account.

Anthropic officially documents [LiteLLM as an LLM gateway](https://code.claude.com/docs/en/llm-gateway) for Claude Code. This repo is a Windows-friendly wrapper around that pattern, with the GitHub Copilot model IDs pre-mapped.

## How it works

```
Claude Code  --(Anthropic /v1/messages)-->  LiteLLM proxy (localhost:4444)  --(OpenAI /chat/completions + Copilot OAuth)-->  api.githubcopilot.com
```

Claude Code thinks it's talking to Anthropic. LiteLLM translates each request to the OpenAI-shape that Copilot's backend expects, and injects the GitHub Copilot OAuth + editor headers automatically.

## What works

- Plain chat
- Tool use (the load-bearing path for Claude Code's MCP servers, Bash, Edit, etc.)
- Streaming
- Vision (when supported by the chosen model)
- Extended thinking / `reasoning_effort` (Claude 4 family — gated by quota, see below)

## What doesn't

- **Anthropic prompt caching.** `cache_control` breakpoints don't survive translation to Copilot's API. Long system prompts get re-tokenized every turn — slower, and on metered tiers, more expensive.
- **1M context on Opus 4.7.** Copilot exposes Anthropic models at 200K context.
- **Native Anthropic features** like citations, computer-use, message-batches API.

## Premium-model quota (read this before installing)

GitHub Copilot splits its model catalog into two tiers:

| Tier | Models | Cost on a typical Business / Enterprise plan |
|---|---|---|
| **Included** | `gpt-4.1`, `gpt-4o`, `gpt-4o-mini`, `gpt-5-mini`, etc. | Unlimited |
| **Premium** | All Claude models (Opus / Sonnet / Haiku, every version), full `gpt-5`, Gemini, Grok | Burns "premium requests" from a per-user monthly bucket |

If you call a premium model without quota, the API returns `HTTP 402 You have no quota`. Have your Copilot admin allocate premium-request quota to your account before expecting Claude to work — otherwise you'll be stuck on the included GPT models.

The repo ships with `gpt-5-mini` as the default to make first-run usable on a base subscription. Flip it to `claude-opus-4-7` once your admin grants premium quota.

## Setup (Windows / Git Bash)

Prerequisites:
- Python 3.12 (3.14 currently breaks `orjson` wheel install). `winget install Python.Python.3.12` if missing.
- Node.js + npm (only if you need to install Claude Code itself: `npm i -g @anthropic-ai/claude-code`).

```bash
git clone <this repo url>
cd claude-code-over-github-copilot
./run.sh setup           # venv, deps, .env keys
./run.sh start           # foreground; first run prompts a GitHub device-code OAuth
```

In a second terminal:

```bash
./run.sh test            # 5-step smoke test (chat, /v1/messages, tool use, streaming)
./run.sh claude-enable   # patches ~/.claude/settings.json (auto-backs it up)
./run.sh claude-status   # confirm 'Using local proxy' + 'Proxy: RUNNING'
```

Then run `claude` in any project directory.

## Setup (macOS / Linux)

The upstream `Makefile` (`make setup` / `make start` / `make claude-enable`) is the supported path. The `run.sh` shipped here is the Windows equivalent.

## Switching models

The default is `claude-opus-4-7` for the main model and `claude-haiku-4-5` for the small/fast model (used by Claude Code for cheap operations like summarizing tool output). Both are **premium** on Copilot — see the quota section above.

### Pre-configured models

The proxy ships with these Claude Code → Copilot mappings:

| Claude Code model name | Copilot model | Tier |
|---|---|---|
| `claude-opus-4-7` | `claude-opus-4.7` | premium |
| `claude-opus-4-6` | `claude-opus-4.6` | premium |
| `claude-opus-4-5` | `claude-opus-4.5` | premium |
| `claude-sonnet-4-6` | `claude-sonnet-4.6` | premium |
| `claude-sonnet-4-5` | `claude-sonnet-4.5` | premium |
| `claude-haiku-4-5` | `claude-haiku-4.5` | premium |
| `gpt-5` | `gpt-5.4` | premium |
| `gpt-5-mini` | `gpt-5-mini` | included |
| `gpt-4.1` | `gpt-4.1` | included |

Client names use Anthropic's `dash` convention; they're translated to Copilot's `dot` form on the wire, since that's the actual ID Copilot's API expects.

### Changing the default

Edit the `env` dict in [scripts/claude_enable.py](scripts/claude_enable.py) — set `ANTHROPIC_MODEL` (main) and `ANTHROPIC_SMALL_FAST_MODEL` (small/fast) to any of the names from the table. Then:

```bash
./run.sh claude-enable
```

Common combinations:

- **Best Claude experience (premium quota required)** — `claude-opus-4-7` + `claude-haiku-4-5` (default)
- **All-included path (no premium quota)** — `gpt-5-mini` + `gpt-4.1`
- **Cheaper Claude (premium quota required)** — `claude-sonnet-4-6` + `claude-haiku-4-5`

### Listing models your account can actually call

The model list above is what the proxy *exposes*. Your Copilot account may not have policy access to all of them. Run:

```bash
./list-copilot-models.sh --enabled-only
```

…to dump the live model list straight from `api.githubcopilot.com/models`. That's the source of truth for what your specific account can use.

### Adding a new model

If a model exists in your Copilot tenant but not in [copilot-config.yaml](copilot-config.yaml), add it:

```yaml
- model_name: my-new-model
  litellm_params:
    model: github_copilot/my-new-model-id
```

Then restart the proxy (`./run.sh stop && ./run.sh start`) and reference `my-new-model` from `claude_enable.py`.

## Security notes

- **Pin LiteLLM** to `>=1.83.0`. Versions `1.82.7` and `1.82.8` were [compromised with credential-stealing malware](https://github.com/BerriAI/litellm/issues/24518). The `requirements.txt` here excludes them.
- **Localhost-only by default.** The proxy binds to `0.0.0.0:4444` for compatibility, but the LiteLLM master key in `.env` is what gates access. Keep `.env` out of git (it already is).
- **No data leaves your laptop except via the Copilot API.** Same surface as using Copilot in VS Code.

## Acknowledgements

Forked structure and Makefile from [kjetiljd/claude-code-over-github-copilot](https://github.com/kjetiljd/claude-code-over-github-copilot). Approach inspired by Anthropic's [LLM gateway docs](https://code.claude.com/docs/en/llm-gateway) and [this writeup](https://blog.f12.no/wp/2025/09/22/using-claude-code-with-github-copilot-a-guide/).

## License

The [MIT License](LICENSE) covers contributions by Justin Pitt:

- `run.sh`, `smoke-test.sh`
- `README.md`, `LICENSE`
- `copilot-config.yaml` (rewritten)
- modifications to `scripts/claude_enable.py`, `requirements.txt`, `.gitignore`

The following files originate from the upstream repo [kjetiljd/claude-code-over-github-copilot](https://github.com/kjetiljd/claude-code-over-github-copilot) and retain their original status (the upstream is unlicensed at time of fork — verify before redistributing):

- `Makefile`, `generate_env.py`, `list-copilot-models.sh`, `scripts/claude_disable.py`
