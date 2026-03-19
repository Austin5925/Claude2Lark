# Deployment Changelog

## [Unreleased]

### 2026-03-19
- **Plugin**: Replaced stock `feishu` plugin with `@larksuite/openclaw-lark@2026.3.17` (full UAT support)
- **Security**: All data operations now use `user_access_token` (UAT), compliant with company policy v1.1 §5.2
- **Security**: Tenant scopes reduced to 7 (bot messaging infrastructure only, zero data access)
- **Docs**: Created `docs/lark-permission-request.md` — permission request document for boss approval

### 2026-03-18
- **Skills**: Uninstalled `lark-calendar` (third-party, contained hardcoded team data)
- **Skills**: Installed `weather` (@steipete) and `markdown-converter` (@steipete) via ClaWHub
- **Skills**: Installed `uv` on VPS for `uvx markitdown` dependency
- **Security**: Reduced Lark app-level permissions from 20 → 10 scopes (removed group, recall, pin, reaction, multi-send, sys-msg)
- **Security**: Removed optional event subscriptions (reaction, bot-added-to-group)
- **Docs**: Updated plan.md permissions checklist and skills section

### 2026-03-16
- Initial project scaffolding: Makefile, .env.example, config templates, deploy scripts
- Research completed: OpenClaw + openclaw-lark + MiniMax M2.5 architecture
- CLAUDE.md and plan.md created
