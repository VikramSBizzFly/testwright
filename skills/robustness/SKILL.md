---
name: robustness
description: Test how a web app behaves when things go wrong or wear on - pages whose API fails, drops or is slow (resilience-prober), memory that leaks as a single-page app is used (leak-hunter), the same specs in Firefox and WebKit (cross-browser-runner), analytics events that silently stop firing (analytics-verifier), and a read-only smoke check of a live deploy (tf.sh postdeploy). Use for /testwright:run --resilience, --memory, --cross-browser, --analytics or --post-deploy, or when a user asks what happens when the API is down, whether the app leaks memory, works in Safari or Firefox, whether tracking still works, or whether a deploy is healthy.
---

# Robustness

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

## Resilience (`--resilience`, `tags=resilience`)

`tf.sh audit-cases resilience` writes one `RES-NNN` per page. Give it only
the pages that load data; a static page has nothing to fail. For each case,
`resilience-prober` intercepts the page's API requests in the browser and
tries four modes. **Nothing is sent to the server that a normal visit would
not send.**

| Mode | Injected | Pass |
| --- | --- | --- |
| `ok` | nothing: the control | a working page. If this fails, the case is ERROR, not a resilience finding |
| `http500` | every matching request answers 500 | a readable error; no endless spinner, blank page or `undefined` |
| `abort` | every matching request fails at the network | the same |
| `slow` | answers after 8 s; judged at 3 s | a loading state, not a blank page |

The request pattern defaults to `**/api/**`. Use the app's own prefix when
it differs (`**/graphql`, `**/v1/**`), from the api cases' routes. A retry
control is expected. `"robustness": { "require_retry": true }` makes its
absence a failure.

## Memory (`--memory`, `tags=memory`)

`tf.sh audit-cases memory` writes the cases. Keep only the routes of a
single-page app, where memory lives across navigations. A full page load
frees everything, so a server-rendered site cannot leak this way. For each
one, `leak-hunter`:
1. moves between two or more views ten times (hash routes, pushed paths, or
   clicks);
2. forces garbage collection through the Chrome DevTools Protocol;
3. samples the heap and the DOM node count.

**A leak** is a heap that rises at every sample by more than
`robustness.leak_mb` (5 MB), or DOM nodes growing by more than
`robustness.leak_nodes` (500). One step up that then stays flat is a cache
filling, not a leak.

Likely causes, by shape:

| Shape | Usually |
| --- | --- |
| About 1 MB or more per navigation | a module-level array, map or cache that is only appended to |
| A slow, steady rise | listeners or `setInterval` added on every mount and never removed |
| Nodes rising, heap flat | detached DOM kept alive by a closure or a stored element reference |

Chromium only: the heap measurement uses DevTools.

## Cross-browser (`--cross-browser`)

The Playwright MCP drives a single browser engine, so cross-browser runs
use the project's own Playwright runner, on the specs `spec-writer` promoted
(Tier 1 and 2). `cross-browser-runner` adds `firefox` and `webkit` projects
to the config, runs the specs across all three, and reports **only verdicts
that differ by browser**. It never installs browsers: it names the command.
At Tier 0 it says what is needed. Real devices remain out of scope.

## Analytics (`--analytics`, `tags=analytics`)

`analytics-verifier` takes the events from `analytics.plan` (a tracking
plan) or from the `track(...)` calls in the code. It performs each action in
the browser and checks that the request carries the event and its required
properties, exactly once, with no personal data. It never performs an
action that buys, sends or deletes. Whether the data reaches the warehouse
is out of scope; that the app sends it is not.

## Post-deploy (`--post-deploy`)

`tf.sh postdeploy` is the one engine command that talks to a remote host on
purpose, so it is fenced its own way:

- **The target** is `postdeploy.base_url` in `framework.json`, never the
  suite's `base_url`.
- **The requests** are GET only, anonymous: no cookie, no credential, no
  session.
- **The routes** are `postdeploy.routes`, or else the public `smoke` cases'
  routes.
- **The pace** is at most `postdeploy.max_requests` (30), one a second.
- **Without `--yes`** it only prints the plan. **Show it to the user first.**

It checks that each route answers 2xx within `postdeploy.max_ms`, that an
HTML page has a title and no stack trace, and that an https certificate has
more than `postdeploy.min_cert_days` (14) days left. The results go to the
summary panel and its exit code, so it can gate a deploy in CI. Nothing is
written to the case store.
