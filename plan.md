# OpenClaw + Lark + MiniMax M2.5 实施计划

> 目标：在 Hetzner VPS 上部署 OpenClaw，通过 openclaw-lark 插件接入 Lark（国际版），使用 MiniMax M2.5 作为 LLM 后端，让女朋友在 Lark 中与 AI Agent 对话，实现文档/多维表格/日历/任务等操作。

---

## 系统架构

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   女朋友的 Lark 客户端（手机/桌面）                                │
│                                                                  │
└───────────────────────────┬──────────────────────────────────────┘
                            │ 发消息 / @Bot / 收回复
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   Lark Open Platform (open.larksuite.com)                        │
│   ┌──────────────────────────────────────────┐                   │
│   │ 事件订阅（WebSocket 长连接 或 Webhook）    │                   │
│   │ • im.message.receive_v1                   │                   │
│   │ • im.message.reaction.created_v1          │                   │
│   │ • im.chat.member.bot.added_v1             │                   │
│   │ • card.action.trigger                     │                   │
│   └──────────────────────┬───────────────────┘                   │
│                          │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │ WebSocket / HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   Hetzner VPS (CX22, Ubuntu 24.04, ~$4.50/月)                   │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │                  OpenClaw Gateway                         │   │
│   │                  (Node.js >= 22)                          │   │
│   │                                                          │   │
│   │   ┌──────────────────┐    ┌────────────────────────┐    │   │
│   │   │ openclaw-lark    │    │    Agent Runtime        │    │   │
│   │   │ 插件             │    │                        │    │   │
│   │   │                  │    │  ┌──────────────────┐  │    │   │
│   │   │ • IM 工具 (4)    │◄──►│  │ MiniMax M2.5    │  │    │   │
│   │   │ • 文档 (5)       │    │  │ Provider        │  │    │   │
│   │   │ • 多维表格 (27)  │    │  │ (OpenAI-compat) │  │    │   │
│   │   │ • 电子表格 (7)   │    │  └──────┬───────────┘  │    │   │
│   │   │ • 日历 (4)       │    │         │              │    │   │
│   │   │ • 任务 (4)       │    │  ┌──────┴───────────┐  │    │   │
│   │   │ • 云盘 (7)       │    │  │ Skill Engine    │  │    │   │
│   │   │ • 知识库 (2)     │    │  │ (9 内置 Skills) │  │    │   │
│   │   │ • 搜索 (2)       │    │  └──────────────────┘  │    │   │
│   │   │ • OAuth (1)      │    └────────────────────────┘    │   │
│   │   └──────────────────┘                                  │   │
│   │                                                          │   │
│   │   ┌──────────────────┐    ┌────────────────────────┐    │   │
│   │   │ WebSocket API    │    │ Control UI (Web)       │    │   │
│   │   │ :18789 (local)   │    │ :18789/dashboard       │    │   │
│   │   └──────────────────┘    └────────────────────────┘    │   │
│   └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│   守护进程: systemd / PM2                                        │
│   远程管理: SSH 隧道 / Tailscale                                 │
│                                                                  │
└──────────────────────────┬───────────────────────────────────────┘
                           │ HTTPS (OpenAI-compatible API)
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   MiniMax API (api.minimax.io/v1)                                │
│   • 模型: MiniMax-M2.5                                           │
│   • 认证: API Key                                                │
│   • 工具调用: OpenAI 格式 tools + function calling               │
│   • 定价: $0.30 input / $1.20 output per M tokens               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 数据流

