#!/bin/bash
# smoke_test.sh — verify post-bootstrap empire health.
# Exits non-zero on any failure. Prints ✅/❌ per check.
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "❌ $1"; FAIL=$((FAIL+1)); }

# 1. ~/.env.empire exists and is mode 600
if [[ -f "$HOME/.env.empire" ]]; then
  mode=$(stat -f '%Lp' "$HOME/.env.empire" 2>/dev/null || stat -c '%a' "$HOME/.env.empire")
  if [[ "$mode" == "600" ]]; then
    ok "~/.env.empire exists (mode 600)"
  else
    bad "~/.env.empire wrong mode: $mode"
  fi
else
  bad "~/.env.empire missing"
fi

# 2. launchd jobs (expect 13)
loaded=$(launchctl list 2>/dev/null | grep -c -E 'empire|mejia|hermes' || true)
if [[ "$loaded" -ge 13 ]]; then
  ok "launchd jobs registered ($loaded ≥ 13)"
else
  bad "launchd jobs registered: $loaded (expected 13)"
fi

# 3. age decrypt dry-run
if command -v age >/dev/null 2>&1 && [[ -f "$HOME/.config/age/key.txt" ]]; then
  ok "age key present"
else
  bad "age or age key missing"
fi

# 4. Telegram alert fires
if [[ -x "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/telegram_alert.sh" ]]; then
  if "$HOME/supa-work/Mejia-Supa-Hermes-Overlay/scripts/telegram_alert.sh" "smoke_test ping" >/dev/null 2>&1; then
    ok "telegram alert fired"
  else
    bad "telegram alert failed"
  fi
else
  bad "telegram_alert.sh missing or not executable"
fi

# 5. Both repos cloned
[[ -d "$HOME/supa-work/AI-Agent-Bible" ]] && ok "AI-Agent-Bible cloned" || bad "AI-Agent-Bible missing"
[[ -d "$HOME/supa-work/Mejia-Supa-Hermes-Overlay" ]] && ok "Overlay cloned" || bad "Overlay missing"

# 6. Hermes installed
if command -v hermes >/dev/null 2>&1 || python3 -c "import hermes" 2>/dev/null; then
  ok "hermes installed"
else
  bad "hermes not installed"
fi

echo "──"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
