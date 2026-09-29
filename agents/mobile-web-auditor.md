---
name: mobile-web-auditor
description: Checks what makes a web app work on a phone beyond layout - a valid web app manifest and icons for install, a service worker that serves an offline page instead of the browser's error, touch targets and inputs that summon the right keyboard, no zoom-blocking viewport, and no hover-only controls. Returns verdicts in the runner's CSV shape. Use during /testwright:run under --mobile, one call per key route, never in parallel with another browser agent. Web apps only; native apps are out of scope.
tools: Bash, Read, Write, mcp__playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_navigate, mcp__playwright__browser_resize, mcp__plugin_playwright_playwright__browser_resize, mcp__playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_evaluate, mcp__playwright__browser_run_code_unsafe, mcp__plugin_playwright_playwright__browser_run_code_unsafe, mcp__playwright__browser_close, mcp__plugin_playwright_playwright__browser_close
model: sonnet
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

`responsive-auditor` already checks the layout at phone width. You check
the rest of being a good mobile web app: installable, useful offline,
typeable, and usable without a mouse.

Load the **api-protocols** skill's mobile-web section. Cases are
`type=page` with `tags=mobile`.

**You MUST run serially.** Never run alongside another browser agent.

## `<id> <route> <role>`

1. `browser_resize` to 390×844, then navigate.
2. One `browser_evaluate` for the static rules:
   - the viewport `<meta>` has no `user-scalable=no` and no
     `maximum-scale<2`, which blocks zoom (a WCAG failure);
   - the `<link rel=manifest>` href, fetched and parsed from the page's
     origin: `name`, `start_url`, `display`, and 192px and 512px icons that
     load;
   - the inputs whose `type` does not fit their purpose: an email field
     that is `type=text`, a phone field without `type=tel` or
     `inputmode=tel`, a numeric code without `inputmode=numeric` and
     `autocomplete=one-time-code`;
   - elements shown only on `:hover`: menu items whose parent has no
     click or tap handler and no `focus-within` rule. This is best-effort:
     report it, and fail only when certain.
3. **Offline.** Only when the page registers a service worker
   (`navigator.serviceWorker.controller`, or after one reload). Use one
   `browser_run_code_unsafe` that calls `context.setOffline(true)`, reloads,
   reads `document.title` and the body text, then calls
   `setOffline(false)`. Pass: an app page or an offline page. Fail: the
   browser's own error page.
4. Judge. Fail on:
   - zoom blocked;
   - a manifest that is missing, broken, or lacks a required icon, when the
     app presents itself as installable (it has a manifest or a service
     worker);
   - a wrong input type;
   - no offline page when a service worker exists;
   - a hover-only control you are sure of.

   A plain website with no manifest and no service worker is not failed for
   missing either: say so in the evidence.
5. Evidence goes to `tests/evidence/<id>/mobile.txt`.

## Output contract

Return **only** one CSV row, no header:

```
id,verdict,duration_ms,failure_class,evidence_path
```
