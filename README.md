# empire-bootstrap

One-line bootstrap for a fresh Mac → fully operational empire node.

## The one-line command

```bash
curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/install.sh -o ~/empire-install.sh && bash ~/empire-install.sh
```

> We download-then-run instead of `curl | bash` because Homebrew, `sudo`, `bw unlock`, and the Claude Code browser-auth flow all need an interactive TTY.

## Prerequisites (do these BEFORE running)

1. **Bitwarden vault populated** — see `AI-Agent-Bible/04-Shared/secrets/cred-source-map.md` for the canonical secure-note inventory. At minimum the `empire-env` note must contain the full `~/.env.empire` body.
2. **GitHub PAT** ready (classic, `repo` scope) — used during `gh auth login`.
3. **Bitwarden API key** ready (Account Settings → Security → Keys → View API Key).
4. **Bitwarden master password** memorized (you will be prompted by `bw unlock` — up to 3 attempts before the script aborts).
5. **Claude Max/Pro subscription** active on the Anthropic account you'll authorize in P5.5.

## Manual touchpoints during the run

| Phase | What you'll do |
|---|---|
| P0 | Click "Install" on the Xcode Command Line Tools GUI prompt (first run only) |
| P1 | sudo password for the Homebrew installer (first run only) |
| P3 | `gh auth login` — device-code flow in browser (first run only) |
| P5 | Paste BW `client_id`, then `client_secret` (hidden) |
| P5 | Type Bitwarden master password at the `bw unlock` prompt |
| P5.5 | Authorize Claude Code against your Max subscription in the browser (first run only) |
| P10 | `sudo` password for `pmset` (24/7 lid-closed) |

Everything else is automatic. The whole run is teed to `~/empire-bootstrap-<UTC>.log` so you can review it after.

## What it does

P0 Xcode CLT · P1 Homebrew (also persists `brew shellenv` to `~/.zprofile`) ·
P2 brew formulas + casks · P3 GitHub auth · P4 clone Bible + Overlay repos ·
P5 Bitwarden login + `bw_sync_env.sh` (3-attempt master-password retry) →
materializes `~/.env.empire` · P5.5 Claude Code CLI + `claude auth login --claudeai`
into Keychain · P6 Hermes agent (PATH-injected immediately so post-install
steps work) · P6.5 hermes-claude-auth patch (works around Anthropic's
April-2025 OAuth lockdown), sets `model.provider=anthropic` +
`model.default=anthropic/claude-opus-4-7`, clears `ANTHROPIC_API_KEY`
(Max plan has no API credits → would otherwise return HTTP 400), installs
canonical `SOUL.md`, runs a live `hermes chat` round-trip · P7 vault restore
(age-decrypt) · P8 overlay bootstrap (creates main venv, MCP skeleton,
~/.hermes/* dirs; reranker venv removed — see overlay commit history) ·
P9 launchd jobs (seeds `~/.hermes/cron/jobs.json` from this repo, then loads
all 13 com.mejia.* plists, idempotent unload-then-load) · P10 pmset 24/7
(verifies `sleep=0` actually applied; warns if not) · P11 smoke test ·
P12 Telegram "Mac bootstrap ✅".

## Verify after run

The bootstrap runs `smoke_test.sh` automatically as P11. For a deeper
post-hoc audit any time:

```bash
bash ~/supa-work/empire-bootstrap/scripts/verify.sh
# or remote:
curl -fsSL https://raw.githubusercontent.com/MrDadaMon/empire-bootstrap/main/scripts/verify.sh | bash
```

`verify.sh` checks every phase against the explainer pack's ground truth
and exits non-zero on any failure with a remediation hint per check.

## Logs

- `~/empire-bootstrap-<UTC>.log` — full transcript of the most recent install run
- `~/Library/Logs/com.mejia/*.{out,err}.log` — per-launchd-job output
- `~/.hermes/logs/gateway.log` — Hermes gateway service

## Linux / VPS support

`install-linux.sh` is TODO. The current script is macOS-only (relies on
Homebrew, Keychain, launchd, pmset). Architecture is documented in the
explainer pack (`04-three-device-topology.md`). Until the Linux sibling
lands, VPS provisioning is manual.

## Related

- `AI-Agent-Bible/03-Ai-Agent-Onboarding/05-Fresh-Machine-Day-1.md`
- `AI-Agent-Bible/02-Operating-Methodology/04-Claude-Code-Ops/bootstrap-registry.md`
- `AI-Agent-Bible/04-Shared/secrets/cred-source-map.md`
- `Mejia-Supa-Hermes-Overlay/SOUL.md` (canonical empire personality)
- `Mejia-Supa-Hermes-Overlay/profiles/hermes-bootstrap-answers.yaml`
