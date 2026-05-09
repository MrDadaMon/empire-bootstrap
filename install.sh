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
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
if [[ -z "${BW_CLIENTID:-}" ]]; then
  read -r -p "Bitwarden API client_id: " BW_CLIENTID
fi
if [[ -z "${BW_CLIENTSECRET:-}" ]]; then
  read -r -s -p "Bitwarden API client_secret: " BW_CLIENTSECRET
  echo
fi
export BW_CLIENTID BW_CLIENTSECRET
bw login --apikey || true
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/bw_sync_env.sh"
# shellcheck disable=SC1090
source "$HOME/.env.empire"
grep -q '.env.empire' "$HOME/.zshrc" 2>/dev/null || \
  echo '[ -f ~/.env.empire ] && source ~/.env.empire' >> "$HOME/.zshrc"

# P6: Hermes / Claude Code agent
echo "── P6: Hermes agent"
pip3 install --upgrade hermes-agent || pip3 install --upgrade claude-code || true

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
sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1 || true
sudo pmset -c lidwake 0 || true

# P11: Smoke test
echo "── P11: smoke test"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/smoke_test.sh"

# P12: Telegram done
echo "── P12: telegram alert"
bash "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/telegram_alert.sh" "Mac bootstrap ✅" || true

echo "✅ Empire bootstrap complete."
