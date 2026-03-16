# Lark + Claude API 文档交互 Bot 完整搭建指南

> 目标：在 Hetzner VPS 上部署一个 Node.js 服务，让你女朋友在 Lark 中跟 Bot 对话，Bot 通过 Claude API（function calling）驱动 Lark Open API，完成文档的创建、查询、摘要等操作。

---

## 一、整体架构

```
你女朋友的 Lark 客户端
       ↕ 发消息 / 收回复
Lark Open Platform（WebSocket 长连接）
       ↕ 事件推送 / API 调用
你的 Node.js 服务（Hetzner VPS）
       ↕ function calling
Claude API（Anthropic）
```

**核心流程：**
1. 她在 Lark 里给 Bot 发消息，比如"帮我创建一篇关于项目周报的文档"
2. Lark 通过 WebSocket 把消息推送到你的 Node.js 服务
3. 服务把消息连同一组 tools 定义发给 Claude API
4. Claude 判断意图，返回 tool_use（比如 `create_document`）
5. 服务执行对应的 Lark Open API 调用
6. 把结果返回给 Claude，Claude 组织自然语言回复
7. 服务通过 Lark API 把回复发送给她

---

## 二、Lark 开放平台应用创建

### 2.1 创建应用

1. 登录 https://open.larksuite.com/app（注意是 larksuite，不是 feishu）
2. 点击 **Create Custom App**
3. 填写应用名称（如 "Claude Assistant"）和描述
4. 创建后进入应用详情页，记下：
   - **App ID**（形如 `cli_xxxxxxxxxx`）
   - **App Secret**

### 2.2 配置权限（Permissions & Scopes）

进入 **Permissions & Scopes** 页面，搜索并添加以下权限：

**即时通讯相关（必需）：**
- `im:message` — 发送消息
- `im:message.receive_v1` — 接收消息事件
- `im:resource` — 读取消息中的资源

**文档相关（核心功能）：**
- `docx:document` — 创建和编辑文档
- `docx:document:readonly` — 读取文档内容
- `wiki:wiki` — 知识库操作（可选）
- `wiki:wiki:readonly` — 读取知识库（可选）

**云盘相关：**
- `drive:drive` — 文件夹操作
- `drive:drive:readonly` — 读取文件列表
- `search:docs` — 搜索文档

> 提示：具体权限列表可能随 Lark 开放平台更新而变化。在开发过程中如果遇到权限不足的报错，到这里补加即可。

### 2.3 启用 Bot 功能

1. 进入 **Add Features** 页面
2. 点击 **Bot** → 启用
3. Bot 名称、描述、头像按喜好填写

### 2.4 配置事件订阅

1. 进入 **Events & Callbacks** 页面
2. **Subscription Method** 选择 **Long Connection（WebSocket）**
   - 这种方式不需要公网回调地址，你的 VPS 主动连接 Lark，非常适合你的场景
3. 添加事件：**im.message.receive_v1**（接收消息）

### 2.5 发布应用

1. 进入 **Version Management & Release**
2. 创建新版本，填写版本说明
3. 提交审核
4. 在 **Lark Admin Console** 中审批通过
5. **重要：Bot 在审批通过并发布后才能正常工作**

### 2.6 可见范围设置

进入 **Availability** 页面，设置应用的可见范围。至少要把你和你女朋友的账号加进去，这样她才能在 Lark 里搜到这个 Bot 并发起对话。

---

## 三、项目初始化

### 3.1 在 VPS 上创建项目

```bash
# SSH 到你的 Hetzner VPS
ssh root@your-vps-ip

# 确保 Node.js >= 20
node -v
# 如果需要安装
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs

# 创建项目
mkdir ~/lark-claude-bot && cd ~/lark-claude-bot
npm init -y

# 安装依赖
npm install @larksuiteoapi/node-sdk @anthropic-ai/sdk dotenv

# 安装开发依赖（TypeScript）
npm install -D typescript @types/node ts-node
npx tsc --init
```

### 3.2 tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"]
}
```

### 3.3 项目结构

```
lark-claude-bot/
├── src/
│   ├── index.ts              # 入口，启动 Lark WebSocket 客户端
│   ├── lark-client.ts        # Lark SDK 封装
│   ├── claude-agent.ts       # Claude API + tool definitions
│   ├── tools/
│   │   ├── types.ts          # 工具类型定义
│   │   ├── doc-tools.ts      # 文档相关工具实现
│   │   ├── search-tools.ts   # 搜索相关工具实现
│   │   └── drive-tools.ts    # 云盘相关工具实现
│   └── conversation-store.ts # 简易会话历史管理
├── .env                      # 环境变量（凭据）
├── package.json
└── tsconfig.json
```

### 3.4 .env 文件

```bash
# Lark
LARK_APP_ID=cli_xxxxxxxxxx
LARK_APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxx

