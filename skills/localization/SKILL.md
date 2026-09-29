---
name: localization
description: Check the words a web app shows - placeholder copy, unfilled templates, undefined and NaN leaking into the page, missing translations, raw i18n keys and garbled characters (tf.sh content, free), clear copy defects an editor would stop a release for (content-reviewer), and what breaks in other languages, such as clipped labels, right-to-left layout and locale formats (i18n-auditor). Use for /testwright:run --content or --i18n, when a user asks to check copy, typos, translations, localization, RTL support, or "does it work in German".
---

# Localization and content

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

## Content (`--content`, `tags=content`)

`tf.sh content cases` writes one `CONTENT-NNN` per page. `tf.sh content run`
reads each page's visible text (script, style and comments removed) and
fails on:

| Name (for `content.skip`) | Finds |
| --- | --- |
| `placeholder` | lorem ipsum, "dolor sit amet" |
| `marker` | TODO, FIXME, TBD, XXX, "placeholder text", "sample text" |
| `template` | `{{ name }}`, `{% %}`, `${x}`, `<%= %>`, `%s` |
| `js` | `undefined`, `NaN`, `[object Object]`, "Invalid Date" |
| `translation` | "translation missing", `[missing: ...]` |
| `i18n-key` | a whole text node that is a dotted key: `checkout.pay.button` |
| `encoding` | `CafÃ©`, `donâ€™t`, `�`: text decoded with the wrong charset |
| `server` | a stack trace, a PHP warning, an uncaught error in the page |

It also fails a page with fewer than 20 visible characters (a blank page).
A client-rendered shell is UNJUDGED and listed in
`tests/.cache/content/render.txt`, for `content-reviewer render`.

A site whose copy legitimately says "undefined" (a programming tutorial,
say) switches that check off with `"content": { "skip": ["js"] }`.

`content-reviewer review` then reads the saved text
(`tests/.cache/content/text/`) and fails only these copy defects:
- a developer-speak error;
- an empty state with nothing to say;
- a clear typo;
- one thing called by two names in a flow;
- a control that does not say what it does.

Never style preferences.

## Languages (`--i18n`, `tags=i18n`)

`tf.sh audit-cases i18n` writes one `I18N-NNN` per page, and the
`i18n-auditor` agent runs one per call.

**Finding the locales**, in order:
1. `i18n.locales` in `framework.json`;
2. the folder names under `locales/`, `i18n/`, `lang/` or `translations/`;
3. `<link rel=alternate hreflang>`;
4. a language switcher on the page.

**Switching** (`i18n.switch`):
- `query`: `?lang=de`, the default;
- `path`: `/de/...`;
- `cookie`: `i18n.cookie`, the cookie's name;
- `header`: `Accept-Language`.

**What fails**, compared with the base locale:

| Finding | Why it matters |
| --- | --- |
| A label clipped or overflowing that fits in the base locale | German and Finnish run 30-40% longer than English. A fixed-width button hides the word that says what it does |
| A right-to-left locale (`ar`, `he`, `fa`, `ur`) without `dir=rtl` | The whole layout reads backwards |
| `<html lang>` not set to the locale | Screen readers pronounce the page in the wrong language |
| Dates, numbers or currency in the base format | `1,234.56` means something else on a German page, and `09/10` is a different day in the UK |
| Three or more base-language words in a translated page | An untranslated string |

Formats the auditor checks, by example:

| Locale | Number | Date |
| --- | --- | --- |
| `en-US` | `1,234.56` | `09/29/2026` |
| `en-GB` | `1,234.56` | `29/09/2026` |
| `de` | `1.234,56` | `29.09.2026` |
| `fr` | `1 234,56` | `29/09/2026` |
| `ja` | `1,234.56` | `2026/09/29` |

Translation *quality* is out of scope. Whether "Warenkorb" is the right word
is a translator's job. That the button shows the whole word is ours.
