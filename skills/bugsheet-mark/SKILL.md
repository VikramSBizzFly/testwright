---
name: bugsheet-mark
description: Mark the given QA bugs with a status in the bug sheet (default — the tab's "fixed" status) and optionally a Dev Comment. Shows a preview and writes only after the user confirms.
argument-hint: '<bug refs …> [status] [comment "text"]'
disable-model-invocation: true
allowed-tools: mcp__plugin_testwright_bugsheet__list_bugs, mcp__plugin_testwright_bugsheet__preview_status_update
---

# Mark bugs in the bug sheet

Arguments: `$ARGUMENTS` — bug refs (`61`, `62`, `"Agent-Bug Report:3"`), optionally a status
(`Done`, `Working`, …) and optionally `comment "…"` for the Dev Comment. Tools are the bugsheet
MCP tools (`mcp__plugin_testwright_bugsheet__…`).

**No bug refs given?** Do not ask which bugs, and do not suggest any. Reply in two lines:
`/testwright:bugsheet-mark` needs bug refs (e.g. `/testwright:bugsheet-mark "Agent-Bug Report:3" comment "Fixed in
PR #128"`), and `/testwright:bugsheet-verify` checks the sheet tab by tab, row by row, by itself. Then stop.

1. `list_bugs` with `refs`. For each ref in `problems` (not found, or on more than one tab),
   show the message and ask which bug was meant (`Tab:id`).
2. The status is the one given, or else each bug's `fixStatus`. If a bug's `fixStatus` is
   `null`, ask the user which status means fixed on that tab.
3. If no comment was given, ask whether to add a Dev Comment (e.g. "Fixed in PR #128") or none.
4. `preview_status_update` with `updates: [{ ref, status, comment? }]`. Show each bug (tab, id,
   title) and the cells it changes, old → new (the comment gets today's date in front).
5. Ask the user to confirm. Only after a yes, call `apply_status_update` with the same
   `updates`, and show which cells read back ✔ / ✘.

This does not check whether the bugs are really fixed. If the user wants that, suggest
`/testwright:bugsheet-verify <refs>` — it cross-checks them against the code and in the browser first.
