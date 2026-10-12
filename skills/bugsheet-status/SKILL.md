---
name: bugsheet-status
description: Summarise the QA bug sheet — linked tabs, bugs per status, and the open bugs.
argument-hint: '[tab "Name"] [module Name]'
disable-model-invocation: true
allowed-tools: mcp__plugin_testwright_bugsheet__status, mcp__plugin_testwright_bugsheet__sheet_info, mcp__plugin_testwright_bugsheet__list_bugs
---

# Bug sheet status

Arguments: `$ARGUMENTS` (optional tab name and/or module). Tools are the bugsheet MCP tools
(`mcp__plugin_testwright_bugsheet__…`).

1. `sheet_info` (with `tabs` if a tab was named) → bugs per status on each tab.
2. `list_bugs` with `open: true`, `withFields: false` (plus `tabs` / `module`) → the open bugs.
3. Reply with:
   - one line per tab: `Tab — Open 4 · Fixed 12 · Reopen 1`;
   - a short table of open bugs: Tab · ID · Module · Status · Bug (one line);
   - a last line suggesting `/testwright:bugsheet-verify` to check them against the code.

If a tool says the client is missing, you are not signed in, or no sheet is linked, call
`status`, tell the user its `next` step, and suggest `/testwright:bugsheet-setup`.
