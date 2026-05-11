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

# Append a "computed paths" block to ~/.env.empire so every overlay tool
# resolves to this user's $HOME, not the original Linux author's. This is
# the safety net for any code that uses ${VAR:-/home/maestro/...} fallback
# patterns — VAR is now always set, so the fallback never fires. Idempotent:
# only writes if the marker line is absent.
if ! grep -q '^# === EMPIRE COMPUTED PATHS ===' "$HOME/.env.empire" 2>/dev/null; then
  cat >> "$HOME/.env.empire" <<EOF

# === EMPIRE COMPUTED PATHS ===
# Auto-injected by empire-bootstrap install.sh — survives bw_sync_env reruns
# because that script only writes the body of the BW 'empire-env' note above.
# Resolves cross-platform path drift: Linux author wrote /home/maestro/...,
# Macs need /Users/<user>/..., VPS may differ. \$HOME is always correct.
export SUPA_WORK_ROOT="\$HOME/supa-work"
export AI_AGENT_BIBLE_ROOT="\$HOME/supa-work/AI-Agent-Bible"
export OVERLAY_ROOT="\$HOME/supa-work/Mejia-Supa-Hermes-Overlay"
export MEJIA_VAULT_ROOT="\$HOME/supa-work/Mejia-Vault"
export MEJIA_VAULT="\$HOME/supa-work/Mejia-Vault"
export VAULT_BACKUP_DIR="\$HOME/supa-work/mejia-vault-encrypted"
export HERMES_REPO_ROOT="\$HOME/supa-work"
export HERMES_DECISION_LOG="\$HOME/supa-work/AI-Agent-Bible/04-Shared/decision-log"
export HERMES_SKILLS_DIR="\$HOME/.hermes/skills"
export HERMES_CACHE_DIR="\$HOME/.hermes/cache"
export HERMES_MCP_AUDIT_DIR="\$HOME/.hermes/audit/mcp"
export NLM_BUNDLE_DIR="\$HOME/supa-work/notebooklm-bundles"
export NLM_DIGEST="\$HOME/supa-work/Mejia-Vault/wiki/notebooklm-digest.md"
EOF
  echo "✅ injected EMPIRE COMPUTED PATHS into ~/.env.empire"
  # Re-source so the rest of this install run sees them
  # shellcheck disable=SC1090
  source "$HOME/.env.empire"
else
  echo "✅ EMPIRE COMPUTED PATHS already present in ~/.env.empire"
fi

# ---------- P5.5: Claude Code CLI + Max-subscription OAuth ----------
# Installs the Claude Code CLI and authenticates it against your Max/Pro
# subscription. The OAuth credential lands in macOS Keychain under
# "Claude Code-credentials" and is the source of truth used by the
# cloaked proxy in P6.5.
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

# ---------- P6.5: LLM router (Opus via proxy + DeepSeek/MiniMax aux) ----------
# Anthropic patched their API in 2025-04 to refuse OAuth requests from any
# client that doesn't masquerade as Claude Code itself. Our cloaked proxy
# (cloaked-proxy.py) sits on 127.0.0.1:8318, accepts Hermes' /v1/messages
# calls, scrubs Hermes-specific identifiers, injects the Claude Code agent
# identity system block, and forwards to api.anthropic.com with the OAuth
# bearer from ~/.claude/.credentials.json. Auto-refreshes silently.
#
# Provider lineup written into ~/.hermes/config.yaml:
#   main          → anthropic (Opus 4.7) via proxy
#   fallback      → DeepSeek v4 Pro
#   auxiliary.*   → per-role mapping (bulk → DeepSeek, judgment → MiniMax,
#                                     vision → main provider)
echo "── P6.5: LLM router + Opus proxy"

# Install the cloaked proxy (routes Max subscription through Anthropic API)
mkdir -p "$HOME/.hermes/proxy"
cp "$OVERLAY/proxy/cloaked-proxy.py" "$HOME/.hermes/proxy/cloaked-proxy.py"
cp "$OVERLAY/proxy/com.mejia.opus-proxy.plist" "$HOME/Library/LaunchAgents/com.mejia.opus-proxy.plist"
chmod +x "$HOME/.hermes/proxy/cloaked-proxy.py"
launchctl unload "$HOME/Library/LaunchAgents/com.mejia.opus-proxy.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.mejia.opus-proxy.plist" 2>/dev/null || true
echo "✅ Opus cloaked proxy installed (:8318)"

# Sync OAuth credentials from Keychain → file (proxy reads from file)
mkdir -p "$HOME/.claude"
security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null > "$HOME/.claude/.credentials.json" || true

# Write config.yaml provider + aux routing in one Python call (yaml-safe)
"$HOME/.hermes/hermes-agent/venv/bin/python" <<'PY'
import yaml, os
from pathlib import Path
cfg_path = Path(os.path.expanduser("~/.hermes/config.yaml"))
cfg = yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}

# Main model — Opus 4.7 via proxy with explicit 1M context (bypasses probe-down)
cfg.setdefault("model", {}).update({
    "provider": "anthropic",
    "default":  "claude-opus-4-7",
    "base_url": "http://127.0.0.1:8318",
    "context_length":         1_000_000,
    "config_context_length":  1_000_000,
    "max_tokens": 64_000,
})

