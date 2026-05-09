#!/bin/bash
# bw_sync_env.sh — Bitwarden as canonical secrets store.
#
# Pulls the "empire-env" secure note from Bitwarden, writes it to ~/.env.empire
# (chmod 600), then materializes the per-key .txt files the router code reads
# from AI-Agent-Bible/04-Shared/secrets/ (so Bitwarden — not the Bible repo —
# is the canonical source).
#
# Usage:
#   bw_sync_env.sh             # full sync (requires master password prompt)
#   bw_sync_env.sh --dry-run   # parse + print plan, no writes, no unlock
#
# Required env (export before calling, or the bootstrap installer prompts):
#   BW_CLIENTID, BW_CLIENTSECRET
#
# Side effects on success:
#   - ~/.env.empire (mode 600) with all keys
#   - AI-Agent-Bible/04-Shared/secrets/*.txt regenerated (gitignored)
#   - bw lock at exit
#   - Telegram alert "BW sync ✅"

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

ENV_FILE="${HOME}/.env.empire"
BIBLE_SECRETS="${HOME}/supa-work/AI-Agent-Bible/04-Shared/secrets"
OVERLAY_DIR="${HOME}/supa-work/Mejia-Supa-Hermes-Overlay"
TG_ALERT="${OVERLAY_DIR}/scripts/telegram_alert.sh"

cleanup() {
  local rc=$?
  # Always try to lock the vault, even on error.
  if command -v bw >/dev/null 2>&1; then
    bw lock >/dev/null 2>&1 || true
  fi
  if [[ $rc -ne 0 ]]; then
    echo "❌ bw_sync_env.sh failed (rc=$rc)" >&2
    if [[ -x "$TG_ALERT" ]]; then
      "$TG_ALERT" "BW sync ❌ rc=$rc" || true
    fi
  fi
  return $rc
}
trap cleanup EXIT
trap 'echo "ERR at line $LINENO" >&2; exit 1' ERR

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] Would: bw login --apikey, prompt master pwd, bw unlock"
  echo "[dry-run] Would: fetch secure note 'empire-env' → $ENV_FILE (chmod 600)"
  echo "[dry-run] Would: fan out per-key .txt files → $BIBLE_SECRETS/"
  echo "[dry-run] Would: bw lock; telegram alert"
  exit 0
fi

if ! command -v bw >/dev/null 2>&1; then
  echo "bitwarden-cli (bw) not installed; run: brew install bitwarden-cli" >&2
  exit 1
fi

: "${BW_CLIENTID:?BW_CLIENTID must be exported}"
: "${BW_CLIENTSECRET:?BW_CLIENTSECRET must be exported}"

# Login (idempotent — bw exits non-zero if already logged in, swallow that).
bw login --apikey >/dev/null 2>&1 || true

# Unlock — prompts master password interactively.
SESSION_KEY=$(bw unlock --raw)
export BW_SESSION="$SESSION_KEY"

# Fetch the empire-env secure note (notes field holds full env file).
NOTE_JSON=$(bw get item "empire-env")
ENV_BODY=$(printf '%s' "$NOTE_JSON" | jq -r '.notes')

if [[ -z "$ENV_BODY" || "$ENV_BODY" == "null" ]]; then
  echo "empire-env note is empty or missing 'notes' field" >&2
  exit 2
fi

umask 077
printf '%s\n' "$ENV_BODY" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "✅ wrote $ENV_FILE"

# Source it so we can fan out individual keys.
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

# Regenerate the per-key .txt files the router currently reads.
mkdir -p "$BIBLE_SECRETS"
write_key() {
  local fname="$1" varname="$2"
  local val="${!varname:-}"
  if [[ -n "$val" ]]; then
    printf '%s' "$val" > "$BIBLE_SECRETS/$fname"
    chmod 600 "$BIBLE_SECRETS/$fname"
  fi
}
write_key deepseek_api_key.txt              DEEPSEEK_API_KEY
write_key minimax_api_key.txt               MINIMAX_API_KEY
write_key openrouter_api_key.txt            OPENROUTER_API_KEY
write_key cloudflare_ai_gateway_token.txt   CLOUDFLARE_AI_GATEWAY_TOKEN
write_key cloudflare_ai_gateway_url.txt     CLOUDFLARE_AI_GATEWAY_URL
write_key nvidia_nim_flash_api_key.txt      NVIDIA_NIM_FLASH_API_KEY
write_key nvidia_nim_pro_api_key.txt        NVIDIA_NIM_PRO_API_KEY

bw lock >/dev/null 2>&1 || true
unset BW_SESSION

if [[ -x "$TG_ALERT" ]]; then
  "$TG_ALERT" "BW sync ✅ $(date -u +%FT%TZ)" || true
fi

echo "✅ bw_sync_env.sh complete"
