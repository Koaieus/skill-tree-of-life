---
description: Why settings.json denies remote MCP tools and trims skills — startup context load
paths:
  - ".claude/settings.json"
---
`permissions.deny` (rare `mcp__claude-code-remote__*` tools, `Workflow`) and `skillOverrides` (here and user-tier) exist to cut every session's start load: the remote server is `alwaysLoad` (ToolSearch never defers it), so deny is the only lever. Each denied name had 0–1 calls across all transcripts 2026-09-01..10-15.

**Why:** a fresh session showed ~62k used before its first word (MCP tools 15.7k, skills 6.7k; panel 2026-10-15).

**How to apply:** need a denied tool? Remove its line — that's it. Before adding a deny, count its use with the `archivist` first; never deny a tool a skill/charter names (`grep -r mcp__claude-code-remote .claude docs/charters`).
