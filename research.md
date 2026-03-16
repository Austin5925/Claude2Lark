# OpenClaw + Lark + MiniMax M2.5 深度研究报告

> 研究日期：2026-03-16
> 目标：在 Hetzner VPS 上部署 OpenClaw，通过 openclaw-lark 插件接入 Lark（国际版），使用 MiniMax M2.5 作为 LLM 后端，实现文档/多维表格/日历/任务等 Agent 操作。

---

## 一、最终方案概览

```
女朋友的 Lark 客户端
       ↕ 发消息 / 收回复
Lark Open Platform（WebSocket 长连接 或 Webhook）
       ↕ 事件推送 / API 调用
openclaw-lark 插件（98 个 Lark 工具动作）
       ↕
OpenClaw Gateway（Hetzner VPS）
       ↕ OpenAI-compatible API
MiniMax M2.5（api.minimax.io）
```

| 维度 | 选择 | 理由 |
|------|------|------|
| AI Agent 平台 | OpenClaw | 316K stars，开箱即用，Lark 官方插件 |
| Lark 集成 | openclaw-lark | Lark 官方团队维护，98 个工具动作 |
| LLM 后端 | MiniMax M2.5 | $0.30/$1.20 per M tokens，工具调用 BFCL 76.8% |
| 部署 | Hetzner VPS | 已有，CX22 ~$4.50/月足够 |
| 月费用预估 | **~$1.50-3/月**（LLM API） + $4.50（VPS） | 日均50次对话 |

---

## 二、MiniMax M2.5 详细调研

### 2.1 模型概况

- **发布：** 2026年2月12日
- **架构：** Mixture of Experts (MoE) — 230B 总参数，仅 10B 活跃
- **上下文窗口：** ~205K tokens
- **最大输出：** ~196K tokens
- **输入模态：** 仅文本（无视觉/音频）
- **推理能力：** Extended thinking / chain-of-thought（类似 Claude 的 extended thinking）
- **许可证：** MIT — 完全开源，可在 HuggingFace 获取

### 2.2 定价（关键优势）

| 模型 | 输入 (per M tokens) | 输出 (per M tokens) | 相对于 Claude Sonnet |
|------|--------------------|--------------------|---------------------|
| **MiniMax M2.5** | **$0.30** | **$1.20** | **1x（基准）** |
| MiniMax M2.5-highspeed | $0.60 | $2.40 | 2x |
| Claude Sonnet 4.6 | $3.00 | $15.00 | **10-12x 更贵** |
| Claude Opus 4.6 | $15.00 | $75.00 | **63x 更贵** |
| Claude Haiku 4 | $0.25 | $1.25 | ~同等 |

**Prompt Caching（自动，无需配置）：**
- Cache 读取：$0.03/M tokens
- Cache 写入：$0.375/M tokens

**月费用估算（日均50次对话）：** ~$1.50-3/月

### 2.3 工具调用能力（Agent 核心）

**MiniMax M2.5 在工具调用上优于 Claude：**

| 基准 | MiniMax M2.5 | Claude Opus 4.6 |
|------|-------------|-----------------|
| BFCL（Berkeley 函数调用） | **76.8%** | 63.3% |
| SWE-Bench Verified | **80.2%** | 78.9% |
| Multi-SWE-Bench | **51.3%** | 50.3% |

**工具调用特性：**
- 标准 OpenAI 格式的 `tools` 数组和 JSON Schema 参数
- 交错思考（Interleaved Thinking）— 每轮工具交互前自动推理
- 支持并行工具调用（实测提速 37%）
- 完整的多轮工具使用支持

### 2.4 API 接入

**OpenAI 兼容 API：**
- **Base URL：** `https://api.minimax.io/v1`
- **认证：** API Key via header
- **获取 API Key：** `platform.minimax.io` 开发者面板
- **也提供 Anthropic 兼容端点：** `https://api.minimax.io/anthropic`

**可用模型：**

| 模型 ID | 速度 | 适用场景 |
|---------|------|---------|
| `MiniMax-M2.5` | ~50 tok/s | 标准使用，推荐 |
| `MiniMax-M2.5-highspeed` | ~100 tok/s | 需要快速响应 |

### 2.5 OpenClaw 原生支持 MiniMax

OpenClaw **原生支持** MiniMax 作为 Provider，有官方文档页面 `docs.openclaw.ai/providers/minimax`。

