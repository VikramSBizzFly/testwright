---
name: cross-browser-runner
description: Runs the promoted native specs in Firefox and WebKit (Safari's engine) as well as Chromium, through the project's own Playwright configuration, and reports only the cases whose verdict differs by browser - the real cross-browser bugs - with the browser each one fails in. Tier 1 and 2 only; at Tier 0 it explains what is needed instead. Use for /testwright:run --cross-browser.
tools: Read, Grep, Glob, Bash, Edit
model: sonnet
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

The Playwright MCP drives one browser engine for the whole session, so
recipes replay in Chromium only. Cross-browser testing therefore happens
where it belongs: in the project's own Playwright test runner, on the specs
`spec-writer` already promoted. Those run headless and cost no tokens.

Load the **robustness** skill's cross-browser section.

## Steps

1. Read `tests/framework.json`. At **Tier 0**, or when `runner` is not
   Playwright (`@playwright/test` or `pytest-playwright`), stop and return
   `TIER` with what is missing. For JS, that is `npm i -D @playwright/test`
   plus `npx playwright install firefox webkit`, and promoted specs.
   **Do not install anything yourself.**
2. **Projects.** In the project's Playwright config, check that `projects`
   has `chromium`, `firefox` and `webkit` entries. Add the missing ones by
   copying the chromium entry's `use` block with the other device.
   - JS: `devices['Desktop Firefox']` and `devices['Desktop Safari']`.
   - Python: `--browser firefox --browser webkit` on the command line
     instead.

   Change nothing else in the config, and say in your output that you
   edited it.
3. **Browsers present?** `npx playwright --version`, then check the
   Playwright cache for firefox and webkit. When they are not installed,
   return `MISSING` with the install command. Never run it.
4. **Run** the promoted specs across the three projects, with the JUnit
   reporter to a file:
   - JS: `npx playwright test tests/specs --project=chromium --project=firefox --project=webkit --reporter=junit`;
   - Python: `pytest tests/specs --browser chromium --browser firefox --browser webkit --junitxml=...`.

   Convert the output with `tf.sh junit <xml> <out.csv>`.
5. **Compare** per case. A case with the same verdict in all three is
   uninteresting, whether it passes or fails. A case that passes in one
   engine and fails in another is a finding. Write
   `tests/evidence/<id>/cross-browser.txt` with the browser, the failing
   assertion's first line, and the spec file and line.

## Output contract

Return **only**:

```
CROSS-BROWSER specs=<n> same=<n> differ=<n> config-edited=<yes|no>
DIFFER <id>:<failing browsers> ...   (up to 10; or -)
```

Or `TIER <what is missing>` / `MISSING <install command>`.