```
1. 女朋友在 Lark 中发消息："帮我在项目管理表里新增一条任务"
      ↓
2. Lark Platform → WebSocket 推送 im.message.receive_v1 事件
      ↓
3. openclaw-lark 插件接收消息 → 解析文本 → 去重 → 权限检查
      ↓
4. Agent Runtime 将消息 + 98 个工具定义 + 会话历史发送到 MiniMax M2.5
      ↓
5. MiniMax M2.5 分析意图，返回 tool_call:
   { name: "feishu_bitable_app_table_record", action: "create", ... }
      ↓
6. openclaw-lark 执行 Lark Open API 调用
   POST https://open.larksuite.com/open-apis/bitable/v1/apps/.../records
      ↓
7. 工具结果返回给 MiniMax M2.5
      ↓
8. MiniMax M2.5 组织自然语言回复："已在项目管理表中创建新记录..."
      ↓
9. openclaw-lark 通过流式卡片将回复发送到 Lark
      ↓
10. 女朋友在 Lark 中看到卡片回复
```

### 连接模式决策树

```
尝试 WebSocket 长连接（首选）
    ├── 成功 → 使用 WebSocket（无需公网 URL，最简单）
    └── 失败 → 切换 Webhook 模式
                ├── VPS 有公网 IP → 直接配置回调 URL
                └── 需要隧道 → Cloudflare Tunnel / ngrok
```

---

## 前置条件

在开始之前，需要准备：

| 项目                | 状态    | 说明                   |
| ------------------- | ------- | ---------------------- |
| Hetzner VPS         | ✅ 已有 | 需要 SSH 访问权限      |
| Lark 账户（你）     | 需确认  | 需要管理员权限创建应用 |
| Lark 账户（女朋友） | 需确认  | 需要在同一 Lark 组织下 |
| MiniMax 开发者账号  | 待注册  | platform.minimax.io    |
| MiniMax API Key     | 待获取  | 注册后在面板创建       |
| 域名（可选）        | 看情况  | 仅 Webhook 模式需要    |

---

## 原则

### 核心工作流

1. **Plan-first**：任何改动前先输出 `[PLAN]`，等用户明确批准后再动手写代码。绝不跳过计划直接实现。
2. **每个版本做好详细的测试，每个版本 commit push 一次。**
3. **做好版本日志和版本管理。** 使用 Conventional Commits（`feat:` / `fix:` / `chore:` / `docs:` 等），配合 commitlint 强制格式。
4. **使用相关的 skills 和 MCP。**
5. **以后每次和你说完改动，你自动 commit，push，make deploy。**

### Git 纪律

7. **绝不使用 `--force`、`--no-verify`、`--amend`（除非明确要求）、`git add -A`。** 精确 stage 需要的文件。
8. **绝不提交密钥/凭据。** `.env`、API Key、App Secret 等必须在 `.gitignore` 中。
9. **Commit 消息简洁且 action-oriented，<100 字符。** 格式：`<type>: <description>`。

### 安全与验证

10. **绝不假设，总是验证。** 不猜测失败原因，不跳过状态检查。
11. **改动后立即测试。** 每次改动后运行相关检查（lint、build、连通性测试等），确认没有破坏。
12. **失败自动回滚。** 如果测试不通过，回退到上一个已知良好状态，而非硬改测试让它通过。

### 文档与可追溯性

13. **配置变更记录在 CHANGELOG 中。** 每次部署相关的配置修改都要有记录。
14. **重要架构决策写 ADR（Architecture Decision Record）。** 放在 `docs/adr/` 下。
15. **CLAUDE.md 保持最新。** 项目上下文变化时同步更新，确保 AI 助手始终有正确的项目认知。

### 部署

16. **`make deploy` 是唯一的部署入口。** 所有部署步骤封装在 Makefile 中，一条命令完成。
17. **部署前自动检查。** Makefile 中的 deploy target 应先运行验证步骤。
18. **环境变量通过 `.env` 文件管理，配置通过 `openclaw.json` 管理。** 两者都不进 git。

## 待办事项清单

### 阶段一：环境准备

- [x] **1.1 VPS 环境检查**
  - [x] SSH 登录 Hetzner VPS (46.224.44.160, ssh openclaw2)
  - [x] 确认系统版本：Ubuntu 24.04.3 LTS
  - [x] 确认内存：7.6 GB
  - [x] 确认磁盘：71 GB 可用

- [x] **1.2 安装 Node.js 22**
  - [x] Node.js v22.22.1 已安装
  - [x] npm 10.9.4 已安装