# Anthropic
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxx

# 可选：限制只允许特定用户使用 bot
ALLOWED_USER_IDS=ou_xxxxxxxxxxxxxx,ou_xxxxxxxxxxxxxx

# 文档默认存放的文件夹 token（可选）
DEFAULT_FOLDER_TOKEN=fldcnxxxxxxxxxx
```

设置权限：`chmod 600 .env`

---

## 四、核心代码实现

### 4.1 Lark 客户端封装 — `src/lark-client.ts`

```typescript
import * as lark from "@larksuiteoapi/node-sdk";
import "dotenv/config";

// 创建 Lark 客户端
export const larkClient = new lark.Client({
  appId: process.env.LARK_APP_ID!,
  appSecret: process.env.LARK_APP_SECRET!,
  appType: lark.AppType.SelfBuild,
  domain: lark.Domain.Lark, // 注意：国际版用 Domain.Lark，国内版用 Domain.Feishu
});

// 创建 WebSocket 事件分发器
export const wsClient = new lark.WSClient({
  appId: process.env.LARK_APP_ID!,
  appSecret: process.env.LARK_APP_SECRET!,
  domain: lark.Domain.Lark,
  loggerLevel: lark.LoggerLevel.info,
});

// ---------- 消息发送相关 ----------

/** 发送文本消息 */
export async function sendTextMessage(chatId: string, text: string) {
  // Lark 单条消息限制约 30000 字符，超长需要分片
  const chunks = splitText(text, 25000);
  for (const chunk of chunks) {
    await larkClient.im.message.create({
      params: { receive_id_type: "chat_id" },
      data: {
        receive_id: chatId,
        msg_type: "text",
        content: JSON.stringify({ text: chunk }),
      },
    });
  }
}

/** 发送富文本消息（Markdown 风格） */
export async function sendRichTextMessage(chatId: string, title: string, content: string) {
  // Lark 富文本用 post 格式
  const post = {
    en_us: {
      title,
      content: [[{ tag: "text", text: content }]],
    },
  };
  await larkClient.im.message.create({
    params: { receive_id_type: "chat_id" },
    data: {
      receive_id: chatId,
      msg_type: "post",
      content: JSON.stringify(post),
    },
  });
}

/** 发送包含链接的消息 */
export async function sendLinkMessage(chatId: string, text: string, url: string, linkText: string) {
  const post = {
    en_us: {
      title: "",
      content: [
        [
          { tag: "text", text: text + " " },
          { tag: "a", text: linkText, href: url },
        ],
      ],
    },
  };
  await larkClient.im.message.create({
    params: { receive_id_type: "chat_id" },
    data: {
      receive_id: chatId,
      msg_type: "post",
      content: JSON.stringify(post),
    },
  });
}

// ---------- 文档操作相关 ----------

/** 创建文档 */
export async function createDocument(title: string, folderToken?: string) {
  const res = await larkClient.docx.document.create({
    data: {
      title,
      folder_token: folderToken || process.env.DEFAULT_FOLDER_TOKEN,
    },
  });
  return res.data?.document;
}

/** 获取文档纯文本内容 */
export async function getDocumentContent(documentId: string) {
  const res = await larkClient.docx.document.rawContent({
    path: { document_id: documentId },
    params: { lang: 0 }, // 0 = 全部语言
  });
  return res.data?.content || "";
}

/** 获取文档元信息 */
export async function getDocumentMeta(documentId: string) {
  const res = await larkClient.docx.document.get({
    path: { document_id: documentId },
  });
  return res.data?.document;
}

/** 向文档追加内容（创建文本块） */
export async function appendToDocument(documentId: string, text: string) {
  // 先获取文档，拿到最后一个 block 的 id 作为插入位置
  const blocks = await larkClient.docx.documentBlock.list({
    path: { document_id: documentId },
    params: { page_size: 500 },
  });

  const items = blocks.data?.items || [];
  // 文档的第一个 block 是 page block，我们在它下面追加
  const pageBlockId = items[0]?.block_id || documentId;

  // 追加文本段落
  await larkClient.docx.documentBlock.childrenBatchCreate({
    path: {
      document_id: documentId,
      block_id: pageBlockId,
    },
    data: {
      children: [
        {
          block_type: 2, // paragraph
          paragraph: {
            elements: [
              {
                text_run: {
                  content: text,
                },
              },
            ],
          },
        },
      ],
      index: -1, // 追加到末尾
    },
  });
}