**配置方式一 — OAuth（推荐）：**
```bash
openclaw plugins enable minimax
openclaw onboard --auth-choice minimax-portal
```

**配置方式二 — API Key：**
```bash
openclaw configure
# 选择 Model/auth -> MiniMax M2.5
# 设置 MINIMAX_API_KEY
```

**配置方式三 — 手动配置（openclaw.json）：**
```json5
{
  "models": {
    "mode": "merge",
    "providers": {
      "minimax": {
        "baseUrl": "https://api.minimax.io/v1",
        "apiKey": "${MINIMAX_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "MiniMax-M2.5",
            "name": "MiniMax M2.5",
            "reasoning": true,
            "input": ["text"],
            "cost": { "input": 0.3, "output": 1.2 },
            "contextWindow": 204800,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "minimax/MiniMax-M2.5"
      }
    }
  }
}
```

---

## 三、Lark（国际版）支持详细调研

### 3.1 ⚠️ 关键问题：Lark 与 Feishu 的区别

| 方面 | Feishu（国内版） | Lark（国际版） |
|------|-----------------|---------------|
| 开发者控制台 | `https://open.feishu.cn/app` | `https://open.larksuite.com/app` |
| API Base URL | `https://open.feishu.cn/open-apis` | `https://open.larksuite.com/open-apis` |
| API 规范 | 相同 | 相同 |
| 应用互通 | ❌ 不能用 Lark 应用 | ❌ 不能用 Feishu 应用 |
| SDK 支持 | 所有官方 SDK | 所有官方 SDK |
| 文档语言 | 中文优先 | 英文可用 |

**关键约束：** Feishu 应用和 Lark 应用**互不兼容**。必须在对应平台创建应用。

### 3.2 各组件 Lark 支持情况逐项调研

#### ① OpenClaw 内置 Feishu Channel → ✅ 支持 Lark

OpenClaw 官方 Feishu Channel（`extensions/feishu/`）**明确支持 Lark 国际版**。

配置方式：设置 `domain: "lark"`
```json5
{
  "channels": {
    "feishu": {
      "domain": "lark",  // 关键：默认是 "feishu"，必须改为 "lark"
      "appId": "cli_xxx",
      "appSecret": "xxx"
    }
  }
}
```

- 官方文档注明：`channels.feishu.domain` — API domain (`feishu` or `lark`), default: `feishu`
- Lark 租户必须在 `https://open.larksuite.com/app` 创建应用
- 所有功能（DM、群组、流式卡片、多账号、ACP 会话）在两个域名上**表现一致**

#### ② openclaw-lark 插件 (`larksuite/openclaw-lark`) → ✅ 支持 Lark

从配置 Schema（`config-schema.ts`）可见：
- `domain` 字段：接受 `"feishu"` | `"lark"` | 自定义 URL
- 该插件名称本身就叫 "openclaw-**lark**"
- Lark 开放平台团队维护，Lark 支持是第一优先级

```json5
{
  "channels": {
    "feishu": {
      "domain": "lark",           // Lark 国际版
      "connectionMode": "websocket",
      "appId": "cli_xxx",
      "appSecret": "xxx"
    }
  }
}
```

#### ③ @larksuiteoapi/node-sdk → ✅ 完整 Lark 支持

官方 SDK 源码确认：

```typescript
export enum Domain {
    Feishu,  // → https://open.feishu.cn
    Lark,    // → https://open.larksuite.com
}

// 使用方式
const client = new lark.Client({
    appId: 'cli_xxx',
    appSecret: 'xxx',
    domain: lark.Domain.Lark,  // ← 明确支持
});
```

WSClient 同样支持 `Domain.Lark`，无域名限制。

#### ④ WebSocket 长连接在 Lark 国际版 → ⚠️ 存在争议

**这是最关键的不确定性：**

| 来源 | 观点 |
|------|------|
| `abca12a/lark-openclaw` | ❌ 声称 Lark 仅支持 HTTP Webhook，不支持 WebSocket |
| AstrBot / LangBot 文档 | ❌ 推荐 Lark 用户选择 webhook |
| DeepWiki 分析 | ✅ 称两者协议实现相同，WebSocket 对两者都可用 |
| `@larksuiteoapi/node-sdk` | ✅ WSClient 无域名限制 |
| OpenClaw 官方文档 | ✅ 默认 WebSocket，未标注 Lark 特殊情况 |

**结论：先尝试 WebSocket（简单，无需公网 URL），失败则回退到 Webhook。**

