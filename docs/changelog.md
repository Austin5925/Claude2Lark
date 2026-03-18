# Deployment Changelog

## [Unreleased]

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