- [x] **1.3 安装 OpenClaw**
  - [x] OpenClaw 2026.3.13 已安装
  - [x] systemd 服务已配置（`openclaw gateway run` 前台模式）

- [x] **1.4 注册 MiniMax 开发者账号**
  - [x] 使用 platform.minimaxi.com（国内平台）
  - [x] Coding Plan API Key (sk-cp-) 已获取
  - [x] 注意：Coding Plan key 使用 Anthropic 兼容端点 `https://api.minimaxi.com/anthropic`

### 阶段二：Lark 应用创建

- [ ] **2.1 创建 Lark 应用**
  - [ ] 登录 https://open.larksuite.com/app
  - [ ] 点击 "Create Custom App"
  - [ ] 填写应用名称（如 "AI Assistant"）
  - [ ] 填写应用描述
  - [ ] 上传应用图标（可选）
  - [ ] 记录 **App ID**（`cli_xxxxxxxxxx`）
  - [ ] 记录 **App Secret**

- [ ] **2.2 配置应用权限**
  - [ ] 进入 Permissions & Scopes 页面
  - [ ] 添加 20 个必需的应用级权限：
    - [ ] `im:message.group_at_msg:readonly`
    - [ ] `im:message.p2p_msg:readonly`
    - [ ] `im:message:send_as_bot`
    - [ ] `im:message:readonly`
    - [ ] `im:message:update`
    - [ ] `im:message:recall`
    - [ ] `im:resource`
    - [ ] `im:chat:read`
    - [ ] `im:chat:update`
    - [ ] `im:message.pins:read`
    - [ ] `im:message.pins:write_only`
    - [ ] `im:message.reactions:read`
    - [ ] `im:message.reactions:write_only`
    - [ ] `im:message:send_multi_users`
    - [ ] `im:message:send_sys_msg`
    - [ ] `cardkit:card:write`
    - [ ] `cardkit:card:read`
    - [ ] `application:application:self_manage`
    - [ ] `contact:contact.base:readonly`
    - [ ] `docx:document:readonly`

- [ ] **2.3 启用 Bot 功能**
  - [ ] 进入 Add Features 页面
  - [ ] 启用 Bot 能力
  - [ ] 设置 Bot 名称
  - [ ] 设置 Bot 描述

- [ ] **2.4 配置事件订阅**
  - [ ] 进入 Events & Callbacks 页面
  - [ ] Subscription Method 选择 **Long Connection (WebSocket)**
    - ⚠️ 如果 Lark 国际版不提供此选项，记录并准备切换 Webhook
  - [ ] 添加事件：`im.message.receive_v1`
  - [ ] （可选）添加事件：`im.message.reaction.created_v1`
  - [ ] （可选）添加事件：`im.chat.member.bot.added_v1`

- [ ] **2.5 设置可见范围**
  - [ ] 进入 Availability 页面
  - [ ] 添加你自己的 Lark 账号
  - [ ] 添加女朋友的 Lark 账号
  - [ ] 限制可见范围为仅这两个人（安全考虑）

- [ ] **2.6 发布应用**
  - [ ] 进入 Version Management & Release
  - [ ] 创建新版本
  - [ ] 填写版本说明
  - [ ] 提交审核
  - [ ] 在 Lark Admin Console 中审批通过
  - [ ] 确认应用状态为"已发布"

### 阶段三：OpenClaw 配置

- [x] **3.1 运行 OpenClaw 入门向导**
  - [x] 手动创建配置文件 `~/.openclaw/openclaw.json`
  - [x] 配置 `gateway.mode: "local"` 用于 VPS 前台运行

- [x] **3.2 配置 MiniMax Provider**
  - [x] .env 中设置 `MINIMAX_API_KEY`
  - [x] 发现：Coding Plan key 需要 Anthropic 兼容端点
  - [x] 正确配置：`baseUrl: "https://api.minimaxi.com/anthropic"`, `api: "anthropic-messages"`
  - [x] API 连通性已验证（curl 测试成功）

