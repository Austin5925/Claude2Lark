# CLAUDE.md

## Project Overview

**Claude2Lark** — 在 Hetzner VPS 上部署 OpenClaw + openclaw-lark 插件，接入 MiniMax M2.5，让用户在 Lark（国际版）中与 AI Agent 对话，操作文档/多维表格/日历/任务等。

**Tech Stack:** OpenClaw Gateway (Node.js 22) + openclaw-lark plugin + MiniMax M2.5 API + Lark Open Platform

## Absolute Rules

### NEVER

- Never commit secrets (`.env`, API keys, App Secret) to git
- Never run `git add -A` or `git add .` — stage specific files only
- Never use `--force`, `--no-verify`, or `--amend` unless explicitly asked
- Never modify `main` branch directly — always branch, always PR
- Never assume state — verify before acting (`git status`, `openclaw status`, etc.)
- Never generate code before plan is approved — output `[PLAN]` first, wait for explicit approval
- Never hardcode credentials in config files — use environment variable references (`${VAR}`)

### ALWAYS

- Always output `[PLAN]` before implementation and wait for approval
- Always create a branch before making modifications
- Always test after changes (lint, build, connectivity check, etc.)
- Always use Conventional Commits: `<type>: <description>` (<100 chars)
  - Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `security`
- Always commit, push, and `make deploy` after confirmed changes (per user's principle #5)
- Always keep this CLAUDE.md and plan.md in sync with project state
- Always store deployment credentials in `.env` (chmod 600, gitignored)

## Architecture

```
Lark Client → Lark Open Platform (WebSocket/Webhook)
    → OpenClaw Gateway (Hetzner VPS, :18789)
        → openclaw-lark plugin (98 Lark tool actions)
        → MiniMax M2.5 (api.minimax.io/v1, OpenAI-compatible)
```

### Key Components

| Component | Role | Config Location |
|-----------|------|-----------------|
| OpenClaw Gateway | Agent runtime, channel management | `~/.openclaw/openclaw.json` |
| openclaw-lark | Lark channel + 98 tool actions | Bundled in OpenClaw |
| MiniMax M2.5 | LLM backend (tool calling, reasoning) | Provider config in openclaw.json |
| Lark App | Bot identity, permissions, events | open.larksuite.com |
| systemd | Process management | `/etc/systemd/system/openclaw.service` |

### Critical Config

- **Lark domain:** Must be `"lark"` (NOT `"feishu"`) — target is Lark international
- **App created at:** `https://open.larksuite.com/app` (NOT `open.feishu.cn`)
- **Connection mode:** Try WebSocket first; fallback to Webhook if Lark intl doesn't support WS
- **MiniMax API:** `https://api.minimaxi.com/anthropic` (Anthropic-compatible, Coding Plan key `sk-cp-`)

## Commands

```bash
# Deployment
make deploy              # Full deploy: validate → push config → restart service

# OpenClaw management (on VPS)
openclaw gateway start   # Start gateway
openclaw gateway status  # Check status
openclaw logs --follow   # Tail logs
openclaw doctor          # Health check
openclaw security audit --deep  # Security audit

# Service management (on VPS)
sudo systemctl status openclaw
sudo systemctl restart openclaw
journalctl -u openclaw -f

# Local development
git checkout -b feat/description  # Always branch first
git add <specific-files>          # Never git add -A
```

## File Structure

```
Claude2Lark/
├── CLAUDE.md              # This file — AI development context
├── plan.md                # Implementation plan with task checklist
├── research.md            # Technical research findings
├── Makefile               # Deployment automation (make deploy)
├── .env.example           # Template for environment variables
├── .gitignore             # Excludes .env, secrets, local state
├── configs/
│   └── openclaw.json      # OpenClaw config template (no secrets)
├── scripts/
│   └── deploy.sh          # Deployment script called by Makefile
├── docs/
│   ├── adr/               # Architecture Decision Records
│   └── changelog.md       # Deployment changelog
└── lark-claude-bot-guide.md  # Legacy reference (original pre-research)
```

## Lark-Specific Notes

- **Lark vs Feishu:** Same API spec, different domains. Apps are NOT cross-compatible.
- **WebSocket uncertainty:** Some community reports claim Lark intl doesn't support WS long-connection. Test first, have Webhook fallback ready.
- **Required app permissions:** 20 app-level scopes + 66 user-level scopes (see research.md section 5.5)
- **openclaw-lark tools:** 98 actions across IM, Docs, Bitable (27 CRUD actions), Sheets, Calendar, Tasks, Drive, Wiki, Search

## MiniMax M2.5 Notes

- **Pricing:** Coding Plan 月订阅（非按量计费）
- **Tool calling:** BFCL 76.8% (outperforms Claude's 63.3%)
- **OpenClaw model ID:** `minimax/MiniMax-M2.5`
- **API endpoint:** `https://api.minimaxi.com/anthropic` (国内平台，Anthropic 兼容)
- **Key prefix:** `sk-cp-` (Coding Plan 专用)
- **No vision:** Text-only input — cannot process images sent in Lark
