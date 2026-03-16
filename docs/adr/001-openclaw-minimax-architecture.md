# ADR-001: OpenClaw + MiniMax M2.5 Architecture

## Status
Accepted

## Context
Need a Lark bot that can operate documents, bitable, calendar, and tasks. Evaluated multiple approaches:
- Custom Node.js bot + Claude API
- Claude-to-IM + MCP Server
- OpenClaw + openclaw-lark plugin

## Decision
Use OpenClaw Gateway + openclaw-lark plugin with MiniMax M2.5 as LLM backend.

## Rationale
- **openclaw-lark** provides 98 ready-made Lark tool actions (docs, bitable, calendar, tasks, etc.)
- **MiniMax M2.5** costs 1/10 of Claude Sonnet with better tool-calling benchmarks (BFCL 76.8%)
- **OpenClaw** is battle-tested (316K GitHub stars) with rich infrastructure
- Zero application code needed — pure configuration deployment

## Consequences
- Dependent on OpenClaw and openclaw-lark plugin updates
- MiniMax M2.5 is text-only (no vision/image processing)
- Lark international WebSocket support is uncertain — may need Webhook fallback
