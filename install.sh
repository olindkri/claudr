#!/usr/bin/env bash
# install.sh — install claudr on macOS/Linux so it runs from any terminal.
# Idempotent: re-run to update. Use INSTALL_DIR=... to override location.

set -euo pipefail

# Resolve script's own directory (works whether called via path, symlink, or curl|bash)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SRC_DIR="$(pwd)"
fi
LAUNCHER="$SRC_DIR/claudr"

# Pick an install dir: explicit override > first writable PATH dir among the candidates.
INSTALL_DIR="${INSTALL_DIR:-}"
if [ -z "$INSTALL_DIR" ]; then
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
    if [ -d "$d" ] && [ -w "$d" ]; then INSTALL_DIR="$d"; break; fi
    if [ ! -d "$d" ] && [ "$d" = "$HOME/.local/bin" ]; then INSTALL_DIR="$d"; break; fi
  done
fi
[ -z "$INSTALL_DIR" ] && INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"

REPO_URL="${CLAUDR_REPO:-https://github.com/olindkri/claudr}"

# If launched standalone (e.g. curl|bash), clone the repo to a persistent location.
if [ ! -f "$LAUNCHER" ]; then
  CLONE_DIR="${CLAUDR_DIR:-$HOME/.claudr}"
  if [ -d "$CLONE_DIR/.git" ]; then
    echo "Updating existing clone: $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only --quiet || true
  else
    echo "Cloning $REPO_URL -> $CLONE_DIR"
    rm -rf "$CLONE_DIR"
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" >/dev/null
  fi
  SRC_DIR="$CLONE_DIR"
  LAUNCHER="$SRC_DIR/claudr"
fi

if [ ! -f "$LAUNCHER" ]; then
  echo "install.sh: claudr launcher not found (looked in $SRC_DIR)" >&2
  exit 1
fi

# Symlink so future `git pull` in the source dir updates the command for free.
ln -sf "$LAUNCHER" "$INSTALL_DIR/claudr"
chmod +x "$LAUNCHER"

echo "Installed: $INSTALL_DIR/claudr -> $LAUNCHER"

# PATH sanity
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "WARN: $INSTALL_DIR is not on your PATH."
    case "$INSTALL_DIR" in
      "$HOME/.local/bin")
        echo "  Add to your shell rc:"
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc   # or ~/.bashrc"
        ;;
      *)
        echo "  Add to your shell rc:"
        echo "    echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc"
        ;;
    esac
    ;;
esac

# claude CLI check
if ! command -v claude >/dev/null 2>&1; then
  echo ""
  echo "WARN: 'claude' CLI not found on PATH."
  echo "  install:  npm i -g @anthropic-ai/claude-code"
fi

# fzf check (offer to install via the first detected package manager)
if ! command -v fzf >/dev/null 2>&1; then
  FZF_CMD=""
  FZF_LABEL=""
  if command -v brew >/dev/null 2>&1; then
    FZF_CMD="brew install fzf"; FZF_LABEL="Homebrew"
  elif command -v apt >/dev/null 2>&1; then
    FZF_CMD="sudo apt install -y fzf"; FZF_LABEL="apt"
  elif command -v dnf >/dev/null 2>&1; then
    FZF_CMD="sudo dnf install -y fzf"; FZF_LABEL="dnf"
  elif command -v pacman >/dev/null 2>&1; then
    FZF_CMD="sudo pacman -S --noconfirm fzf"; FZF_LABEL="pacman"
  elif command -v zypper >/dev/null 2>&1; then
    FZF_CMD="sudo zypper install -y fzf"; FZF_LABEL="zypper"
  elif command -v apk >/dev/null 2>&1; then
    FZF_CMD="sudo apk add fzf"; FZF_LABEL="apk"
  fi

  if [ -n "$FZF_CMD" ]; then
    echo ""
    printf "Install fzf via %s for arrow-key picker? [Y/n] " "$FZF_LABEL"
    read -r ANS </dev/tty || ANS=""
    case "$ANS" in
      n|N|no|NO) echo "  skipped (you can install later with: $FZF_CMD)" ;;
      *)         eval "$FZF_CMD" || echo "  fzf install failed; launcher will fall back to a numbered prompt." ;;
    esac
  else
    echo ""
    echo "Tip: install fzf for arrow-key model picking (no supported package manager detected)."
  fi
fi

echo ""
echo "Done. Open a new terminal and run: claudr"
echo "On first launch you'll be prompted for two keys:"
echo "  - OpenRouter API key (required) — https://openrouter.ai/keys"
echo "  - Tavily API key (optional, for web search, free 1000/mo) — https://app.tavily.com"