- [x] **3.3 配置 Lark Channel**
  - [x] Feishu channel 已配置（`domain: "lark"`, `connectionMode: "websocket"`）
  - [x] WebSocket 在 Lark 国际版上**可用**（日志确认 `ws client ready`）
  - [x] 所有 Lark 工具已注册：feishu_doc, feishu_chat, feishu_wiki, feishu_drive, feishu_bitable
  - [ ] ⚠️ 待完成：Lark 控制台需配置事件订阅和补充权限

- [x] **3.4 配置访问控制**
  - [x] 初始策略设为 `dmPolicy: "pairing"`（配对码模式）
  - [ ] 待完成：获取 Open ID 后切换为 allowlist

- [x] **3.5 安全配置**
  - [x] Gateway Token 已生成并配置
  - [x] 文件权限已设置（chmod 600）
  - [x] 所有凭据通过 .env 环境变量引用，不硬编码

### 阶段四：首次启动和测试

- [ ] **4.1 启动 Gateway**
  - [ ] `openclaw gateway start`
  - [ ] 观察日志输出，确认无报错
  - [ ] 确认 WebSocket 连接成功（或 Webhook 端点就绪）

- [ ] **4.2 WebSocket 连接验证**
  - [ ] 检查日志中是否出现 WebSocket 连接成功信息
  - [ ] 如果连接失败：
    - [ ] 记录错误信息
    - [ ] 切换到 Webhook 模式（见阶段四备选）

- [ ] **4.3 基本消息测试**
  - [ ] 在 Lark 中搜索 Bot 名称
  - [ ] 发送 "你好" 测试基本对话
  - [ ] 如使用 pairing 模式：运行 `openclaw pairing approve feishu <CODE>`
  - [ ] 确认 Bot 正常回复

- [ ] **4.4 Lark 工具测试**
  - [ ] 测试文档操作："帮我创建一个文档，标题是测试"
  - [ ] 测试多维表格："列出 [表格名] 中的记录"
  - [ ] 测试搜索："帮我搜索关于 XX 的文档"
  - [ ] 测试日历（如已授权）："今天有什么日程？"
  - [ ] 记录每个测试的结果和问题

- [ ] **4.5 MiniMax 工具调用验证**
  - [ ] 确认 MiniMax M2.5 正确触发 Lark 工具
  - [ ] 检查工具调用日志
  - [ ] 验证多轮工具调用（如：搜索文档 → 读取内容 → 总结）

### 阶段四备选：Webhook 模式配置

> 仅当 WebSocket 连接失败时执行

- [ ] **4B.1 配置 VPS 公网端点**
  - [ ] 确认 VPS 公网 IP 可达
  - [ ] 选择方案：
    - [ ] 方案 A：直接使用 VPS IP + 端口
    - [ ] 方案 B：Cloudflare Tunnel（`cloudflared tunnel`）
    - [ ] 方案 C：nginx 反向代理 + Let's Encrypt SSL

- [ ] **4B.2 配置 OpenClaw Webhook**
  - [ ] 修改 `openclaw.json`：`"connectionMode": "webhook"`
  - [ ] 添加 webhook 配置（verificationToken, encryptKey）

- [ ] **4B.3 配置 Lark Webhook 回调**
  - [ ] 在 Lark 开放平台 Events & Callbacks 中修改为 HTTP 方式
  - [ ] 填入回调 URL：`https://your-domain/webhook/feishu`
  - [ ] 验证回调 URL（Lark 会发送验证请求）

- [ ] **4B.4 重新发布 Lark 应用**
  - [ ] 创建新版本
  - [ ] 提交审核
  - [ ] 审批通过

### 阶段五：持久化运行