如果需要 Webhook：
- Hetzner VPS 本身即可作为公网端点
- 或通过 Cloudflare Tunnel / ngrok 暴露
- OpenClaw 配置：`connectionMode: "webhook"`

#### ⑤ 社区插件 Lark 支持情况

| 插件 | Lark 支持 | 说明 |
|------|----------|------|
| **larksuite/openclaw-lark**（官方） | ✅ 明确支持 | `domain: "lark"` |
| **xzq-xu/openclaw-plugin-feishu** | ✅ 明确支持 | `domain` 字段接受 `"feishu"` 或 `"lark"` |
| **ogromwang/openclaw-feishu** | ✅ 明确支持 | `domain: "feishu" \| "lark"` |
| **gcmsg/openclaw-feishu** | ⚠️ 未明确 | README 仅提及 feishu.cn，但底层用 SDK，可能可行 |
| **abca12a/lark-openclaw** | ✅ Lark 专用 | 专为 Lark 国际版构建，但仅 webhook 模式 |

**推荐：使用官方 `larksuite/openclaw-lark`**，Lark 支持最可靠。

### 3.3 Lark 应用创建关键差异

在 Lark 国际版创建应用时：
1. 必须访问 **`https://open.larksuite.com/app`**（不是 `open.feishu.cn`）
2. 界面为英文
3. 权限 scope ID 与 Feishu 相同
4. Bot 能力启用流程相同
5. 事件订阅流程相同
6. **应用审核可能更快**（国际版审核流程通常较简化）

---

## 四、OpenClaw 平台详细调研

### 4.1 什么是 OpenClaw

- **定位：** 自托管的开源个人 AI 助手网关
- **创建者：** Peter Steinberger（steipete），近期被 OpenAI 聘用
- **当前状态：** 316K GitHub stars，MIT 许可，非常活跃
- **支持 20+ 消息平台**（Lark、Telegram、Discord、WhatsApp、Signal 等）
- **支持 30+ LLM 后端**（包括 MiniMax、Claude、GPT、Gemini、Ollama 等）

### 4.2 架构

```
┌─────────────────────────────────────────────┐
│            OpenClaw Gateway (VPS)            │
│                                             │
│  ┌───────────┐  ┌──────────────────────┐   │
│  │ Feishu    │  │    Agent Runtime     │   │
│  │ Channel   │  │  ┌────────────────┐  │   │
│  │ (Lark)    │←→│  │ MiniMax M2.5   │  │   │
│  │           │  │  │ Provider       │  │   │
│  │ 98 Tools  │  │  └────────────────┘  │   │
│  └───────────┘  │  ┌────────────────┐  │   │
│                 │  │ Skill Engine   │  │   │
│  ┌───────────┐  │  │ (ClawHub)      │  │   │
│  │ WebSocket │  │  └────────────────┘  │   │
│  │ API       │  └──────────────────────┘   │
│  │ :18789    │                             │
│  └───────────┘  ┌──────────────────────┐   │
│                 │ Control UI (Web)     │   │
│                 └──────────────────────┘   │
└─────────────────────────────────────────────┘
```

**核心组件：**
- **Gateway** — 单个长驻进程，管理消息连接和状态
- **WebSocket API** — `ws://127.0.0.1:18789`
- **Control UI** — Web 管理面板 `http://127.0.0.1:18789/`
- **OpenAI 兼容 API** — `/v1/chat/completions`
- **健康检查** — `/healthz`、`/readyz`

### 4.3 系统要求

| 项目 | 最低 | 推荐 |
|------|------|------|
| CPU | 1 vCPU | 2 vCPU |
| 内存 | 1 GB | 2-4 GB |
| 磁盘 | ~500 MB | ~5 GB |
| Runtime | Node.js >= 22 | Node.js 22 LTS |
| 推荐 VPS | CX22（~$4.50/月） | CX22 |

### 4.4 安全模型

- **信任模型：** 个人助手，非多租户
- **Gateway 认证：** Token / Password / Trusted-proxy
- **DM 访问控制：** Pairing（配对码）/ Allowlist / Open / Disabled
- **沙箱：** 可选 Docker 隔离（模式：off / non-main / all）
- **安全审计：** `openclaw security audit --deep`
- **文件权限：** `~/.openclaw/` → 700，`openclaw.json` → 600

### 4.5 模型故障转移

```json5
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "minimax/MiniMax-M2.5",
        "fallbacks": ["minimax/MiniMax-M2.5-highspeed"]
      }
    }
  }
}
```

