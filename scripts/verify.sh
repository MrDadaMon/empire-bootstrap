#!/bin/bash
# verify.sh — post-hoc empire bootstrap audit.
#
# Usage:
#   bash ~/supa-work/empire-bootstrap/scripts/verify.sh
#   curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/scripts/verify.sh | bash
#
# Exits 0 if every phase verifies, non-zero if any check fails. Prints a
# board of ✅/❌ with the specific path or value found, and a remediation
# hint for each failure.
#
# This is the same audit any operator (human or agent) should run any time
# the empire feels off. It checks ALL 13 phases against the ground truth
# documented in the empire-bootstrap-explainer pack.
set -u

PASS=0
FAIL=0
ok()  { printf "✅ %-40s %s\n" "$1" "${2:-}"; PASS=$((PASS+1)); }
bad() { printf "❌ %-40s %s\n" "$1" "${2:-MISSING}"; FAIL=$((FAIL+1)); }

check() {
  local label="$1"; shift
  local result
  result=$(eval "$@" 2>/dev/null || true)
  if [ -n "$result" ]; then ok "$label" "$result"; else bad "$label"; fi
}

echo "── Empire bootstrap verification ──"

# P0
check "P0 Xcode CLT"                     "xcode-select -p"
# P1
check "P1 Homebrew"                      "command -v brew"
check "P1 brew shellenv in .zprofile"    "grep -l 'brew shellenv' \$HOME/.zprofile 2>/dev/null && echo present"
# P2 formulae
for f in git gh age bw jq python3 node rg; do
  check "P2 brew: $f"                    "command -v $f"
done
# P2 casks
for app in Ghostty Raycast Rectangle Bitwarden; do
  check "P2 cask: $app"                  "ls -d /Applications/$app.app 2>/dev/null"
done
# P3
check "P3 gh authenticated"              "gh auth status 2>&1 | grep 'Logged in' | head -1"
# P4
check "P4 ~/supa-work"                   "ls -d \$HOME/supa-work"
check "P4 AI-Agent-Bible"                "ls -d \$HOME/supa-work/AI-Agent-Bible"
check "P4 Mejia-Supa-Hermes-Overlay"     "ls -d \$HOME/supa-work/Mejia-Supa-Hermes-Overlay"
# P5
check "P5 ~/.env.empire (mode 600)"      "stat -f '%Lp' \$HOME/.env.empire 2>/dev/null | grep -x 600 && echo 600"
check "P5 ~/.zshrc sources env.empire"   "grep -l '.env.empire' \$HOME/.zshrc 2>/dev/null && echo yes"
# P5.5
check "P5.5 claude CLI"                  "command -v claude"
if security find-generic-password -s 'Claude Code-credentials' -w >/dev/null 2>&1; then
  ok "P5.5 Keychain Claude creds" "PRESENT"
else
  bad "P5.5 Keychain Claude creds" "run: claude auth login --claudeai"
fi
# P6
check "P6 hermes CLI"                    "command -v hermes"
check "P6 ~/.hermes dir"                 "ls -d \$HOME/.hermes"
check "P6 ~/.hermes/.env"                "ls \$HOME/.hermes/.env"
# P6.5
check "P6.5 hermes-claude-auth patch"    "ls \$HOME/.hermes/patches/anthropic_billing_bypass.py"
check "P6.5 sitecustomize hook"          "ls \$HOME/.hermes/hermes-agent/venv/lib/python*/site-packages/sitecustomize.py 2>/dev/null | head -1"
check "P6.5 anthropic provider"          "hermes config show 2>/dev/null | grep -E 'Model:.*anthropic' | head -1"
check "P6.5 model=opus-4-7"              "hermes config show 2>/dev/null | grep -i 'opus' | head -1"
if grep -q '^ANTHROPIC_API_KEY=.\+' "$HOME/.hermes/.env" 2>/dev/null; then
  bad "P6.5 ANTHROPIC_API_KEY cleared" "still set — Max plan has no API credits, will 400. Remove from ~/.hermes/.env"
else
  ok "P6.5 ANTHROPIC_API_KEY cleared" "ok"
fi
check "P6.5 SOUL.md installed"           "grep -l 'Empire SOUL' \$HOME/.hermes/SOUL.md 2>/dev/null && echo present"
# P7
check "P7 mejia-vault-encrypted clone"   "ls -d \$HOME/supa-work/mejia-vault-encrypted"
check "P7 Mejia-Vault extracted"         "ls -d \$HOME/supa-work/Mejia-Vault"
check "P7 age key"                       "ls \$HOME/.config/age/key.txt"
# P8 (overlay bootstrap marker)
check "P8 ~/.hermes/bootstrap.complete"  "ls \$HOME/.hermes/bootstrap.complete"
# P9
LOADED=$(launchctl list 2>/dev/null | awk '$3 ~ /^com\.mejia\./ {n++} END{print n+0}')
if [ "$LOADED" -ge 13 ]; then
  ok "P9 launchd com.mejia.* jobs" "$LOADED loaded"
else
  bad "P9 launchd com.mejia.* jobs" "only $LOADED loaded (expected ≥13). Re-run: bash \$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/install_launchd_jobs.sh"
fi
# P10 — check the AC ("charger") profile specifically. macOS pmset has separate
# AC/Battery/UPS profiles; -c sets AC. The plain `pmset -g` shows whichever is
# currently active, which false-fails on laptops running on battery during the check.
SLEEP_VAL=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{ac=1; next} /^[A-Z]/{ac=0} ac && /^ sleep/ {print $2; exit}')
if [ "$SLEEP_VAL" = "0" ]; then
  ok "P10 pmset (AC) sleep=0" "ok"
else
  bad "P10 pmset (AC) sleep=0" "AC profile sleep='$SLEEP_VAL'. Run: sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1"
fi
# P12
check "P12 telegram_alert.sh"            "ls \$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/telegram_alert.sh"

echo ""
echo "──"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