- [x] **5.1 配置 systemd 服务**
  - [ ] 创建 `/etc/systemd/system/openclaw.service`：

    ```ini
    [Unit]
    Description=OpenClaw Gateway
    After=network.target

    [Service]
    Type=simple
    User=openclaw
    Environment=MINIMAX_API_KEY=xxx
    Environment=FEISHU_APP_ID=cli_xxx
    Environment=FEISHU_APP_SECRET=xxx
    ExecStart=/usr/bin/openclaw gateway start
    Restart=always
    RestartSec=5
    TimeoutStartSec=90

    [Install]
    WantedBy=multi-user.target
    ```

  - [x] `systemctl daemon-reload`
  - [x] `systemctl enable openclaw`
  - [x] `systemctl start openclaw`
  - [x] `systemctl status openclaw` — active (running)

- [ ] **5.2 创建专用系统用户**
  - [ ] `useradd -r -m -s /bin/bash openclaw`
  - [ ] 将配置迁移到 `/home/openclaw/.openclaw/`
  - [ ] 设置正确的文件权限

- [ ] **5.3 日志管理**
  - [ ] `journalctl -u openclaw -f`（实时查看日志）
  - [ ] 配置日志轮转（避免磁盘满）

- [ ] **5.4 远程管理配置**
  - [ ] 方案 A：SSH 隧道 `ssh -N -L 18789:127.0.0.1:18789 root@VPS_IP`
  - [ ] 方案 B：安装 Tailscale（推荐长期使用）
  - [ ] 测试远程访问 Control UI

### 阶段六：安全加固

- [ ] **6.1 访问控制**
  - [ ] 确认 `dmPolicy` 为 `"allowlist"` 或 `"pairing"`
  - [ ] 确认 `groupPolicy` 为 `"disabled"`（暂不开放群组）
  - [ ] 验证未授权用户无法使用 Bot

- [ ] **6.2 凭据安全**
  - [ ] 所有密钥通过环境变量传递（不硬编码在配置文件中）
  - [ ] `chmod 600 ~/.openclaw/openclaw.json`
  - [ ] `chmod 700 ~/.openclaw/`
  - [ ] 确认 `.env` 文件不在 git 仓库中

- [ ] **6.3 网络安全**
  - [ ] Gateway 仅绑定 `127.0.0.1:18789`（不暴露到公网）
  - [ ] 如使用 Webhook：配置防火墙仅开放必要端口
  - [ ] 运行 `openclaw security audit --deep`

- [ ] **6.4 Bot 权限最小化**
  - [ ] 审查 Lark 应用权限，移除不需要的 scope
  - [ ] 考虑对高风险操作（如删除文档）添加确认步骤

### 阶段七：用户体验优化

- [ ] **7.1 用户级 OAuth 授权**
  - [ ] 启用 UAT（User Access Token）以获取更多操作权限
  - [ ] 引导女朋友完成 `/feishu_auth` 授权流程
  - [ ] 验证授权后的权限提升（如文档写入、日历管理）

- [ ] **7.2 自定义系统提示**
  - [ ] 编写适合女朋友使用场景的系统提示词
  - [ ] 配置在 `openclaw.json` 的 `agents.defaults.systemPrompt` 中
  - [ ] 或为特定群组配置独立提示词

- [ ] **7.3 流式输出调优**
  - [ ] 调整 `streaming` 和 `blockStreaming` 参数
  - [ ] 测试卡片渲染效果
  - [ ] 调整 `textChunkLimit`（默认 2000）

- [ ] **7.4 常用操作文档**
  - [ ] 为女朋友整理 Bot 使用说明：
    - 如何创建文档
    - 如何查询/修改多维表格
    - 如何管理日历/任务
    - 如何搜索文档
  - [ ] 发送到 Lark 中保存

### 阶段八：监控和维护

- [ ] **8.1 运行状态监控**
  - [ ] 定期检查：`openclaw gateway status`
  - [ ] 定期检查：`openclaw logs --follow`
  - [ ] 监控 MiniMax API 用量：`/usage full`

- [ ] **8.2 费用监控**
  - [ ] 设置 MiniMax API 用量告警（如有）
  - [ ] 每周检查 API 费用
  - [ ] 如费用异常：检查是否有非预期的工具调用

