---
name: signals
description: Add accessibility, performance, responsive, SEO and visual-regression checks to page cases. Use when authoring an a11y/perf/responsive/seo/visual case, when a page case already opens a route and the extra assertion is nearly free, when deciding what an SEO pass checks and what it hands to the seo-auditor agent, or when deciding whether visual regression is worth turning on.
---

# Signals

Assertions riding on page cases you already have. Only add them where
they cost close to nothing — that is the whole pitch.

All of them stay `type=page`; the signal lives in `tags` (`a11y`, `perf`,
`visual`, `responsive`, `seo`). `type` is only ever `page` or `api` — see **testwright:authoring**.
Delegate the browser work: accessibility to the `a11y-auditor` agent, a
baseline diff to the `visual-reviewer` agent. Neither the tree nor the image
belongs in the main thread.

## Accessibility (`tags=a11y`) — nearly free

The Playwright MCP returns an accessibility tree with every snapshot you
already take for a `ui` case. Asserting on it costs no extra navigation.

Assert:

- every form input has an accessible name (label, `aria-label`, or
  `aria-labelledby`) — a missing one blocks a screen-reader user outright
- every interactive control (button, link, custom widget) is reachable in the
  tree — not `aria-hidden` while still clickable
- heading levels don't skip (`h1` → `h3` with no `h2`)

Ignore: colour contrast, ARIA role nitpicks below `WCAG A`, and anything only
a visual diff would catch — that noise buries the three checks above that
actually block a user. One `a11y` case per route, not per element.

## Performance (`tags=perf`) — capture what the browser already timed

Capture navigation timing (`domContentLoaded` / `load`, or the MCP's own
timing if it exposes one) on a case you're already running — do not add a
dedicated page load just to time it.

Compare against `perf_budget_ms` in `tests/framework.json` (default `3000`).
Over budget is a `FAIL`, not a warning — a budget nobody enforces is decor.
Record the actual ms in the result row so a regression shows a number, not
just red.

## Responsive (`tags=responsive`) — three widths, five failures

Delegate to the `responsive-auditor` agent, one call per route. It opens the
route at **390 / 768 / 1280** and fails only on what a person could not use:
horizontal overflow, clipped or overlapping text, a control pushed off-screen,
a nav that never collapses, and tap targets under 24px on the phone width.

**Reflow is not a failure** — a stacking sidebar or a one-column grid is the
design working. The failing width goes in the case's `viewport` column, which
the state schema has always had and nothing used until now.

## SEO (`tags=seo`) — curl first, a browser only when it must

A crawler reads the HTML the server sends, so nearly all of SEO is a curl
request: `tf.sh seo cases` writes the cases and `tf.sh seo run` judges them,
for zero tokens. The ids say what each one checks:

- `SEO-NNN`, one per public page (no API routes, no parameterised or
  privileged routes, and anything that redirects to a login is skipped at run
  time): 200 with at most one redirect; title 10–60 characters; description
  50–160; exactly one h1; one absolute canonical that resolves; `html lang`;
  a viewport; `og:title`, `og:description` and an `og:image` that resolves;
  not `noindex`; hreflang alternates that resolve, with `x-default`; `alt` on
  every image.
- `SEO-SITE-001` robots.txt does not block the site and names a sitemap;
  `-002` the sitemap parses, lists only live, indexable URLs and misses no
  public page; `-003` a path that does not exist returns 404; `-004` no two
  pages share a title or a description.

A canonical, og:image or sitemap URL naming the production host is checked by
its path on `base_url` — the production guard still holds. Findings go to
`tests/evidence/<id>/seo.txt`. A page meant to be hidden goes in
`framework.json` as `"seo": { "noindex_allow": ["/drafts"] }`; the sitemap
check stops after `seo.max_sitemap_urls` URLs (default 200).

Two things are handed to the `seo-auditor` agent instead of being guessed at:
a page that is an empty shell until JavaScript runs (UNJUDGED `needs-render`,
listed in `tests/.cache/seo/render.txt`), and judgement — placeholder titles,
a title about the wrong thing, JSON-LD (copied raw to
`tests/.cache/seo/jsonld/`) that is broken or missing what Google needs.
Rankings, keywords, backlinks and page speed are out of scope.

## Visual regression (`tags=visual`) — opt-in, and the one signal that costs tokens

Baselines live at `tests/baselines/<case-id>@<width>.png` — one per width, so a
phone render is never compared against a desktop baseline. A run diffs the current
screenshot against the baseline; a diff is not itself a verdict — it is a
manual review, because the model has to look at the image to say if it
matters. That review is the only thing in this whole framework that spends
tokens on a passing-looking case.

**Turn it on** for a small, deliberate set: the pages where markup is stable
and a pixel regression is the whole risk — a marketing page, a checkout step,
a chart. **Leave it off** everywhere layout is driven by real data (tables,
dashboards, anything with dates or user content) — every run diffs against
noise, and the diff-review cost recurs forever, not once. When a baseline
goes stale on purpose (an intended redesign), regenerate it explicitly; never
silently on a failed diff — that defeats the point of having one.