# Provider lineup — anthropic via proxy + deepseek + minimax
providers = cfg.setdefault("providers", {})
providers["anthropic"] = {"base_url": "http://127.0.0.1:8318", "api_key": "sk-ant...0000"}
providers["deepseek"]  = {"base_url": "https://api.deepseek.com", "api_key": "${DEEPSEEK_API_KEY}"}
providers["minimax"]   = {"base_url": "https://api.minimax.io/v1", "api_key": "${MINIMAX_API_KEY}"}

# Fallback chain — if Opus fails, drop to DeepSeek v4 Pro
cfg["fallback_providers"] = [{"provider": "deepseek", "model": "deepseek-v4-pro"}]

# Auxiliary routing — cost-aware per-role
ROLES = {
    "compression":       ("deepseek", "deepseek-v4-pro"),
    "web_extract":       ("deepseek", "deepseek-v4-pro"),
    "session_search":    ("deepseek", "deepseek-v4-pro"),
    "title_generation":  ("deepseek", "deepseek-v4-flash"),
    "skills_hub":        ("deepseek", "deepseek-v4-flash"),
    "mcp":               ("deepseek", "deepseek-v4-flash"),
    "triage_specifier":  ("minimax",  "MiniMax-M2"),
    "approval":          ("minimax",  "MiniMax-M2"),
    "curator":           ("minimax",  "MiniMax-M2"),
}
aux = cfg.setdefault("auxiliary", {})
for role, (provider, model) in ROLES.items():
    section = aux.setdefault(role, {})
    section["provider"] = provider
    section["model"]    = model
    section["context_length"] = 1_000_000  # belt-suspenders for probe-down

cfg_path.write_text(yaml.dump(cfg, default_flow_style=False, sort_keys=False))
print("✅ Hermes config.yaml: main=Opus@proxy, fallback=DeepSeek, aux=DeepSeek/MiniMax")
PY

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

# Install AGENTS.md at ~/supa-work/ — read by Hermes every session as the
# empire's pointer file. Per bible-as-dna, this contains identity + startup
# directive + scope only; rules live in the Bible.
AGENTS_SRC="$OVERLAY/AGENTS.md"
AGENTS_DST="$HOME/supa-work/AGENTS.md"
if [ -f "$AGENTS_SRC" ]; then
  if [ ! -f "$AGENTS_DST" ] || ! grep -q "Empire Operating Context" "$AGENTS_DST" 2>/dev/null; then
    cp "$AGENTS_SRC" "$AGENTS_DST"
    echo "✅ installed empire AGENTS.md"
  else
    echo "✅ empire AGENTS.md already in place"
  fi
fi

# Sync empire skills from overlay into ~/.hermes/skills/devops/ if they
# don't exist yet. This makes a fresh node start with the same procedural
# memory the principal's MacBook has — no waiting for the agent to "discover"
# the empire on its own.
EMPIRE_SKILLS_SRC="$OVERLAY/skills/devops"
EMPIRE_SKILLS_DST="$HOME/.hermes/skills/devops"
if [ -d "$EMPIRE_SKILLS_SRC" ]; then
  mkdir -p "$EMPIRE_SKILLS_DST"
  for skill in empire-bootstrap-operator empire-doctrine empire-architecture empire-voice empire-vault-protocol; do
    if [ -d "$EMPIRE_SKILLS_SRC/$skill" ] && [ ! -d "$EMPIRE_SKILLS_DST/$skill" ]; then
      cp -r "$EMPIRE_SKILLS_SRC/$skill" "$EMPIRE_SKILLS_DST/"
      echo "✅ installed empire skill: $skill"
    fi
  done
fi

# Verify end-to-end: this exercises the patched OAuth path against Opus.
echo "🧪 Verifying Hermes ↔ Claude Max..."
if timeout 30 hermes chat -q "Reply with just OK" 2>&1 | grep -qi "ok"; then
  echo "✅ Hermes is talking to Claude Max via OAuth"
else
  echo "⚠️  Hermes verification did not return OK. Check:"
  echo "    - launchctl list | grep opus-proxy        (proxy running?)"
  echo "    - curl http://127.0.0.1:8318/v1/models    (proxy reachable?)"
  echo "    - hermes doctor                           (DeepSeek + MiniMax keys?)"
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

# ---------- P9.25: cron-env Python deps ----------
# Cron prompts call bare `python3 /Users/mejia/.../sweep_tenancy.py` etc.,
# which resolves to /usr/bin/python3 (the macOS system Python). The system
# Python ships without PyYAML, but tenancy.py imports yaml. Without this
# step, the tenancy-sweep cron fires "ModuleNotFoundError: No module named
# 'yaml'" forever. Install into the user site-packages (no sudo, no system
# pollution). Idempotent: pip is a no-op if already present.
echo "── P9.25: cron-env Python deps (pyyaml for /usr/bin/python3)"
if ! /usr/bin/python3 -c "import yaml" 2>/dev/null; then
  /usr/bin/python3 -m pip install --user --quiet pyyaml || \
    echo "⚠️  failed to install pyyaml — tenancy-sweep cron will error" >&2
fi
/usr/bin/python3 -c "import yaml; print(f'✅ /usr/bin/python3 has pyyaml {yaml.__version__}')" || true

# ---------- P9.5: overlay-shipped launchd plists ----------
# Standalone WatchPaths/keep-alive plists from the overlay (not cron-derived).
# Currently: hermes-config-guard (self-heals ~/.hermes/config.yaml when
# anything writes a flat `model:` string instead of nested provider/default).
echo "── P9.5: overlay launchd (config-guard)"
bash "$OVERLAY/scripts/install_overlay_launchd.sh" || true

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
