# claudr

**Run Claude Code with any model on OpenRouter.**

Claude Code is one of the best terminal coding assistants out there — but
out of the box it only talks to Anthropic. claudr is a tiny launcher that
points it at [OpenRouter](https://openrouter.ai) instead, so you can use
the exact same `claude` CLI (slash commands, MCP, `/resume`, all of it)
with **any** model the platform offers: Kimi K2, Sonnet 4.6, Opus 4.7,
DeepSeek V4, GPT-5, Gemini 2.5 Pro, Grok, Qwen, GLM — anything.

You install it once. You give it an OpenRouter key. You pick a model from
a fuzzy-searchable list of OpenRouter's live programming leaderboard.
That's the whole product.

```
claudr
```

Pay-as-you-go billing (and OpenRouter ships **free model variants** good
enough for full Claude Code sessions — see [below](#free-models-that-handle-the-claude-code-agentic-flow)).
No proxy server, no per-model setup, no config files to hand-edit.

---

## Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/olindkri/claudr/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
$d="$env:TEMP\orc-src"; if(Test-Path $d){rm -r -fo $d}; git clone --depth 1 https://github.com/olindkri/claudr $d; & "$d\install.ps1"; rm -r -fo $d
```

Then open a **new** terminal and run:

```
claudr
```

First launch walks you through:

1. **OpenRouter API key** — required.
   - Sign up: [openrouter.ai](https://openrouter.ai/sign-up)
   - Create a key: [openrouter.ai/keys](https://openrouter.ai/keys)
   - Pay-as-you-go (preload credits) — most coding-capable models are
     a few cents per million tokens; some are **free**, see below.
2. **Tavily API key** — optional, gives the model web search.
   - Sign up: [app.tavily.com](https://app.tavily.com) (no credit card)
   - **1000 queries/month free**, no per-second rate cap. Press Enter
     to skip if you don't want web search.
3. **Three picks** — your default model, mid-tier subagent model, and
   fast/background model. Change any time with `claudr --tiers`.

### Free models that handle the Claude Code agentic flow

OpenRouter offers free variants of many models — usable for full
Claude Code sessions, tool use included. Look for the **`:free`** suffix
in the picker (or fuzzy-search for it). As of writing, these handle
Anthropic's tool schema well enough for real agentic work:

- `deepseek/deepseek-v4-flash:free` — fast, surprisingly good at tool use
- `z-ai/glm-5.1:free` — solid all-rounder
- `qwen/qwen3-coder-plus:free` — coding-tuned
- `meta-llama/llama-4-scout:free` — long context, decent reasoning

Free tiers are rate-limited and may queue under load — for hobby use it's
fine; for daily heavy use, add a few dollars of OpenRouter credit and
pick a paid model that fits your budget.

Re-run the install command later to update. Keys are saved to
`~/.config/claudr/` on macOS/Linux and `%USERPROFILE%\.claudr\` on Windows.

> **Cautious about `curl | bash`?** Inspect first:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/olindkri/claudr/main/install.sh -o install.sh
> less install.sh && bash install.sh
> ```
> Source is browsable at [github.com/olindkri/claudr](https://github.com/olindkri/claudr/blob/main/install.sh).

---

## Why bother?

Pointing Claude Code at OpenRouter is technically just an env-var change.
But to actually use it daily you also need to:

- Find the right model slug among OpenRouter's hundreds of entries
- Handle Claude Code's hardcoded 200K context cap on non-Anthropic models
  (which is wrong for Kimi's 256K, DeepSeek's 1M, etc.)
- Wire up web search since Anthropic's built-in `WebSearch` tool only
  works on their first-party endpoint
- Route subagents to the right tier (opus / sonnet / haiku model aliases)
  without each one running on your most expensive model
- Work around quirks like [empty `-p` results](https://github.com/anthropics/claude-code/issues/38805)
  when OpenRouter responses include `redacted_thinking` blocks

claudr does all of that in one launcher. No proxy server, no fork of
Claude Code, no maintenance — it just sets env vars and calls `claude`.

---

## Quick reference

> **Windows flag syntax**: examples below use bash style. PowerShell users
> swap to single-dash: `-Tiers`, `-Preset`, `-Ask`, `-Doctor`, `-Presets`,
> `-List`, `-Refresh`, `-Model`. Same semantics, idiomatic per shell.

```bash
claudr                          # launch with your saved tier config
claudr --tiers                  # re-pick the 3 tier models
claudr --tiers coding           # save tier picks as a named preset
claudr --preset coding          # launch with a named preset
claudr --presets                # list saved presets and exit
claudr -m kimi                  # override only the main model
claudr -p "summarize file.md"   # one-shot, returns just the text reply
claudr --ask "what is 2+2?"     # explicit non-interactive form
claudr --doctor                 # health-check CLI, key, fzf, slugs, caches
claudr --list -n 50             # print top 50 as a table, exit
claudr --view month             # ranking window: day | week | month | trending
claudr --refresh                # bypass 6h cache
claudr --list-all               # dump every OpenRouter model
claudr -- --resume              # forward flags to `claude`
```

---

## How it works

Claude Code honors three env vars:

- `ANTHROPIC_BASE_URL` — where to send requests
- `ANTHROPIC_AUTH_TOKEN` — bearer token sent on each request
- `ANTHROPIC_MODEL` — model slug

OpenRouter exposes an Anthropic-compatible endpoint at
`https://openrouter.ai/api`. Pointing `ANTHROPIC_BASE_URL` there (with your
OpenRouter key as the auth token) makes Claude Code talk to OpenRouter
natively — no proxy needed.

The picker scrapes the rankings page's RSC payload, sums tokens per
permaslug (same ordering the site shows), maps OpenRouter's dated permaslug
(e.g. `moonshotai/kimi-k2.6-20260420`) to the canonical model id
(`moonshotai/kimi-k2.6`) using `/api/v1/models`, and pulls description,
context length, and price from the catalog. Both feeds are cached for 6h.
When the rankings page can't be scraped (e.g. it switches to client-side
loading), the picker falls back to a curated catalog so it's never empty.

## Prerequisites

- `claude` CLI: `npm i -g @anthropic-ai/claude-code`
- OpenRouter API key from https://openrouter.ai/keys
- `fzf` (recommended — enables the arrow-key picker; installer offers to
  install it via `brew` / `winget` / `scoop`)
- macOS / Linux: `python3` + `curl` (preinstalled on macOS)
- Windows: PowerShell 5.1+ (preinstalled)

---

## Three-tier model setup

Claude Code uses three model aliases — `opus`, `sonnet`, `haiku` — and routes
subagents and background tasks (compaction, title generation, file searches)
through whichever one their frontmatter declares. claudr maps each alias to
an OpenRouter slug of your choice via env vars
([`ANTHROPIC_DEFAULT_OPUS_MODEL`](https://code.claude.com/docs/en/model-config),
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`).

The **opus** tier is also the **main** model — what your session runs on by
default. The other two only activate when Claude Code dispatches a subagent
at that tier, or when you type `/model sonnet` or `/model haiku` mid-session.

### First launch: the setup wizard

The first time you run `claudr`, it opens a 3-pick wizard in the fzf picker:

```
╭─ claudr · 1/3 · OPUS (main) ─────────────────────────────────────────╮
│   ↑↓ navigate   ⏎ confirm   ⌃A change key   esc cancel               │
│   search ›                                                           │
│ ▶ #1   qwen/qwen3.7-max          1M ctx     $4.00 / $20.00 /M        │
│   #2   anthropic/claude-opus-4.7 1M ctx     $5.00 / $25.00 /M        │
│   ...                                                                │
╰──────────────────────────────────────────────────────────────────────╯
```

1. **OPUS (main)**: your default model. Every session runs on this unless
   Claude Code routes elsewhere.
2. **SONNET**: mid-tier subagent model. Used when an agent file says
   `model: sonnet` or `/model sonnet` is typed.
3. **HAIKU**: fast/background model. Used for compaction, title generation,
   file searches, and `model: haiku` subagents.

Picks are saved to **`~/.config/claudr/tiers.conf`** and reused on every
subsequent launch — no more pickers, instant start.

### Re-running the wizard

```bash
claudr --tiers
```

Reopens the same 3-pick flow and overwrites your saved config. Pressing
**Esc** on any screen cancels without changing anything.

### Manual editing

You can edit `~/.config/claudr/tiers.conf` directly:

```
# claudr tier config — what each Claude Code model alias resolves to.
OPUS=qwen/qwen3.7-max
SONNET=moonshotai/kimi-k2.6
HAIKU=deepseek/deepseek-v4-flash
```

Any OpenRouter slug works. If you typo a slug, claudr warns you on next
launch and points to `claudr --tiers` to fix it.

### Mid-session switching

Inside Claude Code:

- `/model opus` → switches to your OPUS slug
- `/model sonnet` → switches to your SONNET slug
- `/model haiku` → switches to your HAIKU slug
- `/model` (no arg) → opens Claude Code's own picker

Subagents declared with `model: opus|sonnet|haiku` in their frontmatter
get routed automatically.

### Per-launch overrides

| Override                                | Effect                                          |
|-----------------------------------------|-------------------------------------------------|
| `CLAUDR_OPUS_MODEL=<slug> claudr`       | Override opus tier for this launch only         |
| `CLAUDR_SONNET_MODEL=<slug> claudr`     | Override sonnet tier for this launch only       |
| `CLAUDR_HAIKU_MODEL=<slug> claudr`      | Override haiku tier for this launch only        |
| `claudr -m <slug>`                      | Override main model only; tiers stay as configured |
| `claudr --preset <name>`                | Use a named preset instead of the default tier config |

Example: run with saved config but swap opus to GPT-5 just for this session:

```bash
CLAUDR_OPUS_MODEL=openai/gpt-5 claudr
```

---

## Named presets

If you flip between workflows — cheap models for boilerplate, top-tier for
hard debugging — save each one as a named preset:

```bash
claudr --tiers cheap            # wizard → saves to ~/.config/claudr/presets/cheap.conf
claudr --tiers power            # different picks → saves as power
claudr --presets                # list all presets
claudr --preset cheap           # launch with the 'cheap' preset
```

Bare `claudr` still uses the default `tiers.conf`. Each preset is a small
shell-source file you can edit by hand:

```
# ~/.config/claudr/presets/coding.conf
OPUS=anthropic/claude-opus-4.7
SONNET=anthropic/claude-sonnet-4.6
HAIKU=anthropic/claude-haiku-4.5
```

The active preset name shows in the launch banner and the statusline.

---

## Non-interactive use (`-p` / `--ask`)

`claudr -p "your prompt"` works like `claude -p` and returns just the text
reply on stdout — useful for scripts, pipelines, and agent frameworks:

```bash
claudr -p "list the TODO comments in src/" | tee todos.txt
echo "describe this image" | claudr --ask "$(cat -)"
```

Under the hood, claudr transparently routes `-p` through a stream-json
parser to work around upstream
[claude-code#38805](https://github.com/anthropics/claude-code/issues/38805)
(empty `result` field when OpenRouter responses include trailing
`redacted_thinking` blocks). You keep the `-p` ergonomics, you get the
actual text out.

If you explicitly pass `--output-format json` or `--output-format stream-json`,
claudr passes through to `claude` untouched — you're presumably parsing the
structured output yourself.

The launch banner auto-suppresses in print mode. Force-show with
`CLAUDR_BANNER=1`. Opt out of the auto-routing with `CLAUDR_RAW_PRINT=1`.

---

## Doctor

```bash
claudr --doctor
```

Health-checks the `claude` CLI, `fzf`, `python3`, your OpenRouter key
(live ping to `/auth/key`), Tavily key, default tier config, tier slug
validity against the OpenRouter catalog, saved presets, and model-cache
freshness. Color-coded ✓ / ! / ✗ with a summary. **Run this first when
anything feels off.**

---

## Statusline

claudr writes a small statusline script and per-session settings file,
then passes them to `claude --settings`. Claude Code's footer then shows
the model, context window, active preset, and working directory:

```
claudr · qwen/qwen3.7-max · ctx 1M · [coding] · myproject
```

Disable with `CLAUDR_STATUSLINE=0` if you have your own statusline config.

---

## OpenRouter attribution

Every request claudr makes is tagged with `HTTP-Referer:
github.com/olindkri/claudr` and `X-Title: claudr` (via
`ANTHROPIC_CUSTOM_HEADERS`), so your
[OpenRouter activity dashboard](https://openrouter.ai/activity) groups
claudr usage under one label. Override with `CLAUDR_REFERER` /
`CLAUDR_TITLE`.

---

## Web search (Tavily, scoped to this launcher)

Claude Code's built-in `WebSearch` tool runs server-side on Anthropic's
infrastructure, so it doesn't work on OpenRouter models. claudr injects
**Tavily as an MCP server only for claudr launches** — passed via
`--mcp-config`, never registered globally. Other `claude` invocations on
the same machine (Ollama's launcher, plain `claude`, etc.) see no Tavily
and use whatever search they had configured.

Free tier is **1000 queries/month** with no per-second rate cap.

- **Sign up:** https://app.tavily.com (30 sec, no card required)
- **Skip:** press Enter at the prompt — search is just unavailable until you set a key
- **Rotate:** edit or delete `~/.claudr/tavily-key` (`%USERPROFILE%\.claudr\tavily-key` on Windows) and re-launch

Under the hood: the key is saved per-platform; on every launch claudr
writes an `mcp.json` pointing at Tavily's hosted remote MCP and passes
that file via `claude --mcp-config`. It also passes `--disallowedTools
WebSearch` so the model can't pick the no-op Anthropic tool over Tavily.

---

## Context window on non-Anthropic models

Claude Code hardcodes a 200K window for unknown / non-Anthropic models —
even if the model actually supports 1M (DeepSeek V4 Pro) or 256K (Kimi K2.6).
The env var `CLAUDE_CODE_MAX_CONTEXT_TOKENS` only takes effect when
`DISABLE_COMPACT=1` is *also* set. There's no way to get both auto-compaction
and the true window.

claudr picks the **real window** by default:

- Sets `DISABLE_COMPACT=1` and `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<catalog value>`
- DeepSeek V4 Pro shows as 1,000,000 tokens in `/context`, Kimi K2.6 as 256,000
- Auto-compaction is off — run `/compact` yourself when you want to summarize

If you'd rather have auto-compaction back (at the cost of a 200K cap):

```bash
CLAUDR_AUTOCOMPACT=1 claudr
```

That sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` and skips `DISABLE_COMPACT`,
so Claude Code auto-compacts at 75% of its 200K assumption.

---

## All configurable options

| Setting                            | Default        | What it does                                                                |
|------------------------------------|----------------|-----------------------------------------------------------------------------|
| `OPENROUTER_RANK_VIEW` env var     | `week`         | Leaderboard window for the picker (`day` / `week` / `month` / `trending`)   |
| `OPENROUTER_TOP_N` env var         | `25`           | How many ranked models appear above the full catalog in the picker          |
| `--view <window>`                  | —              | Same as `OPENROUTER_RANK_VIEW`, per-launch                                  |
| `-n <N>` / `--top <N>`             | —              | Same as `OPENROUTER_TOP_N`, per-launch                                      |
| `--refresh`                        | —              | Bypass the 6h leaderboard/catalog cache for this launch                     |
| `CLAUDR_AUTOCOMPACT=1` env var     | off            | Re-enable Claude Code's auto-compaction (pins window at 200K)               |
| `CLAUDR_SAFE=1` env var            | off            | Don't pass `--dangerously-skip-permissions` to claude                       |
| `CLAUDR_ALLOW_WEBSEARCH=1` env var | off            | Don't pass `--disallowedTools WebSearch` (lets the no-op tool show up)      |
| `TAVILY_API_KEY` env var           | —              | Use this Tavily key for the web-search MCP instead of the saved file       |
| `CLAUDR_STATUSLINE=0` env var      | on             | Disable claudr's statusline (use your own `claude` settings.json instead)  |
| `CLAUDR_BANNER=1` env var          | auto           | Force-show the launch banner (normally hidden in `-p` / `--ask` modes)     |
| `CLAUDR_RAW_PRINT=1` env var       | off            | Disable `-p` auto-routing; pass `claude -p` through raw                    |
| `CLAUDR_REFERER` / `CLAUDR_TITLE`  | claudr/github  | Override OpenRouter attribution headers (`HTTP-Referer` / `X-Title`)       |
| `CLAUDR_THINKING=1` env var        | off            | Keep extended thinking enabled in print mode (default: disabled for `-p`)  |

### Built-in model aliases

For `-m` and inside the wizard: `kimi`, `kimi-thinking`, `sonnet`, `opus`,
`haiku`, `deepseek`, `deepseek-flash`, `glm`, `qwen`, `qwen-coder`, `gemma`,
`gemini`, `minimax`, `grok`, `gpt`. Anything else is passed through as a
literal OpenRouter model slug.

### In the picker / wizard

- **↑↓** to move, **Enter** to confirm, **Esc** to cancel
- Type to fuzzy-filter the list
- **Ctrl+A** to change your OpenRouter API key without leaving the picker

---

## Troubleshooting

Start with `claudr --doctor`.

| Symptom                                          | Try                                                    |
|--------------------------------------------------|--------------------------------------------------------|
| Picker empty / leaderboard not loading           | `claudr --refresh` (bypasses the 6h cache)             |
| Wrong model slug saved                           | `claudr --tiers` to re-pick, or edit `~/.config/claudr/tiers.conf` |
| Want to swap your OpenRouter key                 | Press **Ctrl+A** inside the picker, or delete `~/.config/claudr/key` |
| Web search not working                           | Set `TAVILY_API_KEY` or write the key to `~/.config/claudr/tavily-key` |
| `claudr -p "..."` returns empty in older versions | Update — claudr auto-routes around [claude-code#38805](https://github.com/anthropics/claude-code/issues/38805); set `CLAUDR_RAW_PRINT=1` to opt out |
| Statusline clashes with your own                 | `CLAUDR_STATUSLINE=0 claudr`                           |
| `unknown option: --gutter` (or similar fzf error)| Your fzf is too old or distro-patched; claudr probes per-flag, so just update to fzf 0.42+ |

---

## Uninstall

**macOS / Linux:**

```bash
rm -f "$(command -v claudr)" ~/.config/claudr/key
# if you cloned to ~/.claudr:
rm -rf ~/.claudr
```

**Windows:**

```powershell
& "$env:LOCALAPPDATA\Programs\claudr\install.ps1" -Uninstall
```

---

## Caveats

- Tool-use / agentic features depend on the chosen model implementing the
  Anthropic tool schema correctly. Anthropic's own models (Sonnet/Opus/Haiku
  via OpenRouter), Kimi K2.6, GLM 5/5.1, DeepSeek V4, and Qwen3 Coder Plus
  work well; some smaller open models do not.
- Anthropic's prompt caching and 1M-context features only apply on
  Anthropic's first-party endpoint, not via OpenRouter.
- The leaderboard reflects **all** OpenRouter programming traffic — popularity
  ≠ quality. Top entries skew toward cheap/fast models (Gemini Flash, GPT-4o
  mini). Use `--view month` for a steadier signal, or just type a slug.
- Pricing shown is USD per million tokens for both input and output. See
  https://openrouter.ai/models for the full sheet.