- 速率限制处理：指数退避 1min → 5min → 25min → 1hr
- 密钥轮换支持
- 费用追踪：`/status`、`/usage full`

---

## 五、openclaw-lark 插件详细调研

### 5.1 基本信息

| 项目 | 值 |
|------|------|
| 仓库 | https://github.com/larksuite/openclaw-lark |
| npm 包 | `@larksuite/openclaw-lark` |
| 最新版本 | 2026.3.14 |
| 维护者 | Lark/Feishu 开放平台团队（ByteDance） |
| Stars | 906 |
| 许可证 | MIT |
| 依赖 | `@larksuiteoapi/node-sdk` ^1.59.0 |
| Lark 支持 | ✅ `domain: "lark"` |

### 5.2 完整工具清单（98 个动作）

#### 即时通讯 (IM) — 4 工具

| 工具 | 动作 |
|------|------|
| `feishu_im_user_message` | 发送、回复消息 |
| `feishu_im_user_get_messages` | 读取消息历史 |
| `feishu_im_user_search_messages` | 搜索消息 |
| `feishu_im_user_fetch_resource` | 下载图片/文件 |

#### 文档 (Docs) — 5 工具

| 工具 | 动作 |
|------|------|
| `feishu_create_doc` | 创建文档 |
| `feishu_fetch_doc` | 读取文档内容 |
| `feishu_update_doc` | 更新文档 |
| `feishu_doc_comments` | 列表/创建/修改评论 |
| `feishu_doc_media` | 下载/插入媒体 |

#### 多维表格 (Bitable) — 5 工具，27 个动作

| 工具 | 动作 |
|------|------|
| `feishu_bitable_app` | create, get, list, patch, copy |
| `feishu_bitable_app_table` | create, list, patch, delete, batch_create, batch_delete |
| `feishu_bitable_app_table_record` | **create, list, update, delete, batch_create, batch_update, batch_delete** |
| `feishu_bitable_app_table_field` | create, list, update, delete |
| `feishu_bitable_app_table_view` | create, get, list, patch, delete |

**支持 27 种字段类型：** Text, Number, SingleSelect, MultiSelect, DateTime, User, URL, Attachment, Checkbox, Progress, Currency, Phone, Email, Location, Formula, Lookup, AutoNumber, CreatedTime, ModifiedTime, CreatedBy, ModifiedBy, Barcode 等。

**高级筛选：** 10 个运算符 — is, isNot, contains, isEmpty, isGreater, isLess 等。

**约束：** 每批最多 500 条记录 / 每表 20,000 条 / 300 字段 / 200 视图 / 同表不支持并发写入。

#### 电子表格 (Sheets) — 1 工具

| 工具 | 动作 |
|------|------|
| `feishu_sheet` | info, read, write, append, find, create, export |

#### 日历 (Calendar) — 4 工具

| 工具 | 动作 |
|------|------|
| `feishu_calendar_calendar` | CRUD 日历 |
| `feishu_calendar_event` | CRUD 事件 |
| `feishu_calendar_event_attendee` | 管理参会者 |
| `feishu_calendar_freebusy` | 查询空闲/忙碌 |

#### 任务 (Tasks) — 4 工具

| 工具 | 动作 |
|------|------|
| `feishu_task_task` | 创建/查询/更新/完成任务 |
| `feishu_task_tasklist` | 任务列表管理 |
| `feishu_task_comment` | 任务评论 |
| `feishu_task_subtask` | 子任务管理 |

#### 云盘 (Drive) — 1 工具

| 工具 | 动作 |
|------|------|
| `feishu_drive_file` | list, get_meta, copy, move, delete, upload, download |

#### 知识库 (Wiki) — 2 工具

| 工具 | 动作 |
|------|------|
| `feishu_wiki_space` | 列表/获取/创建空间 |
| `feishu_wiki_space_node` | 列表/获取/创建/移动/复制节点 |

#### 搜索/群组/通讯录 — 4 工具

| 工具 | 动作 |
|------|------|
| `feishu_search_doc_wiki` | 搜索文档和知识库 |
| `feishu_search_user` | 搜索用户 |
| `feishu_chat` | 搜索群组、获取群组信息 |
| `feishu_chat_members` | 列出群成员 |

#### OAuth — 1 工具

| 工具 | 动作 |
|------|------|
| OAuth device-flow | 用户级授权、批量授权 |

### 5.3 内置 Skills（9 个）

