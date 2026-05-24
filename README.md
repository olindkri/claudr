# claudr

**The simplest way to run Claude Code with any OpenRouter model.**

One command, one key, one picker. Pick a model — Sonnet, Opus, Kimi K2,
DeepSeek V4, GPT-5, Gemini, Grok, anything on OpenRouter — and Claude Code
launches against it. No proxy, no config file, no per-model setup.

```
claudr
```

That's it. You get the full Claude Code experience (slash commands, MCP,
tool use, `/resume`, the lot) talking to whichever frontier model you
picked, billed through your OpenRouter account.

Without `-m`, the launcher pulls OpenRouter's **live programming leaderboard**
(https://openrouter.ai/rankings/programming) and opens a polished `fzf`
picker showing the top models with context, input/output price, and a
description from the OpenRouter catalog. Fuzzy-search the entire catalog
from the same prompt — no hardcoded list, always live.

### Why this exists

Claude Code's official setup only points at Anthropic. Pointing it at
OpenRouter unlocks every model on the platform with the same UX you
already know — but the env-var dance, model-slug guessing, context-window
quirks, and missing web search are tedious to wire up by hand. This
launcher does all of it in one binary you install with one curl command.

---

## One-line install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/olindkri/claudr/main/install.sh | bash
```

The installer auto-clones the repo to `~/.claudr`, symlinks
`claudr` into the first writable PATH dir (Homebrew's `bin`,
`/usr/local/bin`, or `~/.local/bin`), and offers to install `fzf`. Re-run
the same command later to update.

> **Don't trust `curl | bash` blind?** Inspect first:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/olindkri/claudr/main/install.sh -o install.sh
> less install.sh   # read it
> bash install.sh
> ```
> Source is also browsable at
> [github.com/olindkri/claudr/blob/main/install.sh](https://github.com/olindkri/claudr/blob/main/install.sh).

### Windows (PowerShell)

```powershell
$d="$env:TEMP\orc-src"; if(Test-Path $d){rm -r -fo $d}; git clone --depth 1 https://github.com/olindkri/claudr $d; & "$d\install.ps1"; rm -r -fo $d
```

Zip-only fallback (no `git` required):

```powershell
$z="$env:TEMP\orc.zip"; $d="$env:TEMP\orc-src"; if(Test-Path $d){rm -r -fo $d}; iwr -useb https://github.com/olindkri/claudr/archive/refs/heads/main.zip -OutFile $z; Expand-Archive -Force $z $d; & "$d\claudr-main\install.ps1"; rm -r -fo $d,$z
```

After install, open a **new** terminal and run `claudr`. First
launch prompts for an OpenRouter API key (https://openrouter.ai/keys) and
saves it to `~/.config/claudr/key` (Mac/Linux) or
`%USERPROFILE%\.claudr\key` (Windows).

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

## Prereqs

- `claude` CLI: `npm i -g @anthropic-ai/claude-code`
- OpenRouter API key from https://openrouter.ai/keys
- `fzf` (recommended — enables the arrow-key picker; installer offers to
  install it via `brew` / `winget` / `scoop`)
- macOS / Linux: `python3` + `curl` (preinstalled on macOS)
- Windows: PowerShell 5.1+ (preinstalled)

## Usage

```bash
claudr                          # launch with your saved tier config (first run: setup wizard)
claudr --tiers                  # re-pick the 3 tier models (opus/sonnet/haiku)
claudr --tiers coding           # save tier picks as a named preset
claudr --preset coding          # launch with a named preset
claudr --presets                # list saved presets and exit
claudr -m kimi                  # override only the main model for this launch
claudr -p "summarize file.md"   # one-shot print mode (returns just the text)
claudr --ask "what is 2+2?"     # explicit non-interactive form
claudr --doctor                 # health-check CLI, key, fzf, tier slugs, caches
claudr --list -n 50             # print top 50 as a table, exit
claudr --view month             # ranking window: day | week | month | trending
claudr --refresh                # bypass 6h cache
claudr --list-all               # dump every OpenRouter model
claudr -- --resume              # forward flags to `claude`
```

### Three-tier model setup

Claude Code uses three model aliases — `opus`, `sonnet`, `haiku` — and routes
subagents and background tasks (compaction, title generation, file searches)
through whichever one their frontmatter declares. claudr maps each alias to
an OpenRouter slug of your choice via env vars
([`ANTHROPIC_DEFAULT_OPUS_MODEL`](https://code.claude.com/docs/en/model-config),
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`).

The **opus** tier is also the **main** model — what your session runs on by
default. The other two only activate when Claude Code dispatches a subagent
at that tier, or when you type `/model sonnet` or `/model haiku` mid-session.

#### First launch: the setup wizard

The first time you run `claudr`, it opens a 3-pick wizard in the fzf picker:

```
╭─ claudr · 1/3 · OPUS (main) ─────────────────────────────────────────╮
│   ↑↓ navigate   ⏎ confirm   ⌃A change key   esc cancel               │
│   search ›                                                            │
│ ▶ #1   qwen/qwen3.7-max          1M ctx     $4.00 / $20.00 /M        │
│   #2   anthropic/claude-opus-4.7 1M ctx     $5.00 / $25.00 /M        │
│   ...                                                                 │
╰───────────────────────────────────────────────────────────────────────╯
```

1. **Screen 1 of 3 — OPUS (main)**: pick your default model. This is what
   every session runs on unless Claude Code routes elsewhere.
2. **Screen 2 of 3 — SONNET**: pick your mid-tier subagent model. Used when
   an agent file says `model: sonnet` or `/model sonnet` is typed.
3. **Screen 3 of 3 — HAIKU**: pick your fast/background model. Used for
   compaction, title generation, file searches, and `model: haiku` subagents.

Picks are saved to **`~/.config/claudr/tiers.conf`** and reused on every
subsequent launch — no more pickers, instant start.

#### Re-running the wizard

```bash
claudr --tiers
```

Reopens the same 3-pick flow and overwrites your saved config. Use it
whenever you want to swap tiers around. Pressing **Esc** on any of the
three screens cancels without changing anything.

#### Manual editing

You can edit `~/.config/claudr/tiers.conf` directly with any text editor.
It's plain shell-source format:

```
# claudr tier config — what each Claude Code model alias resolves to.
OPUS=qwen/qwen3.7-max
SONNET=moonshotai/kimi-k2.6
HAIKU=deepseek/deepseek-v4-flash
```

Any OpenRouter slug works. If you typo a slug, claudr warns you on next
launch and points to `claudr --tiers` to fix it.

#### Mid-session switching

Inside Claude Code:

- `/model opus` → switches to your OPUS slug
- `/model sonnet` → switches to your SONNET slug
- `/model haiku` → switches to your HAIKU slug
- `/model` (no arg) → opens Claude Code's own picker, where you'll also
  see whatever main model claudr launched you with

Subagents declared with `model: opus|sonnet|haiku` in their frontmatter
get routed automatically — you don't need to switch manually.

#### Per-launch overrides (skip the saved config)

| Override                                | Effect                                          |
|-----------------------------------------|-------------------------------------------------|
| `CLAUDR_OPUS_MODEL=<slug> claudr`       | Override opus tier for this launch only         |
| `CLAUDR_SONNET_MODEL=<slug> claudr`     | Override sonnet tier for this launch only       |
| `CLAUDR_HAIKU_MODEL=<slug> claudr`      | Override haiku tier for this launch only        |
| `claudr -m <slug>`                      | Override main model only; tiers stay as configured |
| `claudr --preset <name>`                | Use a named preset instead of the default tier config |

You can combine them. Example: run with your saved config but swap opus
to GPT-5 for a one-off session:

```bash
CLAUDR_OPUS_MODEL=openai/gpt-5 claudr
```

Example: run main on Kimi but keep tier routing intact (so subagents still
go to your saved opus/sonnet/haiku):

```bash
claudr -m kimi
```

### Named presets

If you flip between workflows — e.g. cheap models for boilerplate, top-tier
for hard debugging — save each one as a named preset instead of re-running
the wizard:

```bash
claudr --tiers cheap            # wizard → saves to ~/.config/claudr/presets/cheap.conf
claudr --tiers power            # different picks → saves as power
claudr --presets                # list all presets (with their tier mappings)
claudr --preset cheap           # launch with the 'cheap' preset
```

Bare `claudr` still uses the default `tiers.conf`. Each preset is a small
shell-source file you can also edit by hand:

```
# ~/.config/claudr/presets/coding.conf
OPUS=anthropic/claude-opus-4.7
SONNET=anthropic/claude-sonnet-4.6
HAIKU=anthropic/claude-haiku-4.5
```

The active preset name shows in the launch banner and the statusline.

### Non-interactive use (`-p` / `--ask`)

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
`redacted_thinking` blocks). The fix is invisible: you keep the `-p`
ergonomics, you get the actual text out.

If you explicitly pass `--output-format json` or `--output-format stream-json`,
claudr passes through to `claude` untouched — you're presumably parsing the
structured output yourself.

The launch banner auto-suppresses in print mode so it doesn't pollute
scripted output. Force-show it with `CLAUDR_BANNER=1`. Opt out of the
auto-routing with `CLAUDR_RAW_PRINT=1` (raw passthrough to `claude -p`).

### Doctor

```bash
claudr --doctor
```

Runs a health check that verifies the `claude` CLI, `fzf`, `python3`,
your OpenRouter key (live ping to `/auth/key`), Tavily key, default
tier config, tier slug validity against the OpenRouter catalog, saved
presets, and the model-cache freshness. Color-coded ✓ / ! / ✗ with a
summary line. Good first thing to run if something feels off.

### Statusline

claudr writes a small statusline script and per-session settings file,
then passes them to `claude --settings`. While you're inside the session,
Claude Code's footer shows the model, context window, active preset, and
working directory:

```
claudr · qwen/qwen3.7-max · ctx 1M · [coding] · myproject
```

Disable with `CLAUDR_STATUSLINE=0` if you have your own.

### OpenRouter attribution

Every request claudr makes is tagged with `HTTP-Referer:
github.com/olindkri/claudr` and `X-Title: claudr` (via
`ANTHROPIC_CUSTOM_HEADERS`), so your
[OpenRouter activity dashboard](https://openrouter.ai/activity) groups
claudr usage under one label and helps you debug rate-limit and provider
routing issues. Override with `CLAUDR_REFERER` / `CLAUDR_TITLE`.

#### Other configurable options

| Setting                            | Default        | What it does                                                                |
|------------------------------------|----------------|-----------------------------------------------------------------------------|
| `OPENROUTER_RANK_VIEW` env var     | `week`         | Leaderboard window for the picker (`day` / `week` / `month` / `trending`)   |
| `OPENROUTER_TOP_N` env var         | `25`           | How many ranked models appear above the full catalog in the picker          |
| `--view <window>`                  | —              | Same as `OPENROUTER_RANK_VIEW`, per-launch                                  |
| `-n <N>` / `--top <N>`             | —              | Same as `OPENROUTER_TOP_N`, per-launch                                      |
| `--refresh`                        | —              | Bypass the 6h leaderboard/catalog cache for this launch                     |
| `CLAUDR_AUTOCOMPACT=1` env var     | off            | Re-enable Claude Code's auto-compaction (pins window at 200K — see below)   |
| `CLAUDR_SAFE=1` env var            | off            | Don't pass `--dangerously-skip-permissions` to claude                       |
| `CLAUDR_ALLOW_WEBSEARCH=1` env var | off            | Don't pass `--disallowedTools WebSearch` (lets the no-op tool show up)      |
| `TAVILY_API_KEY` env var           | —              | Use this Tavily key for the web-search MCP instead of the saved file       |
| `CLAUDR_STATUSLINE=0` env var      | on             | Disable claudr's statusline (use your own `claude` settings.json instead)  |
| `CLAUDR_BANNER=1` env var          | auto           | Force-show the launch banner (normally hidden in `-p` / `--ask` modes)     |
| `CLAUDR_RAW_PRINT=1` env var       | off            | Disable `-p` auto-routing; pass `claude -p` through raw                    |
| `CLAUDR_REFERER` / `CLAUDR_TITLE`  | claudr/github  | Override OpenRouter attribution headers (`HTTP-Referer` / `X-Title`)       |
| `CLAUDR_THINKING=1` env var        | off            | Keep extended thinking enabled in print mode (default: disabled for `-p`)  |

#### In the picker / wizard

- **↑↓** to move, **Enter** to confirm, **Esc** to cancel
- Type to fuzzy-filter the list
- **Ctrl+A** to change your OpenRouter API key without leaving the picker

Built-in name aliases (for `-m` and inside the wizard): `kimi`, `kimi-thinking`,
`sonnet`, `opus`, `haiku`, `deepseek`, `deepseek-flash`, `glm`, `qwen`,
`qwen-coder`, `gemma`, `gemini`, `minimax`, `grok`, `gpt`. Anything else is
passed through as a literal OpenRouter model slug.

## Uninstall

**macOS / Linux** — remove the symlink and source clone:

```bash
rm -f "$(command -v claudr)" ~/.config/claudr/key
# if you cloned to ~/.claudr:
rm -rf ~/.claudr
```

**Windows:**

```powershell
& "$env:LOCALAPPDATA\Programs\claudr\install.ps1" -Uninstall
```

## Web search (Tavily, scoped to this launcher)

Claude Code's built-in `WebSearch` tool runs server-side on Anthropic's
infrastructure, so it doesn't work on OpenRouter models. The launcher
fixes this by **injecting Tavily as an MCP server only for claudr
launches** — passed via `--mcp-config`, never registered globally. Other
`claude` invocations on the same machine (Ollama's launcher, plain
`claude`, etc.) see no Tavily and use whatever search they had configured.

On first launch you'll be prompted for a Tavily API key:

1. Sign up at https://app.tavily.com (30-sec, no card on free tier)
2. Copy the API key from the dashboard
3. Paste it when the launcher asks

Free tier is **1000 queries/month** with no per-second rate cap.

Under the hood: the key is saved to `~/.claudr/tavily-key`,
and on every launch the launcher writes `~/.claudr/mcp.json`
pointing at Tavily's hosted remote MCP (`https://mcp.tavily.com/mcp/?tavilyApiKey=...`)
and passes that file via `claude --mcp-config`. The launcher also passes
`--disallowedTools WebSearch` so the model can't pick the no-op
Anthropic tool over Tavily.

**Skip / set later:** press Enter at the prompt to skip — search just
won't be available in claudr sessions until you set a key.
**Rotate:** edit or delete `~/.claudr/tavily-key` and re-launch.

## Context window on non-Anthropic models

Claude Code hardcodes a 200K window for unknown / non-Anthropic models —
even if the model actually supports 1M (DeepSeek V4 Pro) or 256K (Kimi K2.6).
The env var `CLAUDE_CODE_MAX_CONTEXT_TOKENS` only takes effect when
`DISABLE_COMPACT=1` is *also* set. There's no way to get both auto-compaction
and the true window.

The launcher picks the **real window** by default:

- Sets `DISABLE_COMPACT=1` and `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<catalog value>`
- DeepSeek V4 Pro shows as 1,000,000 tokens in `/context`, Kimi K2.6 as 256,000
- Auto-compaction is off — run `/compact` yourself when you want to summarize

If you'd rather have auto-compaction back (at the cost of a 200K cap):

```bash
CLAUDR_AUTOCOMPACT=1 claudr
```

That sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` and skips `DISABLE_COMPACT`,
so Claude Code will auto-compact at 75% of its 200K assumption.

## Auto-compaction on non-Anthropic models

Claude Code's built-in auto-compaction is a server-side feature gated by an
Anthropic-only beta header (`context-management-2025-06-27`). OpenRouter
doesn't forward it, so on non-Anthropic models the session would otherwise
just run out of context with no warning.

The launcher works around this by exporting two undocumented Claude Code
env vars before exec'ing `claude`:

- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` — set from the catalog `context_length`
  of the chosen model, capped at 180000 (providers commonly serve less than
  the catalog claims).
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` — fire `/compact` at 75% instead of
  the default ~92%, since alternative models pollute context faster.

Override either by setting the env var yourself before running
`claudr`. If you're hitting context walls anyway, run `/compact`
manually every 10–15 turns or restart the session.

## Troubleshooting

Start with:

```bash
claudr --doctor
```

It verifies the `claude` CLI, `fzf`, `python3`, your OpenRouter key (with a
live ping), Tavily key, default tier config, tier slugs against the
OpenRouter catalog, saved presets, and model-cache freshness — color-coded
pass / warn / fail with a summary line. Fast first thing to run when
something feels off.

| Symptom                                          | Try                                                    |
|--------------------------------------------------|--------------------------------------------------------|
| Picker empty / leaderboard not loading           | `claudr --refresh` (bypasses the 6h cache)             |
| Wrong model slug saved                           | `claudr --tiers` to re-pick, or edit `~/.config/claudr/tiers.conf` |
| Want to swap your OpenRouter key                 | Press **Ctrl+A** inside the picker, or delete `~/.config/claudr/key` |
| Web search not working                           | Set `TAVILY_API_KEY` or write the key to `~/.config/claudr/tavily-key` |
| `claudr -p "..."` returns empty in older versions | Update — claudr auto-routes around [claude-code#38805](https://github.com/anthropics/claude-code/issues/38805); set `CLAUDR_RAW_PRINT=1` to opt out |
| Statusline clashes with your own                 | `CLAUDR_STATUSLINE=0 claudr`                           |

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
