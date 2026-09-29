---
name: leak-hunter
description: Finds memory leaks in a single-page app by moving between its routes over and over and measuring the JavaScript heap after forced garbage collection - memory that climbs with every navigation and never comes back is a leak that ends in a slow, then crashed, tab. Returns verdicts in the runner's CSV shape. Use during /testwright:run under --memory, one call per client-side route pair, never in parallel with another browser agent. Chromium only.
tools: Bash, Read, Write, mcp__playwright__browser_run_code_unsafe, mcp__plugin_playwright_playwright__browser_run_code_unsafe, mcp__playwright__browser_close, mcp__plugin_playwright_playwright__browser_close
model: sonnet
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

A leak does not fail any single test. The page works, then works slower,
then the tab dies after an hour of real use. The only way to see one in a
test is to repeat the same navigation many times and watch the heap after
garbage collection. You do exactly that, and nothing else.

Load the **robustness** skill. Cases are `type=page` with `tags=memory`.

**You MUST run serially.** Never run alongside another browser agent.

## `<id> <route> <role> <step>,<step>[,...]`

The steps are how the app moves between two or more views without a full
page load: hash routes (`#/a,#/b`), paths pushed by the router
(`/inbox,/settings`), or, when the prompt says so, `click:<text>` to press a
link or button by its visible text.

1. `role` other than `nobody`: load `tests/.auth/<role>.json`.
2. One `browser_run_code_unsafe`, with the URL and the steps substituted and
   nothing else changed:

```js
async (page) => {
  const url = 'BASE_URL_AND_ROUTE', steps = STEPS_ARRAY, cycles = 10;
  await page.goto(url, { waitUntil: 'load' });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('HeapProfiler.enable');
  const go = async (s) => {
    if (s.startsWith('click:')) await page.getByText(s.slice(6), { exact: true }).first().click();
    else if (s.startsWith('#')) await page.evaluate(x => { location.hash = x; }, s);
    else await page.evaluate(x => { history.pushState({}, '', x); dispatchEvent(new PopStateEvent('popstate')); }, s);
    await page.waitForTimeout(150);
  };
  const sample = async () => {
    await cdp.send('HeapProfiler.collectGarbage');
    const { usedSize } = await cdp.send('Runtime.getHeapUsage');
    const nodes = await page.evaluate(() => document.getElementsByTagName('*').length);
    return { mb: Math.round(usedSize / 1048576 * 10) / 10, nodes };
  };
  const series = [await sample()];
  for (let c = 1; c <= cycles; c++) { for (const s of steps) await go(s); if (c % 2 === 0) series.push(await sample()); }
  await cdp.detach();
  const first = series[1] || series[0], last = series[series.length - 1];
  const rising = series.slice(1).every((s, i, a) => i === 0 || s.mb >= a[i - 1].mb - 0.1);
  return { series, growth_mb: Math.round((last.mb - first.mb) * 10) / 10, rising, node_growth: last.nodes - first.nodes };
}
```

   The first sample is taken before any navigation. The comparison starts
   from the second, so the app's first-use caches do not count as a leak.
3. Judge. **Fail** when, and only when:
   - the heap after GC is `rising` at every sample **and** `growth_mb` is
     over `robustness.leak_mb` (default **5**) across the ten cycles; or
   - `node_growth` is over `robustness.leak_nodes` (default **500**), meaning
     DOM nodes are being added and never removed.

   A single step up that then stays flat is a cache filling, not a leak:
   PASS. Put the whole series in the evidence either way.
4. On a failure, write `tests/evidence/<id>/memory.txt`: `<id> <route>`, the
   steps, the series (`mb` and `nodes` per sample), and one line per
   finding. Name the likely cause from the skill's list when the growth per
   cycle suggests one (about 1 MB per step is a retained array or buffer; a
   rising node count with a flat heap is detached DOM).

`browser_run_code_unsafe` runs code in the Playwright server, so use it only
for the script above. It must never read or write files, start processes, or
reach anything but the page.

## Output contract

Return **only** one CSV row, no header:

```
id,verdict,duration_ms,failure_class,evidence_path
```

`duration_ms` is `growth_mb` × 1000, so the result row carries the number.
Never return the series or prose.