- [ ] **8.3 故障排查准备**
  - [ ] 熟悉 `openclaw doctor` 命令
  - [ ] 熟悉 Lark 开放平台的应用诊断工具
  - [ ] 记录常见问题和解决方案

- [ ] **8.4 更新策略**
  - [ ] 定期更新 OpenClaw：`openclaw update --channel stable`
  - [ ] 更新前先备份配置：`cp -r ~/.openclaw ~/.openclaw.bak`
  - [ ] 关注 openclaw-lark 插件更新

### 阶段九：功能扩展（可选）

- [ ] **9.1 群组支持**
  - [ ] 评估是否开放群组使用
  - [ ] 配置 `groupPolicy: "allowlist"` 和 `requireMention: true`
  - [ ] 为不同群组配置不同权限和系统提示

- [ ] **9.2 额外 Skills**
  - [ ] 浏览 ClawHub（clawhub.com）技能市场
  - [ ] 安装有用的额外技能
  - [ ] 测试技能兼容性

- [ ] **9.3 Docker 沙箱**
  - [ ] 如需增强安全性，启用 Docker 沙箱
  - [ ] 配置 `OPENCLAW_SANDBOX=1`
  - [ ] 测试沙箱对工具执行的影响

- [ ] **9.4 多 LLM 后端**
  - [ ] 配置 fallback 模型链（如 MiniMax → Haiku）
  - [ ] 测试故障转移行为

---

## 关键决策点

| 决策         | 选项                        | 推荐             | 触发条件                     |
| ------------ | --------------------------- | ---------------- | ---------------------------- |
| 连接模式     | WebSocket / Webhook         | 先试 WebSocket   | Lark 国际版是否支持 WS       |
| DM 策略      | pairing / allowlist         | allowlist        | 确定女朋友 Open ID 后        |
| 群组策略     | open / allowlist / disabled | disabled         | 初期仅私聊                   |
| MiniMax 模型 | M2.5 / M2.5-highspeed       | M2.5             | 响应速度不满意则切 highspeed |
| 沙箱         | off / non-main / all        | off              | 初期不需要                   |
| 远程管理     | SSH 隧道 / Tailscale        | SSH 隧道（初期） | 频繁管理则装 Tailscale       |

---

## 预估时间线

| 阶段                   | 预估时间 | 依赖                           |
| ---------------------- | -------- | ------------------------------ |
| 阶段一：环境准备       | 30 分钟  | 无                             |
| 阶段二：Lark 应用创建  | 1-2 小时 | 需要 Lark 管理员权限           |
| 阶段三：OpenClaw 配置  | 30 分钟  | 阶段一 + 二完成                |
| 阶段四：首次启动和测试 | 1-2 小时 | 阶段三完成 + Lark 应用审批通过 |
| 阶段五：持久化运行     | 30 分钟  | 阶段四验证通过                 |
| 阶段六：安全加固       | 30 分钟  | 阶段五完成                     |
| 阶段七：用户体验优化   | 1-2 小时 | 阶段六完成                     |
| 阶段八：监控和维护     | 持续     | 阶段七完成                     |

**核心阶段（一到六）总计约 4-6 小时**，其中最大的不确定性是 Lark 应用审批时间。

---

## 回退方案

如果 OpenClaw + openclaw-lark 方案遇到不可解决的问题：

| 问题                   | 回退方案                                                      |
| ---------------------- | ------------------------------------------------------------- |
| Lark WebSocket 不支持  | 切换 Webhook 模式（阶段四备选）                               |
| Webhook 也不通         | 使用 `abca12a/lark-openclaw` 插件（Lark 专用 Webhook）        |
| MiniMax 工具调用质量差 | 切换到 Claude Haiku 4（$0.25/$1.25，价格接近）                |
| openclaw-lark 插件 Bug | 尝试社区插件 `xzq-xu/openclaw-plugin-feishu`（明确支持 Lark） |
| OpenClaw 整体不可用    | 回退到自建 Node.js Bot（参考 lark-claude-bot-guide.md）       |
