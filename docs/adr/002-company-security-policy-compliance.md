# ADR-002: Company AI Agent Security Policy Compliance

## Status
Accepted

## Context
Company issued "个人 AI Agent 使用政策 v1.1" on 2026-03-17, governing personal AI Agent usage on company Lark accounts.

## Policy Requirements & Implementation

| Policy Requirement | Implementation | Status |
|---|---|---|
| 2.1 个人专属使用（写死白名单） | `dmPolicy: "allowlist"` + `dmAllowlist` in config | ✅ |
| 2.1 禁止共用 | Single Open ID in allowlist | ✅ |
| 2.2 禁止外部接入 | Only Feishu channel enabled, no Telegram/Discord/etc | ✅ |
| 2.2 禁止暴露给第三方 | Gateway binds loopback only, UFW firewall enabled | ✅ |
| 2.3 数据安全（机密数据） | BOOTSTRAP.md + memory enforce confidentiality | ✅ |
| 3.2 最小权限 Skill | `tools.perm: false` (disabled permission modification) | ✅ |
| 4.1 单一平台 | Only Lark channel, `groupPolicy: "disabled"` | ✅ |
| 5.2 User Token | `uat.enabled: true` (mirrors user's personal permissions) | ✅ |

## Security Hardening Applied

1. **Network**: UFW firewall enabled (deny all inbound except SSH)
2. **Gateway**: `bind: "loopback"` + auth token
3. **Access control**: `dmPolicy: "allowlist"` with hardcoded user Open ID
4. **Permissions tool disabled**: `tools.perm: false` prevents permission/sharing changes
5. **Agent prompt**: BOOTSTRAP.md enforces confirmation before writes, data confidentiality
6. **User Token**: UAT mode mirrors user's personal Lark permissions (least privilege)

## Pending

- Get girlfriend's Lark Open ID to set in allowlist (currently placeholder)
- Complete Lark Induction training per policy 5.1
- Formal policy sign-off