/** 搜索文档 */
export async function searchDocuments(query: string) {
  const res = await larkClient.suite.search.message({
    params: { page_size: 10 },
    data: {
      query,
      // 可选：限制搜索范围
      // docs_types: ["doc", "docx"],
    },
  });
  return res.data?.items || [];
}

/** 列出文件夹中的文件 */
export async function listFiles(folderToken?: string) {
  const token = folderToken || process.env.DEFAULT_FOLDER_TOKEN || "";
  const res = await larkClient.drive.file.listByFolder({
    params: {
      folder_token: token,
      page_size: 50,
    },
  });
  return res.data?.files || [];
}

// ---------- 辅助函数 ----------

function splitText(text: string, maxLength: number): string[] {
  if (text.length <= maxLength) return [text];
  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > 0) {
    // 尝试在换行符处分割
    let splitIndex = remaining.lastIndexOf("\n", maxLength);
    if (splitIndex <= 0) splitIndex = maxLength;
    chunks.push(remaining.slice(0, splitIndex));
    remaining = remaining.slice(splitIndex);
  }
  return chunks;
}
```

### 4.2 Claude Agent — `src/claude-agent.ts`

```typescript
import Anthropic from "@anthropic-ai/sdk";
import "dotenv/config";

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY!,
});

// ---------- Tool 定义（Claude function calling） ----------

const tools: Anthropic.Tool[] = [
  {
    name: "create_document",
    description:
      "在 Lark 中创建一个新文档。如果用户要求创建文档、写一篇文章、生成报告等，使用此工具。会返回文档的 URL。",
    input_schema: {
      type: "object" as const,
      properties: {
        title: {
          type: "string",
          description: "文档标题",
        },
        content: {
          type: "string",
          description: "文档正文内容。支持纯文本，段落之间用换行分隔。",
        },
      },
      required: ["title", "content"],
    },
  },
  {
    name: "read_document",
    description:
      "读取一篇 Lark 文档的内容。当用户提到某篇文档、想了解文档内容、或要求总结/分析文档时使用。需要提供文档 ID 或文档 URL。",
    input_schema: {
      type: "object" as const,
      properties: {
        document_id: {
          type: "string",
          description:
            "文档 ID。可以从文档 URL 中提取，URL 格式通常为 https://xxx.larksuite.com/docx/DOCUMENT_ID",
        },
      },
      required: ["document_id"],
    },
  },
  {
    name: "search_documents",
    description:
      "在 Lark 中搜索文档。当用户想找某篇文档、搜索特定主题的文档时使用。",
    input_schema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "搜索关键词",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "append_to_document",
    description:
      "向已有的 Lark 文档末尾追加内容。当用户想在已有文档中添加内容时使用。",
    input_schema: {
      type: "object" as const,
      properties: {
        document_id: {
          type: "string",
          description: "要追加内容的文档 ID",
        },
        content: {
          type: "string",
          description: "要追加的文本内容",
        },
      },
      required: ["document_id", "content"],
    },
  },
  {
    name: "list_recent_files",
    description:
      "列出 Lark 云盘中最近的文件。当用户想查看有哪些文件、最近的文档列表时使用。",
    input_schema: {
      type: "object" as const,
      properties: {
        folder_token: {
          type: "string",
          description: "文件夹 token。不提供则列出默认文件夹中的内容。",
        },
      },
      required: [],
    },
  },
];

// ---------- 系统提示 ----------

