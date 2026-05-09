#!/bin/bash
# Empire bootstrap — fresh Mac → fully operational empire node, in one shot.
#
# Run (download-then-run because Homebrew + sudo + bw need a real TTY):
#   curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/install.sh -o ~/empire-install.sh && bash ~/empire-install.sh
#
# Manual touchpoints during the run:
#   - Xcode CLT GUI prompt (P0, first run only)
#   - Homebrew sudo password (P1, first run only)
#   - gh auth login device-code flow (P3, first run only)
#   - Bitwarden API client_id + client_secret paste (P5, first run only)
#   - Bitwarden master password (P5; up to 3 retries on typo)
#   - Claude Max browser auth (P5.5, first run only)
#   - sudo password for pmset (P10)
#
# Everything else is automatic. Idempotent — safe to re-run any time.
# Full transcript is teed to ~/empire-bootstrap-<UTC>.log for postmortems.

set -euo pipefail

# ---------- 1. universal log capture ----------
# Every line of output (stdout + stderr) is mirrored into a timestamped
# logfile in $HOME so future debugging doesn't depend on scrollback.
LOG_FILE="$HOME/empire-bootstrap-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "🚀 Empire bootstrap starting... (log: $LOG_FILE)"

# ---------- P0: Xcode Command Line Tools ----------
echo "── P0: Xcode CLT"
xcode-select --install 2>/dev/null || true

