# Lark + Claude Bot 深度技术调研报告

> 调研日期：2026-03-16

---

## 目录

1. [Lark 开放平台 API 总览](#1-lark-开放平台-api-总览)
2. [Lark Bot SDK（Python & Node.js）](#2-lark-bot-sdk)
3. [事件订阅机制](#3-事件订阅机制)
4. [文档 API（DocX）](#4-文档-api)
5. [多维表格 API（Bitable）](#5-多维表格-api)
6. [现有 Claude + Lark 集成项目](#6-现有-claude--lark-集成项目)
7. [OpenClaw 平台](#7-openclaw-平台)
8. [Claude Agent SDK](#8-claude-agent-sdk)
9. [Claude Max 程序化使用分析](#9-claude-max-程序化使用分析)
10. [Claude API 定价与模型](#10-claude-api-定价与模型)
11. [架构建议与方案对比](#11-架构建议与方案对比)

---

## 1. Lark 开放平台 API 总览

### 1.1 API 基础信息

- **国际版 Base URL**: `https://open.larksuite.com/open-apis/`
- **国内版（飞书）Base URL**: `https://open.feishu.cn/open-apis/`
- **文档门户**: https://open.larksuite.com/document/home/index
- **API Explorer**: https://open.larksuite.com/api-explorer

### 1.2 认证方式

Lark 使用 OAuth 2.0 风格的认证，核心有三种 token：

| Token 类型 | 用途 | 获取方式 |
|-----------|------|---------|
| `app_access_token` | 应用级别访问 | POST `/auth/v3/app_access_token/internal` with app_id + app_secret |
| `tenant_access_token` | 租户级别访问（最常用） | POST `/auth/v3/tenant_access_token/internal` with app_id + app_secret |
| `user_access_token` | 用户级别访问 | OAuth 2.0 授权码流程 |

**SDK 自动管理 token**：使用官方 SDK 时，不需要手动获取和刷新 token，SDK 内部自动处理。

### 1.3 API 分类（基于 SDK 样例目录的 54 个模块）

- **即时通讯 (IM)**: 消息收发、群组管理、消息卡片
- **文档 (DocX)**: 创建/读取/编辑文档、文档块操作
- **多维表格 (Bitable)**: 表格/记录/字段/视图 CRUD
- **云盘 (Drive)**: 文件上传/下载/管理
- **日历 (Calendar)**: 日程创建/查询/更新
- **通讯录 (Contact)**: 用户/部门查询
- **知识库 (Wiki)**: 知识空间/节点操作
- **审批 (Approval)**: 审批流程
- **任务 (Task)**: 任务管理
- **搜索 (Search)**: 全局搜索
- **电子表格 (Sheets)**: Spreadsheet 操作
- **AI 相关 (Aily)**: AI 能力
- 等共 54 个 API 模块

---

## 2. Lark Bot SDK

### 2.1 Python SDK (`lark-oapi`)

**安装**:
```bash
pip install lark-oapi  # 当前版本 1.5.3，Python >= 3.7
```

**GitHub**: https://github.com/larksuite/oapi-sdk-python (483 stars)

**核心特性**:
- 自动 token 管理（获取、缓存、刷新）
- 数据加密/解密
- 请求签名验证
- 完整类型系统支持
- 同步和异步 API 调用
- Flask 适配器用于 Webhook 事件处理
- WebSocket 长连接支持

**客户端初始化**:
```python
import lark_oapi as lark

client = lark.Client.builder() \
    .app_id("cli_xxxxxxxxxx") \
    .app_secret("xxxxxxxxxxxxxxxxxxxxxxxx") \
    .log_level(lark.LogLevel.DEBUG) \
    .build()
```

**发送消息**:
```python
from lark_oapi.api.im.v1 import *

request = CreateMessageRequest.builder() \
    .receive_id_type("open_id") \
    .request_body(CreateMessageRequestBody.builder()
                  .receive_id("ou_xxxxxxxxxxxx")
                  .msg_type("text")
                  .content('{"text": "Hello!"}')
                  .build()) \
    .build()

response = client.im.v1.message.create(request)
```

**WebSocket 长连接（无需公网地址）**:
```python
import lark_oapi as lark

def do_p2_im_message_receive_v1(data: lark.im.v1.P2ImMessageReceiveV1) -> None:
    print(f'Received: {lark.JSON.marshal(data, indent=4)}')

event_handler = lark.EventDispatcherHandler.builder("", "") \
    .register_p2_im_message_receive_v1(do_p2_im_message_receive_v1) \
    .build()

cli = lark.ws.Client("APP_ID", "APP_SECRET",
                     event_handler=event_handler, log_level=lark.LogLevel.DEBUG)
cli.start()
```

**Flask Webhook 事件处理**:
```python
from flask import Flask
import lark_oapi as lark
from lark_oapi.adapter.flask import *
from lark_oapi.api.im.v1 import *

app = Flask(__name__)

def do_p2_im_message_receive_v1(data: P2ImMessageReceiveV1) -> None:
    print(lark.JSON.marshal(data))

handler = lark.EventDispatcherHandler.builder(ENCRYPT_KEY, VERIFICATION_TOKEN, lark.LogLevel.DEBUG) \
    .register_p2_im_message_receive_v1(do_p2_im_message_receive_v1) \
    .build()

@app.route("/event", methods=["POST"])
def event():
    resp = handler.do(parse_req())
    return parse_resp(resp)
```

### 2.2 Node.js SDK (`@larksuiteoapi/node-sdk`)

**安装**:
```bash
npm install @larksuiteoapi/node-sdk
# 或
yarn add @larksuiteoapi/node-sdk
```

**GitHub**: https://github.com/larksuite/node-sdk (244 stars)

注意：旧版 `@larksuiteoapi/allcore` 已于 2026-01-09 归档，推荐使用新版 `@larksuiteoapi/node-sdk`。

**客户端初始化**:
```typescript
import * as lark from "@larksuiteoapi/node-sdk";

const client = new lark.Client({
  appId: "app id",
  appSecret: "app secret",
  appType: lark.AppType.SelfBuild,
  domain: lark.Domain.Lark, // 国际版用 Lark，国内版用 Feishu
});
```

**WebSocket 长连接**:
```typescript
const wsClient = new lark.WSClient({
  appId: "xxx",
  appSecret: "xxx",
  loggerLevel: lark.LoggerLevel.info,
});

wsClient.start({
  eventDispatcher: new lark.EventDispatcher({}).register({
    "im.message.receive_v1": async (data) => {
      const { message: { chat_id, content } } = data;
      await client.im.v1.message.create({
        params: { receive_id_type: "chat_id" },
        data: {
          receive_id: chat_id,
          content: JSON.stringify({ text: "hello world" }),
          msg_type: "text",
        },
      });
    },
  }),
});
```

**Express Webhook**:
```typescript
import express from "express";
import bodyParser from "body-parser";
import * as lark from "@larksuiteoapi/node-sdk";

const server = express();
server.use(bodyParser.json());

const eventDispatcher = new lark.EventDispatcher({
  encryptKey: "encryptKey",
}).register({
  "im.message.receive_v1": async (data) => {
    const chatId = data.message.chat_id;
    await client.im.message.create({
      params: { receive_id_type: "chat_id" },
      data: {
        receive_id: chatId,
        content: JSON.stringify({ text: "hello world" }),
        msg_type: "text",
      },
    });
  },
});

server.use("/webhook/event", lark.adaptExpress(eventDispatcher));
server.listen(3000);
```

**消息卡片**:
```typescript
client.im.message.create({
  params: { receive_id_type: "chat_id" },
  data: {
    receive_id: "id",
    content: lark.messageCard.defaultCard({ title: "Title", content: "Text" }),
    msg_type: "interactive",
  },
});
```

**分页迭代器**:
```typescript
for await (const items of await client.contact.user.listWithIterator({
  params: { department_id: "0", page_size: 20 },
})) {
  console.log(items);
}
```

---

## 3. 事件订阅机制

### 3.1 两种订阅方式

| 方式 | 优点 | 缺点 |
|------|------|------|
| **WebSocket 长连接** | 无需公网地址、无需域名/SSL、部署简单 | 连接可能断开需要重连 |
| **Webhook HTTP 回调** | 标准 HTTP、更稳定 | 需要公网地址、域名、SSL 证书 |

### 3.2 核心事件

- `im.message.receive_v1` — 接收消息（最重要，Bot 的基础）
- `im.message.message_read_v1` — 消息已读
- `im.chat.member.bot.added_v1` — Bot 被添加到群
- `im.chat.member.bot.deleted_v1` — Bot 被移出群
- `card.action.trigger` — 卡片交互回调（新版）
- `url.preview.get` — URL 预览

### 3.3 WebSocket 长连接配置步骤

1. 在 Lark 开放平台 → 应用详情 → Events & Callbacks
2. Subscription Method 选择 **Long Connection（WebSocket）**
3. 添加需要监听的事件（如 `im.message.receive_v1`）
4. 代码中使用 `WSClient` 或 `lark.ws.Client` 启动

---

## 4. 文档 API（DocX）

### 4.1 可用操作（19 个 API）

**文档级操作**:
- `POST /docx/v1/documents` — 创建文档
- `GET /docx/v1/documents/{document_id}` — 获取文档元信息
- `GET /docx/v1/documents/{document_id}/raw_content` — 获取文档纯文本内容
- `POST /docx/v1/documents/{document_id}/convert` — 转换文档格式

**文档块操作（Block）**:
- `POST /docx/v1/documents/{document_id}/blocks/{block_id}/children` — 创建子块
- `GET /docx/v1/documents/{document_id}/blocks/{block_id}` — 获取块信息
- `GET /docx/v1/documents/{document_id}/blocks/{block_id}/children` — 获取子块列表
- `GET /docx/v1/documents/{document_id}/blocks` — 列出所有块
- `PATCH /docx/v1/documents/{document_id}/blocks/{block_id}` — 更新块
- `POST /docx/v1/documents/{document_id}/blocks/{block_id}/batch_update` — 批量更新块
- `DELETE /docx/v1/documents/{document_id}/blocks/{block_id}/children/batch_delete` — 批量删除子块
- `POST /docx/v1/documents/{document_id}/blocks/{block_id}/descendant` — 创建后代块

### 4.2 SDK 使用示例

**创建文档**:
```python
from lark_oapi.api.docx.v1 import *

request = CreateDocumentRequest.builder() \
    .request_body(CreateDocumentRequestBody.builder()
                  .folder_token("fldcnxxxxxxxxxx")
                  .title("我的文档")
                  .build()) \
    .build()

response = client.docx.v1.document.create(request)
```

**读取文档内容**:
```python
response = client.docx.v1.document.raw_content(
    RawContentDocumentRequest.builder()
    .document_id("docx_id_here")
    .build()
)
content = response.data.content
```

### 4.3 文档块类型

| block_type | 含义 |
|-----------|------|
| 1 | Page（页面，根块） |
| 2 | Text/Paragraph（文本段落） |
| 3 | Heading 1 |
| 4 | Heading 2 |
| 5 | Heading 3 |
| ... | 更多类型参考官方文档 |

### 4.4 所需权限

- `docx:document` — 创建和编辑文档
- `docx:document:readonly` — 读取文档内容
- `drive:drive` — 文件夹操作（创建文档到指定文件夹需要）

---

## 5. 多维表格 API（Bitable）

### 5.1 可用操作（46 个 API）

**应用（App）管理**:
- 创建/获取/更新/复制 Bitable 应用
- 复制仪表盘

**数据表（Table）操作**:
- 创建/列出/更新/删除数据表
- 批量创建/删除数据表

**记录（Record）操作** — 最常用:
- 创建/获取/更新/删除单条记录
- 批量创建/获取/更新/删除记录
- **搜索记录**（支持过滤、排序、分页）
- 列出记录

**字段（Field）操作**:
- 创建/列出/更新/删除字段

**视图（View）操作**:
- 创建/列出/更新/删除视图

**表单（Form）操作**:
- 获取/更新表单
- 列出/更新表单字段

**角色与权限**:
- 创建/列出/更新/删除角色
- 添加/列出/删除角色成员

**其他**:
- 列出仪表盘
- 列出/更新工作流

### 5.2 SDK 使用示例

**创建记录**:
```python
from lark_oapi.api.bitable.v1 import *

request = CreateAppTableRecordRequest.builder() \
    .app_token("bascng7vrxcxpig7geggXiCtadY") \
    .table_id("tblUa9vcYjWQYJCj") \
    .request_body(AppTableRecord.builder()
                  .fields({
                      "任务名称": "完成调研报告",
                      "状态": "进行中",
                      "负责人": [{"id": "ou_xxxx"}],
                  })
                  .build()) \
    .build()

response = client.bitable.v1.app_table_record.create(request)
```

**搜索记录（支持过滤）**:
```python
request = SearchAppTableRecordRequest.builder() \
    .app_token("app_token_here") \
    .table_id("table_id_here") \
    .page_size(20) \
    .request_body(SearchAppTableRecordRequestBody.builder()
                  .field_names(["任务名称", "状态"])
                  .sort([])
                  .filter(FilterInfo.builder()
                          .conjunction("and")
                          .conditions([
                              Condition.builder()
                              .field_name("状态")
                              .operator("is")
                              .value(["进行中"])
                              .build()
                          ])
                          .build())
                  .build()) \
    .build()

response = client.bitable.v1.app_table_record.search(request)
```

**批量更新记录**:
```python
request = BatchUpdateAppTableRecordRequest.builder() \
    .app_token("app_token") \
    .table_id("table_id") \
    .request_body(BatchUpdateAppTableRecordRequestBody.builder()
                  .records([
                      AppTableRecord.builder()
                      .record_id("rec_xxxx")
                      .fields({"状态": "已完成"})
                      .build()
                  ])
                  .build()) \
    .build()

response = client.bitable.v1.app_table_record.batch_update(request)
```

### 5.3 所需权限

- `bitable:app` — Bitable 应用读写
- `bitable:app:readonly` — Bitable 只读

---

## 6. 现有 Claude + Lark 集成项目

### 6.1 feishu-claude（daxiondi/feishu-claude）

**定位**：Feishu (Lark) bot bridge to Claude Code — 从手机控制本地开发环境

**架构**：
```
手机 (Feishu app) → Bridge Service (Node.js) → Claude Code (local process) → 代码库
```

**核心特性**：
- 每个飞书群 = 一个项目 = 独立 Claude 会话
- 自动会话关联：监控 `~/.claude/projects/` 检测新会话
- 会话持久化：映射存储在 `data/groups.json`
- 斜杠命令：`/session`, `/resume <id>`, `/loop`, `/cd`

**技术栈**：TypeScript, Node.js 22+, Claude Agent SDK

### 6.2 feishu-user-plugin（EthanQC/feishu-user-plugin）

**定位**：飞书 MCP Server — 让 Claude 以用户身份操作飞书

**核心特性（33 个工具，9 个技能组）**：
- **以用户身份发消息**（非 Bot 身份，通过逆向 Protobuf 协议实现）
- 文档：搜索/读取/创建
- Bitable：查询表/字段/记录，创建/更新记录
- Wiki：空间/节点/搜索
- Drive：列出文件和文件夹
- 联系人：按邮箱/手机号查找用户

**三层认证架构**：
1. 用户身份（Cookie/Protobuf）— Web session 模拟用户发消息
2. 官方 API（App 凭证）— 标准 REST API 操作
3. 用户 OAuth（UAT）— 用户授权 Token，自动刷新

**与 Claude 集成**：作为 MCP Server 配置到 Claude Code / Claude Desktop / Cursor 中

### 6.3 FlashClaw（GuLu9527/flashclaw）

**定位**：轻量级个人 AI 助手框架

**架构**：
- Channel 层：飞书、Telegram 连接器
- Tool 层：AI 能力和工具
- Provider 层：Anthropic Claude, OpenAI

**飞书集成**：
- WebSocket 长连接，无需公网服务器
- 智能消息路由：群组需 @，私聊自动回复
- 配置：`FEISHU_APP_ID` + `FEISHU_APP_SECRET`

**Claude 集成**：
```
AI_PROVIDER=anthropic-provider
AI_MODEL=claude-sonnet-4-20250514
ANTHROPIC_AUTH_TOKEN=sk-ant-xxx
```

**特色功能**：
- 插件系统（core + community plugins）
- 持久化记忆（用户级、会话级、全局）
- 定时任务（Cron/间隔/一次性）
- 多 Agent 路由
- Token 使用监控和自动上下文压缩

### 6.4 LangBot（langbot-app/LangBot）— 15.6k stars

**定位**：生产级多平台 AI Bot 框架

**支持平台**：Discord, Telegram, Slack, LINE, QQ, WeChat, 飞书/Lark 等

**支持 LLM**：Anthropic Claude, OpenAI, DeepSeek, Gemini, Ollama 等

**安装**：`uvx langbot` 或 Docker

**特点**：Web 管理界面、RAG 知识库、流式输出、MCP 协议支持

---

## 7. OpenClaw 平台

### 7.1 什么是 OpenClaw？

OpenClaw 是一个开源的个人 AI 助手平台（316k GitHub stars），核心理念是"在你自己的设备上运行的个人 AI 助手"。

**GitHub**: https://github.com/openclaw/openclaw

**架构**：Gateway WebSocket 控制面板 (`ws://127.0.0.1:18789`) 协调各组件

**支持 21+ 消息平台**：WhatsApp, Telegram, Slack, Discord, **飞书/Feishu**, LINE, Teams 等

**Skills 系统**：
- Bundled skills（内置）
- Managed skills（官方维护）
- Workspace skills（自定义）
- ClawHub 注册中心自动发现安装

**安装**：
```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

### 7.2 OpenClaw Lark 官方插件

**GitHub**: https://github.com/larksuite/openclaw-lark (1,036 stars)

**由飞书官方出品**，提供完整的飞书集成：

**能力覆盖**：
| 功能 | 详情 |
|------|------|
| 消息 | 读取/发送消息、搜索历史、管理回复线程 |
| 文档 | 创建和修改飞书文档 |
| 多维表格 | 完整 CRUD，支持批量和高级过滤 |
| 电子表格 | 创建/编辑/查看 |
| 日历 | 事件管理、参与者协调、可用时间查询 |
| 任务 | 任务创建/完成跟踪/子任务/评论 |

**高级功能**：
- 交互式卡片（思考中/生成中/完成 状态指示器）
- 流式响应实时更新消息卡片
- 每群独立配置（系统提示、技能绑定、白名单）
- 权限策略（私聊 vs 群聊不同控制）

**要求**：Node.js v22+, OpenClaw v2026.2.26+

### 7.3 其他 OpenClaw + 飞书社区项目

- `AlexAnys/openclaw-feishu` (581 stars) — 配置指南
- `AlexAnys/feishu-openclaw` (323 stars) — 无需公网的连接方案
- `Futaoj/enable_openclaw_feishu_lark` (74 stars) — 启用指南

---

## 8. Claude Agent SDK

### 8.1 概述

Claude Agent SDK（原 Claude Code SDK）是 Anthropic 官方提供的库，让开发者以编程方式使用 Claude Code 的全部能力——读文件、运行命令、编辑代码、搜索网页等。

**安装**：
```bash
# Python
pip install claude-agent-sdk

# TypeScript
npm install @anthropic-ai/claude-agent-sdk
```

### 8.2 认证方式

**必须使用 API Key**：
```bash
export ANTHROPIC_API_KEY=your-api-key
```

也支持：
- Amazon Bedrock（`CLAUDE_CODE_USE_BEDROCK=1`）
- Google Vertex AI（`CLAUDE_CODE_USE_VERTEX=1`）
- Microsoft Azure（`CLAUDE_CODE_USE_FOUNDRY=1`）

**重要限制**：
> "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK."

即：**Agent SDK 不能使用 claude.ai 订阅（Max/Pro）认证，必须使用 API Key**。

### 8.3 核心用法

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    async for message in query(
        prompt="Find and fix the bug in auth.py",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Edit", "Bash"],
            permission_mode="acceptEdits",
        ),
    ):
        if hasattr(message, "result"):
            print(message.result)

asyncio.run(main())
```

### 8.4 内置工具

| 工具 | 功能 |
|------|------|
| Read | 读取文件 |
| Write | 创建新文件 |
| Edit | 编辑已有文件 |
| Bash | 运行终端命令 |
| Glob | 按模式查找文件 |
| Grep | 正则搜索文件内容 |
| WebSearch | 网页搜索 |
| WebFetch | 获取网页内容 |
| AskUserQuestion | 向用户提问 |

### 8.5 高级功能

- **Hooks**：在工具调用前后运行自定义代码
- **Subagents**：生成专门的子代理处理子任务
- **MCP 集成**：连接外部系统（数据库、浏览器、API）
- **Sessions**：跨多轮维护上下文
- **自定义权限**：精确控制代理能使用哪些工具

### 8.6 作为 Lark Bot 后端的可行性

Agent SDK 可以作为 Lark Bot 的 AI 后端，但需注意：
- 它设计用于代码操作场景（读文件、写代码、运行命令）
- 对于纯对话 + Lark API 调用的场景，直接使用 Anthropic Client SDK 更合适
- 如果需要让 Claude 操作本地文件系统（如处理上传的文件），Agent SDK 有优势

---

## 9. Claude Max 程序化使用分析

### 9.1 Claude Max 订阅

Claude Max 是 claude.ai 的高级个人订阅计划，包含：
- claude.ai 网页版高级功能
- Claude Code 使用权
- 更高的使用限额

**Claude Code 支持的计划**（从认证文档确认）：
- Claude Pro（基础付费订阅）
- **Claude Max**（高级付费订阅）
- Claude for Teams
- Claude for Enterprise
- Claude Console（API 计费）

### 9.2 Claude Code 与 Max 的关系

Claude Code CLI 可以直接使用 Max 订阅登录（`claude` 命令 → 浏览器授权）。Max 用户运行 Claude Code 时，使用量计入 Max 订阅额度，而非 API 计费。

### 9.3 能否用 Max 为 Bot 供电？

**直接用 Claude Code CLI/Max 订阅**：
- Claude Code CLI 支持非交互式模式：`claude -p "prompt here"`
- 理论上可以在 Bot 收到消息时调用 `claude -p` 命令
- `feishu-claude` 项目就是这种方式（通过 Agent SDK 调用本地 Claude）

**Terms of Service 限制**：
Anthropic 消费者条款明确规定：
> "access through automated or non-human means, whether through a bot, script, or otherwise" 是禁止的
> 例外："except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it"

**结论**：
- Max 订阅用于个人交互使用 Claude Code 是允许的
- **通过 Max 订阅自动化地为 Bot 提供 AI 能力（非人工直接交互）违反消费者条款**
- **构建 Bot 应使用 Anthropic API Key（Console 计费）**，这是 Commercial Terms 明确允许的用途

### 9.4 合规方案

| 方案 | 合规性 | 成本 |
|------|--------|------|
| Anthropic API Key（推荐） | 完全合规 | 按 token 计费 |
| AWS Bedrock | 完全合规 | AWS 定价 |
| Google Vertex AI | 完全合规 | GCP 定价 |
| Azure AI Foundry | 完全合规 | Azure 定价 |
| Max 订阅自动化 | **违反 ToS** | 月费 |

---

## 10. Claude API 定价与模型

### 10.1 当前模型与定价

| 模型 | 输入价格 | 输出价格 | 上下文窗口 | 最大输出 |
|------|---------|---------|-----------|---------|
| Claude Opus 4.6 | $5/MTok | $25/MTok | 1M tokens | 128k tokens |
| **Claude Sonnet 4.6** | **$3/MTok** | **$15/MTok** | **1M tokens** | **64k tokens** |
| Claude Haiku 4.5 | $1/MTok | $5/MTok | 200k tokens | 64k tokens |

### 10.2 费用估算（Bot 场景）

假设每天 50 轮对话，每轮平均：
- 输入 ~2000 tokens（用户消息 + 系统提示 + 工具定义 + 历史）
- 输出 ~500 tokens（回复 + 工具调用）

使用 Sonnet 4.6：
- 每日输入：50 × 2000 = 100k tokens = $0.30
- 每日输出：50 × 500 = 25k tokens = $0.375
- **每日总计约 $0.50 - $1.00**
- **每月约 $15 - $30**

使用 Haiku 4.5（更省钱）：
- **每日总计约 $0.10 - $0.20**
- **每月约 $3 - $6**

---

## 11. 架构建议与方案对比

### 11.1 方案一：自建 Node.js 服务（推荐，当前 guide 的方案）

```
Lark Client → WebSocket → Node.js Service → Anthropic API → Lark API
```

**优点**：完全可控、最灵活、合规
**技术栈**：Node.js + @larksuiteoapi/node-sdk + @anthropic-ai/sdk
**适合**：需要精确控制 Bot 行为、自定义工具定义

### 11.2 方案二：OpenClaw + 飞书插件

```
Lark Client → OpenClaw Lark Plugin → OpenClaw Agent → LLM Provider
```

**优点**：开箱即用、功能最全（消息+文档+表格+日历+任务）、社区活跃
**缺点**：额外依赖 OpenClaw 平台、定制性受限于插件接口
**适合**：快速部署、需要全功能集成

### 11.3 方案三：FlashClaw

```
Lark Client → WebSocket → FlashClaw → Anthropic Claude
```

**优点**：轻量级、插件系统、内置记忆和定时任务
**缺点**：社区较小（26 stars）
**适合**：个人使用、需要定时任务和记忆功能

### 11.4 方案四：LangBot

```
Lark Client → LangBot Platform → Claude API
```

**优点**：成熟（15.6k stars）、多平台支持、Web 管理界面
**缺点**：通用框架可能对 Lark 特定功能支持不够深入
**适合**：需要多平台支持、团队使用

### 11.5 方案五：MCP Server 方案（feishu-user-plugin）

```
Claude Code / Claude Desktop → MCP → Feishu MCP Server → Lark API
```

**优点**：以用户身份操作（非 Bot）、33 个工具、覆盖面广
**缺点**：依赖逆向工程协议（可能不稳定）、更适合开发者自用
**适合**：开发者从 Claude Code 中操作飞书

### 11.6 综合建议

**如果目标是给非技术用户使用的 Bot**：方案一（自建）或方案二（OpenClaw）
- 方案一提供最大灵活性，代码已经在现有 guide 中
- 方案二功能最全，官方支持，但需要额外安装 OpenClaw

**如果是快速验证/个人使用**：方案三（FlashClaw）最快

**如果需要多平台**：方案四（LangBot）

**当前 guide 中的方案一是最佳平衡点**：
- 完全自主可控
- 合规使用 API Key
- WebSocket 长连接无需公网地址
- 易于扩展 Bitable 工具
- 代码清晰，易于维护

---

## 附录 A：快速参考 — Lark API URL 模式

```
# 国际版
Base URL: https://open.larksuite.com/open-apis

# 即时通讯
POST   /im/v1/messages                              # 发送消息
GET    /im/v1/messages/{message_id}                  # 获取消息
DELETE /im/v1/messages/{message_id}                  # 撤回消息

# 文档
POST   /docx/v1/documents                            # 创建文档
GET    /docx/v1/documents/{document_id}               # 获取文档信息
GET    /docx/v1/documents/{document_id}/raw_content   # 获取纯文本
GET    /docx/v1/documents/{document_id}/blocks        # 列出所有块
POST   /docx/v1/documents/{document_id}/blocks/{block_id}/children  # 添加子块

# 多维表格
POST   /bitable/v1/apps                               # 创建应用
GET    /bitable/v1/apps/{app_token}                    # 获取应用信息
POST   /bitable/v1/apps/{app_token}/tables             # 创建数据表
GET    /bitable/v1/apps/{app_token}/tables              # 列出数据表
POST   /bitable/v1/apps/{app_token}/tables/{table_id}/records        # 创建记录
GET    /bitable/v1/apps/{app_token}/tables/{table_id}/records        # 列出记录
POST   /bitable/v1/apps/{app_token}/tables/{table_id}/records/search # 搜索记录
PUT    /bitable/v1/apps/{app_token}/tables/{table_id}/records/{record_id}  # 更新记录
DELETE /bitable/v1/apps/{app_token}/tables/{table_id}/records/{record_id}  # 删除记录
POST   /bitable/v1/apps/{app_token}/tables/{table_id}/records/batch_create # 批量创建
POST   /bitable/v1/apps/{app_token}/tables/{table_id}/records/batch_update # 批量更新
POST   /bitable/v1/apps/{app_token}/tables/{table_id}/records/batch_delete # 批量删除
GET    /bitable/v1/apps/{app_token}/tables/{table_id}/fields         # 列出字段

# 云盘
GET    /drive/v1/files                                 # 列出文件
POST   /drive/v1/files/upload_all                      # 上传文件

# 搜索
POST   /suite/v1/search/messages                       # 搜索消息/文档
```

## 附录 B：需要的飞书应用权限清单

```
# 即时通讯
im:message                    # 发送消息
im:message:readonly           # 读取消息
im:resource                   # 读取消息资源（文件、图片等）

# 文档
docx:document                 # 创建和编辑文档
docx:document:readonly        # 读取文档

# 多维表格
bitable:app                   # 多维表格读写
bitable:app:readonly          # 多维表格只读

# 云盘
drive:drive                   # 云盘操作
drive:drive:readonly          # 云盘只读

# 知识库（可选）
wiki:wiki                     # 知识库操作
wiki:wiki:readonly            # 知识库只读

# 搜索
search:docs                   # 搜索文档

# 通讯录（可选）
contact:user.id:readonly      # 读取用户 ID
```

## 附录 C：关键仓库链接

| 项目 | Stars | 链接 |
|------|-------|------|
| Lark Python SDK | 483 | https://github.com/larksuite/oapi-sdk-python |
| Lark Node.js SDK | 244 | https://github.com/larksuite/node-sdk |
| OpenClaw | 316k | https://github.com/openclaw/openclaw |
| OpenClaw Lark 插件 | 1,036 | https://github.com/larksuite/openclaw-lark |
| LangBot | 15.6k | https://github.com/langbot-app/LangBot |
| FlashClaw | 26 | https://github.com/GuLu9527/flashclaw |
| feishu-claude | 0 | https://github.com/daxiondi/feishu-claude |
| feishu-user-plugin (MCP) | 0 | https://github.com/EthanQC/feishu-user-plugin |
| Claude Agent SDK (Python) | - | https://github.com/anthropics/claude-agent-sdk-python |
| Claude Agent SDK (TypeScript) | - | https://github.com/anthropics/claude-agent-sdk-typescript |
| Claude Agent SDK Demos | - | https://github.com/anthropics/claude-agent-sdk-demos |
