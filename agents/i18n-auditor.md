---
name: i18n-auditor
description: Opens one page in each locale the app supports and judges what breaks in translation - text clipped or overflowing when a language runs 30-40% longer than English, a right-to-left locale that is not mirrored, dates, numbers and currency still in the English format, and untranslated strings mixed into a translated page. Returns verdicts in the runner's CSV shape. Use during /testwright:run under --i18n, one call per route, never in parallel with another browser agent.
tools: Bash, Read, Write, mcp__playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_navigate, mcp__playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_evaluate, mcp__playwright__browser_run_code_unsafe, mcp__plugin_playwright_playwright__browser_run_code_unsafe, mcp__playwright__browser_close, mcp__plugin_playwright_playwright__browser_close
model: sonnet
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

`tf.sh content run` has already caught what is wrong in the text itself: a
missing translation, a raw key, garbled characters. You judge what only
rendering shows, in each locale.

Load the **localization** skill: how locales are found and switched, and
what counts as a failure. Cases are `type=page` with `tags=i18n`.

**You MUST run serially.** Never run alongside another browser agent.

## `<id> <route> <role>`

1. **The locales.** Use `i18n.locales` from `tests/framework.json`. If
   there is none, use the locales the skill tells you how to find: a
   `locales/` or `i18n/` folder, `<link hreflang>`, or a language switcher on
   the page. **The switch**: `i18n.switch` in `framework.json` is a query
   parameter (`?lang=`), a path prefix (`/de/`), a cookie, or `header`
   (`Accept-Language`). Default: try `?lang=` and fall back to the header.
2. For the base locale, then each other locale, navigate. For `header` or
   `cookie`, use one `browser_run_code_unsafe` that sets them with
   `page.setExtraHTTPHeaders` or `context.addCookies`, then calls
   `page.goto`, and nothing else. Then run one `browser_evaluate`, unchanged:

```js
() => {
  const out = { lang: document.documentElement.lang, dir: getComputedStyle(document.documentElement).direction, clipped: [], overflowX: document.documentElement.scrollWidth > innerWidth + 1 };
  for (const el of document.querySelectorAll('button, a, label, th, td, h1, h2, h3, li, [role=tab], [role=menuitem], input[type=submit]')) {
    const s = getComputedStyle(el);
    if (el.offsetParent === null) continue;
    const txt = (el.innerText || el.value || '').trim();
    if (!txt) continue;
    if ((el.scrollWidth > el.clientWidth + 2 && s.overflowX !== 'visible') || (el.scrollHeight > el.clientHeight + 2 && s.overflowY === 'hidden'))
      out.clipped.push(txt.slice(0, 40));
  }
  out.clipped = out.clipped.slice(0, 10);
  out.text = document.body.innerText.slice(0, 4000);
  return out;
}
```

3. Judge each non-base locale. **Fail** on, and only on:
   - `clipped` entries, or `overflowX`, that the base locale does not have.
     The translation is longer than the box it was given;
   - a right-to-left locale (`ar`, `he`, `fa`, `ur`) whose `dir` is not
     `rtl`;
   - `lang` not set to the locale (screen readers and search engines read
     it);
   - in `text`: a date, number or currency still in the base locale's
     format when the skill's table says it differs (`1,234.56` on a `de`
     page, `09/29/2026` on an `en-GB` page), or a run of three or more
     base-language words in a translated page, meaning an untranslated
     string.
4. On a failure, write `tests/evidence/<id>/i18n.txt`: `<id> <route>`, then
   `- <locale>: <finding>`, one per line.

## Output contract

Return **only** one CSV row, no header:

```
id,verdict,duration_ms,failure_class,evidence_path
```

A page available in one locale only is `SKIP`. Never return page text or
prose.