# ---------- P1: Homebrew ----------
# Install Homebrew if missing, then PERSIST `brew shellenv` to ~/.zprofile so
# every future shell finds /opt/homebrew/bin/brew on PATH. Without this,
# re-running install.sh from a fresh shell can fail with "command not found: brew".
echo "── P1: Homebrew"
if ! command -v brew &>/dev/null; then
  if [ -t 0 ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "❌ ERROR: Homebrew install needs interactive stdin for sudo prompt."
    echo "   You ran this via 'curl | bash' which occupies stdin."
    echo "   Fix: download then run:"
    echo "     curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/install.sh -o ~/empire-install.sh && bash ~/empire-install.sh"
    exit 1
  fi
fi
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN=/usr/local/bin/brew
else
  echo "❌ brew not found in either /opt/homebrew/bin or /usr/local/bin after install"
  exit 1
fi
eval "$($BREW_BIN shellenv)"
# Persist for all future shells
if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
  echo "eval \"\$($BREW_BIN shellenv)\"" >> "$HOME/.zprofile"
  echo "✅ added brew shellenv to ~/.zprofile"
fi

# ---------- P2: Brew packages ----------
# Casks: --force tolerates a pre-existing /Applications/Bitwarden.app, etc.
# without aborting. Filter out the noisy "already an App" notice for clarity.
echo "── P2: brew packages"
brew install git gh age bitwarden-cli jq python@3.12 node ripgrep
brew install --cask --force ghostty raycast rectangle bitwarden 2>&1 \
  | grep -vE 'already an App|Not upgrading' || true

for cmd in git gh age bw jq python3 node rg; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ $cmd missing after brew install"
    exit 1
  fi
done
echo "✅ All brew packages verified in PATH"

# ---------- P3: GitHub auth ----------
echo "── P3: gh auth login (interactive)"
if ! gh auth status &>/dev/null; then
  gh auth login
fi

# ---------- P4: Clone bootstrap repos ----------
echo "── P4: clone repos"
mkdir -p "$HOME/supa-work"
cd "$HOME/supa-work"
[[ -d AI-Agent-Bible ]] || gh repo clone MrDadaMon/mejia-ai-agent-bible AI-Agent-Bible
[[ -d Mejia-Supa-Hermes-Overlay ]] || gh repo clone MrDadaMon/mejia-supa-hermes-overlay Mejia-Supa-Hermes-Overlay

OVERLAY="$HOME/supa-work/Mejia-Supa-Hermes-Overlay"

# ---------- P5: Bitwarden bootstrap ----------
# Master-password unlock with up to 3 retries — the previous version aborted
# on the first typo with the cryptic "decryption operation failed" error,
# forcing the user to manually re-run the whole script.
echo "── P5: Bitwarden"
echo "🔐 Bitwarden login (email + master password)"
echo "   You'll be prompted for: email, master password, and 2FA code if enabled"
bw login || echo "Already logged in, continuing..."
echo "🔓 Unlocking vault (up to 3 attempts)..."
BW_SESSION=""
for attempt in 1 2 3; do
  BW_SESSION=$(bw unlock --raw 2>/dev/null || true)
  if [ -n "$BW_SESSION" ]; then
    break
  fi
  echo "❌ unlock attempt $attempt failed — wrong master password? Try again."
done
if [ -z "$BW_SESSION" ]; then
  echo "❌ BW unlock failed after 3 attempts. Aborting."
  exit 1
fi
export BW_SESSION
echo "✅ BW unlocked"
bash "$OVERLAY/scripts/bw_sync_env.sh"
# shellcheck disable=SC1090
source "$HOME/.env.empire"
grep -q '.env.empire' "$HOME/.zshrc" 2>/dev/null || \
  echo '[ -f ~/.env.empire ] && source ~/.env.empire' >> "$HOME/.zshrc"

# ---------- P5.5: Claude Code CLI + Max-subscription OAuth ----------
# Installs the Claude Code CLI and authenticates it against your Max/Pro
# subscription. The OAuth credential lands in macOS Keychain under
# "Claude Code-credentials" and is the source of truth used by the
# hermes-claude-auth patch in P6.5.
echo "── P5.5: Claude Code CLI + Max-subscription OAuth"
if ! command -v claude &>/dev/null; then
  npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code
fi
echo "✅ Claude Code installed: $(claude --version 2>&1 | head -1)"

if ! security find-generic-password -s "Claude Code-credentials" -w &>/dev/null; then
  echo "🔐 Logging Claude Code into your Max/Pro subscription (browser will open)..."
  if [ -t 0 ]; then
    claude auth login --claudeai || {
      echo "❌ claude auth login failed — re-run manually:  claude auth login --claudeai"
      exit 1
    }
  else
    echo "❌ Need interactive stdin for 'claude auth login --claudeai'."
    echo "   Re-run install.sh from a real terminal (not curl|bash)."
    exit 1
  fi
else
  echo "✅ Claude Code credentials already in Keychain"
fi

# ---------- P6: Hermes agent ----------
# Run the upstream installer, then immediately PATH-inject ~/.local/bin so
# this same shell can invoke `hermes` for the post-install steps. The
# Hermes installer adds .local/bin to .zshrc/.zprofile but the running
# bash doesn't pick it up.
echo "── P6: Hermes agent"
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

export PATH="$HOME/.local/bin:$PATH"
hash -r
if ! command -v hermes &>/dev/null; then
  echo "❌ hermes not on PATH after install. Tried: $HOME/.local/bin"
  exit 1
fi
echo "✅ hermes on PATH: $(command -v hermes)"

# ---------- P6.5: Wire Hermes to Claude Max (April-2025 OAuth lockdown) ----------
# Anthropic patched their API on 2025-04-04 to reject OAuth requests from any
# client other than Claude Code itself. The hermes-claude-auth patch restores
# compatibility by injecting the billing-header signature + system-prompt
# shape Anthropic now requires, hooked in via sitecustomize.py.
echo "── P6.5: hermes-claude-auth patch + Hermes Max wiring"
if [ ! -f "$HOME/.hermes/patches/anthropic_billing_bypass.py" ]; then
  curl -fsSL https://raw.githubusercontent.com/kristianvastveit/hermes-claude-auth/main/install-remote.sh | bash
else
  echo "✅ hermes-claude-auth patch already installed"
fi

# Point Hermes at Opus 4.7 via the Anthropic provider.
hermes config set model.provider anthropic                || true
hermes config set model.default anthropic/claude-opus-4-7 || true

# Critical: clear ANTHROPIC_API_KEY. Max plan does not include API credits;
# if a key is present Hermes prefers it and fails with HTTP 400
# "credit balance too low". The patch routes through the OAuth token instead.
if [ -f "$HOME/.hermes/.env" ]; then
  /usr/bin/sed -i '' '/^ANTHROPIC_API_KEY=/d' "$HOME/.hermes/.env" || true
fi
hermes config set ANTHROPIC_API_KEY "" || true

# Install the canonical empire SOUL.md if the user hasn't customized.
SOUL_SRC="$OVERLAY/SOUL.md"
SOUL_DST="$HOME/.hermes/SOUL.md"
if [ -f "$SOUL_SRC" ]; then
  if [ ! -f "$SOUL_DST" ] || ! grep -q "Empire SOUL" "$SOUL_DST" 2>/dev/null; then
    cp "$SOUL_SRC" "$SOUL_DST"
    echo "✅ installed empire SOUL.md"
  else
    echo "✅ empire SOUL.md already in place"
  fi
fi

# Verify end-to-end: this exercises the patched OAuth path against Opus.
echo "🧪 Verifying Hermes ↔ Claude Max..."
if timeout 30 hermes chat -q "Reply with just OK" 2>&1 | grep -qi "ok"; then
  echo "✅ Hermes is talking to Claude Max via OAuth"
else
  echo "⚠️  Hermes verification did not return OK. Check:"
  echo "    - security find-generic-password -s 'Claude Code-credentials' -w"
  echo "    - ls ~/.hermes/patches/anthropic_billing_bypass.py"
  echo "    - hermes config get model.provider model.default"
fi

# ---------- P7: Vault restore ----------
echo "── P7: vault restore"
bash "$OVERLAY/scripts/vault_restore_decrypt.sh" || true

# ---------- P8: Overlay bootstrap (no reranker venv anymore) ----------
echo "── P8: overlay bootstrap"
bash "$OVERLAY/scripts/bootstrap.sh" || true

# ---------- P9: launchd jobs ----------
# install_launchd_jobs.sh seeds ~/.hermes/cron/jobs.json from this very
# repo if missing, then generates plists with --all-hermes and loads them.
echo "── P9: launchd jobs"
bash "$OVERLAY/scripts/install_launchd_jobs.sh"

# ---------- P10: 24/7 lid-closed ----------
# Verify pmset actually applied (the previous version printed a warning and
# moved on, so a typo'd sudo password silently left the machine sleeping).
echo "── P10: pmset (sudo)"
if [ -t 0 ]; then
  if sudo -v; then
    sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1 || true
    sudo pmset -c lidwake 0 || true
    SLEEP_VAL=$(pmset -g | awk '/^ sleep/{print $2; exit}')
    if [ "$SLEEP_VAL" != "0" ]; then
      echo "⚠️  pmset sleep is still '$SLEEP_VAL' (expected 0). Re-run:"
      echo "    sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1"
    else
      echo "✅ pmset configured for 24/7 lid-closed operation"
    fi
  else
    echo "⚠️  sudo unavailable — skipping pmset. Re-run manually:"
    echo "    sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1"
    echo "    sudo pmset -c lidwake 0"
  fi
else
  echo "⚠️  Skipping pmset (needs interactive sudo). Run manually after bootstrap:"
  echo "    sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1"
  echo "    sudo pmset -c lidwake 0"
fi

# ---------- P11: Smoke test ----------
echo "── P11: smoke test"
bash "$OVERLAY/scripts/smoke_test.sh"

# ---------- P12: Telegram done ----------
echo "── P12: telegram alert"
bash "$OVERLAY/scripts/telegram_alert.sh" "Mac bootstrap ✅ — see $LOG_FILE" || true

echo ""
echo "✅ Empire bootstrap complete."
echo "   Log: $LOG_FILE"
echo "   Verify any time: bash $HOME/supa-work/empire-bootstrap/scripts/verify.sh"
echo "                or: curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/scripts/verify.sh | bash"
