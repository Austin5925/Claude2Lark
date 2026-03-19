# Lark AI 助手应用 — 权限申请

## 应用信息

| 项目 | 内容 |
|------|------|
| 应用名称 | 小龙虾（AI 工作助手） |
| 类型 | 企业自建应用 |
| 使用人 | 仅限本人（私聊模式） |
| 用途 | 通过 Lark Bot 辅助日常工作（查询文档、操作多维表格、管理日程等） |

---

## 权限架构说明

本应用采用 **User Access Token（用户身份凭证）** 架构：

- **Bot 只能操作我本人有权限访问的内容**，不会超越我自己的权限范围
- 所有对公司数据的访问（文档、表格、日历、任务等）都使用我个人的 OAuth 授权
- Bot 不进入任何群组，仅限私聊

权限分为两部分：

| 类别 | Token 类型 | 数量 | 作用 | 能访问公司数据？ |
|------|-----------|------|------|----------------|
| Bot 消息通道 | 应用身份（tenant） | 7 个 | Bot 收发聊天消息 | **否** |
| 数据操作 | **用户身份（user）** | 按需授权 | 文档/表格/日历等 | **是，仅限本人权限范围** |

---

## 第一部分：应用级权限（Bot 消息通道，7 个）

这些权限仅用于 Bot 作为 Lark 机器人收发消息，**不涉及任何公司数据访问**。这是 Lark 平台对任何机器人的基础要求。

| 权限 | 用途 |
|------|------|
| `im:message.p2p_msg:readonly` | 接收私聊消息 |
| `im:message:send_as_bot` | Bot 发送回复 |
| `im:message:readonly` | 读取消息内容 |
| `im:message:update` | 更新流式回复卡片 |
| `im:resource` | 处理用户发送的图片/文件 |
| `cardkit:card:write` | 创建回复卡片 |
| `application:application:self_manage` | 应用自身状态查询 |

**批量导入 JSON（应用级）：**

```json
{
  "scopes": {
    "tenant": [
      "im:message.p2p_msg:readonly",
      "im:message:send_as_bot",
      "im:message:readonly",
      "im:message:update",
      "im:resource",
      "cardkit:card:write",
      "application:application:self_manage"
    ],
    "user": []
  }
}
```

---

## 第二部分：用户级权限（数据操作，OAuth 按需授权）

以下权限在我首次使用对应功能时，通过 Lark OAuth 授权流程由**我本人确认授权**。Bot 获得的权限完全等同于我自己的 Lark 权限，不会超越。

### 多维表格（核心需求）

| 权限 | 用途 |
|------|------|
| `base:app:read` | 读取多维表格应用信息 |
| `base:app:create` | 创建多维表格 |
| `base:app:update` | 更新多维表格设置 |
| `base:table:read` | 读取表格结构 |
| `base:table:create` | 创建数据表 |
| `base:record:retrieve` | 查询记录 |
| `base:record:create` | 新增记录 |
| `base:record:update` | 修改记录 |
| `base:record:delete` | 删除记录 |
| `base:field:read` | 读取字段信息 |
| `base:view:read` | 读取视图 |

### 文档（核心需求）

| 权限 | 用途 |
|------|------|
| `docx:document:readonly` | 读取文档内容 |
| `docx:document:create` | 创建文档 |
| `docx:document:write_only` | 编辑文档内容 |
| `docs:document.comment:read` | 读取文档评论 |

### 日历

| 权限 | 用途 |
|------|------|
| `calendar:calendar:read` | 查看日程 |
| `calendar:calendar.event:read` | 读取日程详情 |
| `calendar:calendar.event:create` | 创建日程 |
| `calendar:calendar.event:update` | 修改日程 |

### 任务

| 权限 | 用途 |
|------|------|
| `task:task:read` | 查看任务 |
| `task:task:write` | 创建/修改任务 |

### 云盘与知识库

| 权限 | 用途 |
|------|------|
| `space:document:retrieve` | 浏览云盘文件列表 |
| `wiki:space:retrieve` | 浏览知识库 |
| `wiki:node:read` | 读取知识库内容 |
| `search:docs:read` | 搜索文档和知识库 |

---

## 安全措施（对应公司 AI Agent 使用政策 v1.1）

| 公司政策要求 | 本应用实现方式 |
|-------------|--------------|
| **2.1 个人专属，禁止共用** | 白名单机制，仅允许本人的 Open ID |
| **2.2 禁止外部接入** | 仅接入 Lark，无其他平台；服务器防火墙禁止外部访问 |
| **2.3 数据安全** | Bot 系统提示强制：写操作需确认、禁止向外泄露数据、所有数据视为机密 |
| **3.2 最小权限** | 权限修改工具已禁用（`tools.perm: false`），Bot 无法修改文档分享设置 |
| **4.1 单一平台** | 仅 Lark 渠道，群组功能已禁用，Bot 不会被拉入任何群组 |
| **5.2 User Token** | **全部数据操作使用用户身份凭证（UAT），Bot 只能操作本人有权限的内容** |

### 核心原则

**Bot 能做的事 ≤ 我自己能做的事。**

- 我能看的文档，Bot 能帮我查；我看不到的，Bot 也看不到
- 我能编辑的表格，Bot 能帮我改；我没权限的，Bot 也改不了
- Bot 不进群、不群发、不改权限、不访问我权限之外的任何内容

---

## 事件订阅

仅需订阅一个事件：

| 事件 | 用途 |
|------|------|
| `im.message.receive_v1` | 接收用户发送的私聊消息 |

连接方式：**WebSocket 长连接**（无需暴露公网端点）

---

## 可见范围

仅限本人可见，不对其他同事开放。