const SYSTEM_PROMPT = `你是一个 Lark 文档助手，名叫 Claude Assistant。你帮助用户在 Lark 中管理和创建文档。

你的能力：
- 创建新文档（根据用户描述生成内容）
- 读取已有文档的内容并进行总结、分析、翻译等
- 搜索文档
- 向已有文档追加内容
- 列出最近的文件

使用规则：
1. 当用户让你"写一篇"、"创建"、"帮我写"文档时，先用 create_document 创建文档，然后把链接给用户
2. 当用户分享了文档链接或提到文档 ID 时，先用 read_document 读取内容
3. 当用户说"找一下"、"搜索"、"有没有关于XX的文档"时，用 search_documents
4. 创建文档时，内容要专业、结构清晰，用换行分隔段落
5. 始终用中文回复（除非用户用其他语言提问）
6. 文档 URL 从 Lark 文档 URL 中提取 ID 的方式：https://xxx.larksuite.com/docx/{document_id}

重要：你只是一个文档助手，不要尝试做与文档操作无关的事情。对于非文档相关的闲聊，你可以正常回复，但如果涉及发消息给别人、修改日历、审批等操作，请说明你目前只支持文档相关的功能。`;

// ---------- 会话记忆 ----------

// 简单的内存会话存储（生产环境可以换 Redis/SQLite）
const conversationHistory = new Map<
  string,
  Anthropic.MessageParam[]
>();

const MAX_HISTORY = 20; // 每个会话最多保留 20 轮

function getHistory(chatId: string): Anthropic.MessageParam[] {
  if (!conversationHistory.has(chatId)) {
    conversationHistory.set(chatId, []);
  }
  return conversationHistory.get(chatId)!;
}

function addToHistory(
  chatId: string,
  role: "user" | "assistant",
  content: string | Anthropic.ContentBlock[]
) {
  const history = getHistory(chatId);
  history.push({ role, content: content as any });
  // 超出长度限制时裁剪最早的对话
  while (history.length > MAX_HISTORY * 2) {
    history.shift();
  }
}

// ---------- Tool 执行器 ----------

import * as larkOps from "./lark-client";

async function executeTool(
  toolName: string,
  toolInput: Record<string, any>
): Promise<string> {
  try {
    switch (toolName) {
      case "create_document": {
        const doc = await larkOps.createDocument(toolInput.title);
        if (!doc) return JSON.stringify({ error: "创建文档失败" });

        // 向文档写入内容
        if (toolInput.content) {
          await larkOps.appendToDocument(doc.document_id!, toolInput.content);
        }

        const url = `https://YOUR_LARK_DOMAIN.larksuite.com/docx/${doc.document_id}`;
        return JSON.stringify({
          success: true,
          document_id: doc.document_id,
          title: doc.title,
          url,
          message: "文档创建成功",
        });
      }

      case "read_document": {
        const content = await larkOps.getDocumentContent(toolInput.document_id);
        const meta = await larkOps.getDocumentMeta(toolInput.document_id);
        return JSON.stringify({
          success: true,
          title: meta?.title || "未知标题",
          content: content.slice(0, 15000), // 防止内容过长
          truncated: content.length > 15000,
        });
      }

      case "search_documents": {
        const results = await larkOps.searchDocuments(toolInput.query);
        return JSON.stringify({
          success: true,
          count: results.length,
          results: results.map((item: any) => ({
            title: item.title,
            url: item.url,
            type: item.type,
          })),
        });
      }

      case "append_to_document": {
        await larkOps.appendToDocument(toolInput.document_id, toolInput.content);
        return JSON.stringify({
          success: true,
          message: "内容已追加到文档",
        });
      }

      case "list_recent_files": {
        const files = await larkOps.listFiles(toolInput.folder_token);
        return JSON.stringify({
          success: true,
          count: files.length,
          files: files.map((f: any) => ({
            name: f.name,
            type: f.type,
            url: f.url,
            modified_time: f.modified_time,
          })),
        });
      }

      default:
        return JSON.stringify({ error: `未知工具: ${toolName}` });
    }
  } catch (err: any) {
    console.error(`Tool execution error [${toolName}]:`, err.message);
    return JSON.stringify({
      error: `执行失败: ${err.message}`,
    });
  }
}

// ---------- 主对话函数 ----------