| Skill | 用途 |
|-------|------|
| `feishu-bitable` | 多维表格操作指导 |
| `feishu-calendar` | 日历操作指导 |
| `feishu-channel-rules` | 渠道规则配置 |
| `feishu-create-doc` | 文档创建流程 |
| `feishu-fetch-doc` | 文档读取流程 |
| `feishu-im-read` | IM 消息读取 |
| `feishu-task` | 任务管理流程 |
| `feishu-troubleshoot` | 故障排查 |
| `feishu-update-doc` | 文档更新流程 |

### 5.4 交互特性

- **流式卡片输出** — CardKit v2 实时更新，状态：Thinking → Generating → Complete
- **消息类型** — 入站：文本/富文本/图片/文件/音频/视频/贴纸；出站：文本/图片/文件/交互卡片
- **中断检测** — 用户发新消息时优雅中断生成
- **消息去重** — 默认 12h TTL，5000 条上限

### 5.5 Lark 应用权限要求

**必需的应用级权限（20 个 scope）：**
`im:message.group_at_msg:readonly`, `im:message.p2p_msg:readonly`, `im:message:send_as_bot`, `im:message:readonly`, `im:message:update`, `im:message:recall`, `im:resource`, `im:chat:read`, `im:chat:update`, `im:message.pins:read/write_only`, `im:message.reactions:read/write_only`, `im:message:send_multi_users`, `im:message:send_sys_msg`, `cardkit:card:write`, `cardkit:card:read`, `application:application:self_manage`, `contact:contact.base:readonly`, `docx:document:readonly`

**用户级权限（66 个 scope）：** 按工具动作按需授权。

### 5.6 已知限制

- 同一表格不支持并发写入（需串行化 + 0.5-1s 延迟）
- Webhook 模式在 monitor 路径未完全实现（推荐 WebSocket）
- SDK 需 monkey-patch 才能处理 `card.action.trigger` 事件
- 维护者建议在个人测试账号中使用（AI 可访问敏感数据）
- 删除操作不可逆
- Formula/Lookup 字段只读

---

## 六、风险和注意事项

### 6.1 Lark WebSocket 不确定性
- 部分社区报告 Lark 国际版不支持 WebSocket 长连接
- **缓解：** 先尝试 WebSocket，失败则使用 Webhook（VPS 直接作为端点）

### 6.2 MiniMax M2.5 的局限
- 仅文本输入（无视觉能力，不能处理图片消息）
- 社区较 Claude/GPT 小，遇到问题时参考资料有限
- 中文能力优秀，但英文可能略逊于 Claude

### 6.3 安全性
- Lark App Secret 和 MiniMax API Key 需安全存储（chmod 600）
- 限制 Bot 可见范围（仅你和女朋友）
- 使用 `dmPolicy: "allowlist"` 或 `dmPolicy: "pairing"` 限制访问
- AI 可读取 Lark 中的消息、文档、日历等 — 注意数据边界

### 6.4 稳定性
- WebSocket 长连接可能断开（SDK 内置重连）
- OpenClaw Gateway 需要守护进程（systemd / PM2）
- MiniMax API 稳定性不如 Claude/OpenAI（较新的服务）

### 6.5 Lark 应用审核
- 必须在 `open.larksuite.com` 创建应用
- 需要审批发布
- 权限变更后需重新发布

---

## 七、参考资源

| 资源 | URL |
|------|-----|
| OpenClaw GitHub | https://github.com/openclaw/openclaw |
| OpenClaw 文档 | https://docs.openclaw.ai |
| openclaw-lark 插件 | https://github.com/larksuite/openclaw-lark |
| MiniMax M2.5 公告 | https://www.minimax.io/news/minimax-m25 |
| MiniMax API 文档 | https://platform.minimax.io/docs |
| MiniMax 定价 | https://platform.minimax.io/docs/guides/pricing-paygo |
| OpenClaw MiniMax Provider | https://docs.openclaw.ai/providers/minimax |
| Lark 开放平台（国际版） | https://open.larksuite.com |
| @larksuiteoapi/node-sdk | https://github.com/larksuite/node-sdk |
| OpenClaw Feishu 文档 | https://docs.openclaw.ai/channels/feishu |
| OpenClaw Hetzner 部署 | https://docs.openclaw.ai/install/hetzner |
| ClawHub 技能市场 | https://clawhub.com |
| OpenClaw Discord | https://discord.gg/clawd |
