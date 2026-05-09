#!/bin/bash
# Empire bootstrap — fresh Mac to operational empire in one curl|bash.
# Run:
#   curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/install.sh | bash
#
# Manual touchpoints during run:
#   - Xcode CLT GUI prompt (P0)
#   - `gh auth login` device-code flow (P3)
#   - Bitwarden API client_id + client_secret paste (P5)
#   - Bitwarden master password prompt (P5, via bw unlock)
#   - sudo password for pmset (P10)
set -euo pipefail

echo "🚀 Empire bootstrap starting..."

# P0: Xcode CLT
echo "── P0: Xcode CLT"
xcode-select --install 2>/dev/null || true

# P1: Homebrew
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
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# P2: Brew packages
echo "── P2: brew packages"
brew install git gh age bitwarden-cli jq python@3.12 node ripgrep
brew install --cask ghostty raycast rectangle bitwarden || true

for cmd in git gh age bw jq python3 node rg; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌ $cmd missing after brew install"
    exit 1
  fi
done
echo "✅ All brew packages verified in PATH"

# P3: GitHub auth
echo "── P3: gh auth login (interactive)"
if ! gh auth status &>/dev/null; then
  gh auth login
fi

# P4: Clone repos
echo "── P4: clone repos"
mkdir -p "$HOME/supa-work"
cd "$HOME/supa-work"
[[ -d AI-Agent-Bible ]] || gh repo clone MrDadaMon/mejia-ai-agent-bible AI-Agent-Bible
[[ -d Mejia-Supa-Hermes-Overlay ]] || gh repo clone MrDadaMon/mejia-supa-hermes-overlay Mejia-Supa-Hermes-Overlay

# P5: Bitwarden bootstrap
echo "── P5: Bitwarden"
echo "🔐 Bitwarden login (email + master password)"
echo "   You'll be prompted for: email, master password, and 2FA code if enabled"
bw login || echo "Already logged in, continuing..."
echo "🔓 Unlocking vault..."
export BW_SESSION=$(bw unlock --raw)
if [ -z "$BW_SESSION" ]; then
  echo "❌ BW unlock failed"
  exit 1
fi
echo "✅ BW unlocked"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/bw_sync_env.sh"
# shellcheck disable=SC1090
source "$HOME/.env.empire"
grep -q '.env.empire' "$HOME/.zshrc" 2>/dev/null || \
  echo '[ -f ~/.env.empire ] && source ~/.env.empire' >> "$HOME/.zshrc"

echo "── P5.5: Claude Code CLI + Max-subscription OAuth"
if ! command -v claude &>/dev/null; then
  npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code
fi
echo "✅ Claude Code installed: $(claude --version 2>&1 | head -1)"

# Authenticate Claude Code against the Max/Pro subscription (browser flow).
# This stores credentials in the macOS Keychain under "Claude Code-credentials"
# and is the source of truth used by the hermes-claude-auth patch in P6.5.
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

# P6: Hermes / Claude Code agent
echo "── P6: Hermes agent"
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

# P6.5: Wire Hermes to the Max subscription (April-2025 OAuth lockdown patch)
# Anthropic patched their API on 2025-04-04 to reject OAuth requests from any
# client other than Claude Code itself. The hermes-claude-auth patch restores
# compatibility by injecting the billing-header signature + system-prompt shape
# Anthropic now requires, hooked in via sitecustomize.py.
echo "── P6.5: hermes-claude-auth patch + Hermes model config"
if [ ! -f "$HOME/.hermes/patches/anthropic_billing_bypass.py" ]; then
  curl -fsSL https://raw.githubusercontent.com/kristianvastveit/hermes-claude-auth/main/install-remote.sh | bash
else
  echo "✅ hermes-claude-auth patch already installed"
fi

# Point Hermes at Opus 4.7 via the Anthropic provider.
hermes config set model.provider anthropic        || true
hermes config set model.default anthropic/claude-opus-4-7 || true

# Critical: clear ANTHROPIC_API_KEY. Max plan does not include API credits, and
# if an API key is present Hermes will prefer it and fail with HTTP 400
# "credit balance too low". The patch routes through the OAuth token instead.
if [ -f "$HOME/.hermes/.env" ]; then
  /usr/bin/sed -i '' '/^ANTHROPIC_API_KEY=/d' "$HOME/.hermes/.env" || true
fi
hermes config set ANTHROPIC_API_KEY "" || true

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

# P7: Vault restore
echo "── P7: vault restore"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/vault_restore_decrypt.sh" || true

# P8: Reranker / overlay bootstrap
echo "── P8: overlay bootstrap"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/bootstrap.sh" || true

# P9: launchd jobs
echo "── P9: launchd jobs"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/install_launchd_jobs.sh"

# P10: 24/7 lid-closed
echo "── P10: pmset (sudo)"
if [ -t 0 ]; then
  sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1 || true
  sudo pmset -c lidwake 0 || true
else
  echo "⚠️  Skipping pmset (needs interactive sudo). Run manually after bootstrap:"
  echo "    sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1"
  echo "    sudo pmset -c lidwake 0"
fi

# P11: Smoke test
echo "── P11: smoke test"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/smoke_test.sh"

# P12: Telegram done
echo "── P12: telegram alert"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/telegram_alert.sh" "Mac bootstrap ✅" || true

echo "✅ Empire bootstrap complete."