export async function chat(chatId: string, userMessage: string): Promise<string> {
  const history = getHistory(chatId);
  addToHistory(chatId, "user", userMessage);

  let messages: Anthropic.MessageParam[] = [...history];

  // 可能需要多轮 tool use
  let maxIterations = 5;
  while (maxIterations-- > 0) {
    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools,
      messages,
    });

    // 检查是否有 tool_use
    const toolUseBlocks = response.content.filter(
      (block) => block.type === "tool_use"
    );

    if (toolUseBlocks.length === 0) {
      // 纯文本回复，提取文字
      const textContent = response.content
        .filter((block) => block.type === "text")
        .map((block) => (block as Anthropic.TextBlock).text)
        .join("\n");

      addToHistory(chatId, "assistant", textContent);
      return textContent;
    }

    // 有 tool_use，需要执行工具并继续对话
    messages.push({ role: "assistant", content: response.content });

    // 执行每个 tool call
    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const block of toolUseBlocks) {
      if (block.type === "tool_use") {
        console.log(`[Tool Call] ${block.name}:`, JSON.stringify(block.input));
        const result = await executeTool(block.name, block.input as Record<string, any>);
        console.log(`[Tool Result] ${block.name}:`, result.slice(0, 200));
        toolResults.push({
          type: "tool_result",
          tool_use_id: block.id,
          content: result,
        });
      }
    }

    messages.push({ role: "user", content: toolResults });
  }

  return "抱歉，处理过程中遇到了问题，请稍后重试。";
}
```

### 4.3 入口文件 — `src/index.ts`

```typescript
import "dotenv/config";
import { wsClient, sendTextMessage, sendLinkMessage } from "./lark-client";
import { chat } from "./claude-agent";
import * as lark from "@larksuiteoapi/node-sdk";

// 允许使用 bot 的用户（可选安全措施）
const ALLOWED_USERS = process.env.ALLOWED_USER_IDS
  ? process.env.ALLOWED_USER_IDS.split(",").map((s) => s.trim())
  : [];

// 消息去重（Lark 可能重复推送）
const processedMessages = new Set<string>();

function isAllowed(userId: string): boolean {
  if (ALLOWED_USERS.length === 0) return true; // 未配置则不限制
  return ALLOWED_USERS.includes(userId);
}

// 从 Lark 消息内容中提取纯文本
function extractText(msgType: string, content: string): string | null {
  try {
    const parsed = JSON.parse(content);
    if (msgType === "text") {
      // 去掉 @bot 的 mention
      return (parsed.text as string).replace(/@_user_\d+/g, "").trim();
    }
    // 后续可以扩展：支持图片、文件等消息类型
    return null;
  } catch {
    return null;
  }
}

async function handleMessage(data: any) {
  const event = data;

  // 提取消息信息
  const messageId = event?.message?.message_id;
  const chatId = event?.message?.chat_id;
  const chatType = event?.message?.chat_type; // p2p 或 group
  const msgType = event?.message?.message_type;
  const content = event?.message?.content;
  const senderId = event?.sender?.sender_id?.open_id;

  // 基本校验
  if (!messageId || !chatId || !content) return;

  // 去重
  if (processedMessages.has(messageId)) return;
  processedMessages.add(messageId);
  // 清理旧的消息 ID（避免内存泄漏）
  if (processedMessages.size > 10000) {
    const arr = [...processedMessages];
    arr.slice(0, 5000).forEach((id) => processedMessages.delete(id));
  }

  // 权限检查
  if (!isAllowed(senderId)) {
    console.log(`[Rejected] User ${senderId} not in allowed list`);
    return;
  }

  // 群聊中只响应 @bot 的消息
  if (chatType === "group") {
    const mentions = event?.message?.mentions;
    if (!mentions || mentions.length === 0) return;
    // 检查是否 @了 bot（通过 mentions 中的 id 判断）
  }

  // 提取文本
  const text = extractText(msgType, content);
  if (!text) {
    await sendTextMessage(chatId, "目前我只能处理文字消息哦～");
    return;
  }

  console.log(`[Message] from=${senderId} chat=${chatId}: ${text.slice(0, 100)}`);

  try {
    // 调用 Claude Agent
    const reply = await chat(chatId, text);

    // 检查回复中是否包含文档链接，如果有则用富文本发送
    const urlMatch = reply.match(
      /(https:\/\/\S+\.larksuite\.com\/docx\/\S+)/
    );
    if (urlMatch) {
      // 分离文本和链接，用富文本消息发送
      await sendLinkMessage(chatId, reply.replace(urlMatch[0], "").trim(), urlMatch[0], "打开文档");
    } else {
      await sendTextMessage(chatId, reply);
    }
  } catch (err: any) {
    console.error("[Error]", err.message);
    await sendTextMessage(
      chatId,
      "处理消息时出错了，请稍后再试。错误：" + err.message?.slice(0, 100)
    );
  }
}

// ---------- 启动 ----------

