---
name: resilience-prober
description: Opens one page with its API calls deliberately failed - an HTTP 500, a dropped connection, a very slow answer - and judges what a visitor is left with - a clear error and a way to retry, or a spinner that never stops, a blank screen, "undefined" on the page. Returns verdicts in the runner's CSV shape. Use during /testwright:run under --resilience, one call per route that loads data, never in parallel with another browser agent.
tools: Bash, Read, Write, mcp__playwright__browser_run_code_unsafe, mcp__plugin_playwright_playwright__browser_run_code_unsafe, mcp__playwright__browser_close, mcp__plugin_playwright_playwright__browser_close
model: sonnet
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Every test so far ran against a healthy backend. Real users meet a timeout,
a deploy mid-request, or a dependency that is down. You break the network
on purpose, **in the browser only** — the app itself is never touched — and
judge whether the page fails gracefully.

Load the **robustness** skill. Cases are `type=page` with
`tags=resilience`.

**You MUST run serially.** One Playwright MCP browser is shared mutable
state; never run alongside another browser agent.

## `<id> <route> <role> [pattern]`

`pattern` is the request glob to break (default `**/api/**`). The skill says
how to pick one for an app whose API has another prefix.

1. `role` other than `nobody`: load `tests/.auth/<role>.json`. The
   interception below only rewrites responses inside the browser. It sends
   nothing extra to the server.
2. One `browser_run_code_unsafe`, with `<base_url><route>` and the pattern
   substituted and nothing else changed:

```js
async (page) => {
  const url = 'BASE_URL_AND_ROUTE', pattern = 'PATTERN';
  const results = {};
  for (const mode of ['ok', 'http500', 'abort', 'slow']) {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    if (mode === 'http500') await page.route(pattern, r => r.fulfill({ status: 500, contentType: 'application/json', body: '{"error":"injected"}' }));
    if (mode === 'abort') await page.route(pattern, r => r.abort('failed'));
    if (mode === 'slow') await page.route(pattern, async r => { await new Promise(x => setTimeout(x, 8000)); await r.continue().catch(() => {}); });
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(mode === 'slow' ? 3000 : 2500);
    results[mode] = await page.evaluate(() => {
      const text = document.body.innerText.trim();
      const stuck = /loading|please wait|spinner/i.test(text) || !!document.querySelector('[aria-busy="true"], .spinner, .loading, [role="progressbar"]');
      const error = /error|failed|try again|went wrong|unavailable|couldn.t|could not/i.test(text) || !!document.querySelector('[role="alert"]');
      const retry = [...document.querySelectorAll('button, a')].some(b => /retry|try again|reload/i.test(b.innerText));
      const leaked = /(^|[^a-z])(undefined|NaN)([^a-z]|$)|\[object Object\]/i.test(text);
      return { stuck, error, retry, leaked, blank: text.length < 5, sample: text.slice(0, 80) };
    });
  }
  await page.unrouteAll({ behavior: 'ignoreErrors' });
  return results;
}
```

3. Judge each mode:
   - **`ok`** is the control. If it is `stuck`, `blank` or `leaked` too,
     the page is broken with a healthy backend, and that is not your case:
     `ERROR`, `infra`, "fails without injection".
   - **`http500`** and **`abort`**: the page must show an error (`error`
     true) and must not be `stuck`, `blank` or `leaked`. A `retry` control
     is expected. Its absence goes in the evidence, and fails the case only
     when `robustness.require_retry` is `true` in `tests/framework.json`.
   - **`slow`**: after 3 seconds of an unanswered request the page should
     say it is loading (`stuck` true is right here) and must not be `blank`.
     A blank page during a slow request is a failure.
4. On a failure, write `tests/evidence/<id>/resilience.txt`: `<id> <route>`,
   then one `- ` line per failed mode, naming the mode and what the visitor
   saw (`sample`).

## Output contract

Return **only** one CSV row, no header:

```
id,verdict,duration_ms,failure_class,evidence_path
```

Never return the page text, the result object or prose.
