# empire-bootstrap

One-line bootstrap for a fresh Mac → fully operational empire.

## The one-line command

```bash
curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/install.sh -o ~/empire-install.sh && bash ~/empire-install.sh
```

> We download-then-run instead of `curl | bash` because Homebrew and `sudo` need interactive stdin.

## Prerequisites (do these BEFORE running)

1. **Bitwarden vault populated** — see `AI-Agent-Bible/04-Shared/secrets/cred-source-map.md`
   for the canonical secure-note inventory. At minimum the `empire-env` note
   must contain the full `~/.env.empire` body (all `export` lines).
2. **GitHub PAT** ready (classic, `repo` scope) — used during `gh auth login`.
3. **Bitwarden API key** ready (Account Settings → Security → Keys → View API Key).
4. **Bitwarden master password** memorized (you will be prompted by `bw unlock`).

## Manual touchpoints during the run

| Phase | What you'll do |
|---|---|
| P0 | Click "Install" on the Xcode Command Line Tools GUI prompt |
| P3 | `gh auth login` — device-code flow in browser |
| P5 | Paste BW `client_id`, then `client_secret` (hidden) |
| P5 | Type Bitwarden master password at the `bw unlock` prompt |
| P5.5 | `claude auth login --claudeai` — browser flow to authorize your Claude Max/Pro subscription (only on first run; skipped if Keychain already has it) |
| P10 | `sudo` password for `pmset` (24/7 lid-closed) |

Everything else is automatic.

## What it does

P0 Xcode CLT · P1 Homebrew · P2 brew formulas + casks · P3 GitHub auth ·
P4 clone Bible + Overlay repos · P5 Bitwarden login + `bw_sync_env.sh` →
materializes `~/.env.empire` and per-key secrets · P5.5 Claude Code CLI +
Max-subscription OAuth into Keychain · P6 Hermes agent ·
P6.5 hermes-claude-auth patch (works around Anthropic's April-2025 OAuth
lockdown) + sets `model.provider=anthropic`, `model.default=anthropic/claude-opus-4-7`,
clears `ANTHROPIC_API_KEY` (Max plan has no API credits), and verifies with
a live `hermes chat` round-trip · P7 vault restore (age-decrypt) ·
P8 reranker venv · P9 launchd jobs (13) · P10 pmset 24/7 · P11 smoke test ·
P12 Telegram "Mac bootstrap ✅".

## Verify after run

```bash
bash ~/supa-work/Mejia-Supa-Hermes-Overlay/scripts/smoke_test.sh
```

Should print `✅` for: env file, launchd jobs, age dry-run, telegram, repos, hermes.

## Related

- `AI-Agent-Bible/03-Ai-Agent-Onboarding/05-Fresh-Machine-Day-1.md`
- `AI-Agent-Bible/02-Operating-Methodology/04-Claude-Code-Ops/bootstrap-registry.md`
- `AI-Agent-Bible/04-Shared/secrets/cred-source-map.md`