async function main() {
  console.log("🚀 Starting Lark Claude Bot...");

  // 注册消息事件处理器
  const eventDispatcher = new lark.EventDispatcher({}).register({
    "im.message.receive_v1": async (data) => {
      await handleMessage(data);
    },
  });

  // 启动 WebSocket 长连接
  await wsClient.start({ eventDispatcher });

  console.log("✅ Bot is running! Waiting for messages...");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
```

### 4.4 package.json scripts

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  }
}
```

---

## 五、部署到 Hetzner VPS

### 5.1 构建

```bash
cd ~/lark-claude-bot
npm run build
```

### 5.2 用 PM2 管理进程

```bash
# 安装 PM2
npm install -g pm2

# 启动
pm2 start dist/index.js --name lark-claude-bot

# 设置开机自启
pm2 startup
pm2 save

# 查看日志
pm2 logs lark-claude-bot

# 重启 / 停止
pm2 restart lark-claude-bot
pm2 stop lark-claude-bot
```

### 5.3 systemd 替代方案

如果不想用 PM2，也可以创建 systemd service：

```bash
sudo cat > /etc/systemd/system/lark-claude-bot.service << 'EOF'
[Unit]
Description=Lark Claude Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/lark-claude-bot
ExecStart=/usr/bin/node /root/lark-claude-bot/dist/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable lark-claude-bot
sudo systemctl start lark-claude-bot
sudo systemctl status lark-claude-bot

# 看日志
journalctl -u lark-claude-bot -f
```

---

## 六、.env 中需要修改的项

| 变量 | 从哪里获取 |
|------|-----------|
| `LARK_APP_ID` | Lark 开放平台 → 你的应用 → Credentials → App ID |
| `LARK_APP_SECRET` | 同上 → App Secret |
| `ANTHROPIC_API_KEY` | https://console.anthropic.com → API Keys |
| `ALLOWED_USER_IDS` | Lark Admin → 用户管理中查看 open_id；或让 bot 打印收到的 sender_id |
| `DEFAULT_FOLDER_TOKEN` | 在 Lark 云盘中打开目标文件夹，URL 中的 token，形如 `fldcnxxxxxxxxxx` |

### 关于 claude-agent.ts 中的 URL

代码中有一行 `https://YOUR_LARK_DOMAIN.larksuite.com/docx/...`，需要替换为你实际的 Lark 域名。在 Lark Admin Console 中查看你的组织域名。

---

## 七、调试流程

### 7.1 本地开发

```bash
# 先在本地跑
npm run dev
```

在 Lark 中找到你的 bot，发一条消息测试。终端会打印日志。

### 7.2 常见问题排查

**Bot 没反应：**
- 检查应用是否已发布并审批通过
- 检查事件订阅是否配置了 `im.message.receive_v1`
- 检查是否选择了 Long Connection（WebSocket）方式
- 检查 ALLOWED_USER_IDS 是否包含了发消息人的 ID

**权限报错（code 99991400 等）：**
- 回到 Permissions & Scopes 页面添加缺失的权限
- 添加权限后需要重新发布应用版本

**文档创建成功但打不开：**
- 检查文档权限，bot 创建的文档默认只有 bot 可见
- 需要通过 Drive API 设置文档的分享权限（可以后续添加一个 `share_document` 工具）

### 7.3 获取用户的 open_id

如果不确定女朋友的 open_id，可以先不设 ALLOWED_USER_IDS，让她发一条消息，从日志中看到 `senderId` 的值，再填入 .env。

---

## 八、后续迭代建议

### 8.1 近期可以加的功能

- **文档分享权限**：创建文档后自动设置为"组织内可查看"或分享给特定用户
- **从 URL 提取文档 ID**：让她直接发文档链接，bot 自动解析 ID 去读取
- **文档模板**：预设几个常用模板（周报、会议纪要、待办清单等）
- **图片消息处理**：她发截图过来，bot 用 Claude 的 vision 能力理解图片

### 8.2 中期可以加的功能

- **多维表格（Bitable）操作**：查询/写入 Bitable 数据（你已经有经验了）
- **日历查询**：只读查看今天/本周的日程
- **对话记忆持久化**：用 SQLite 替代内存 Map，重启不丢会话

### 8.3 费用估算

- **Claude API**：Sonnet 4 的输入约 $3/百万 token，输出约 $15/百万 token。普通聊天+文档操作，每天几十轮对话大约 $0.1-0.5/天
- **Lark 开放平台**：免费额度足够个人使用
- **VPS**：你已有的 Hetzner，无额外费用
