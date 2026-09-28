---
name: performance
description: Audit how fast a web app is and find its performance bugs - server response time, endpoint latency (p50/p95), page weight, compression, caching, Core Web Vitals (LCP, CLS, TBT) in a real browser, load under concurrent users, and code patterns that will be slow at scale (N+1 queries, unpaginated lists). Use when running /testwright:run --perf or --load, when writing or judging a tags=perf case, when choosing or changing a performance budget, or when a perf failure needs a root cause or a bug report.
---

# Performance

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

A performance audit here answers one question per case: **is this over its
budget, by how much, and why**. It is not a profiler and not a capacity plan.
Every verdict carries a number and the budget it broke, so a regression shows
as `2746ms / 500ms`, not just as red.

All cases stay `type=page` or `type=api`; the signal lives in `tags`. `perf`
marks every one. `vitals` sends it to the browser, `load` holds it back for
`--load`, and `risk` marks a suspicion written from reading the code.

## Where each check runs — cheapest first

| Case | Tags | What it proves | Runs on | Cost |
| --- | --- | --- | --- | --- |
| `PERF-NNN` | `perf` | a page's first byte and full response time, HTML size, compression, redirects | `tf.sh perf run`, curl | free |
| `PERF-API-NNN` | `perf` | an endpoint's p50/p95 over `perf.repeat` requests, response size, paging | `tf.sh perf run`, curl | free |
| `PERF-SITE-001..003` | `perf` | every linked asset arrives, text assets are compressed, static assets are cacheable | `tf.sh perf run`, curl | free |
| `PERF-WV-NNN` | `perf,vitals` | LCP, CLS, TBT, page weight, request count, render-blocking, uncompressed and unsized resources | `perf-auditor`, one browser call | ~2.5k tokens |
| `PERF-RISK-NNN` | `perf,risk` (+`vitals` for a page) | a code pattern that will be slow at scale, proved or cleared at run time | engine or `perf-auditor` | free / one call |
| `PERF-LOAD-NNN` | `perf,load` | error rate and p95 under `perf.load.users` concurrent users | `tf.sh perf load --yes`, curl | free, **real traffic** |

`tf.sh perf cases <routes> <privileged>` writes every family except RISK, for
nothing. `perf-case-author` writes RISK, one call per feature. A perf case
never gets a page model or a recipe, and `run-api` never runs one: `tf.sh perf`
owns their verdicts.

## Measuring honestly

Timing is noisy, so the engine never judges one request:

- the **first request warms the route** and is thrown away (cold caches, lazy
  imports, a JIT);
- a page is judged on the **median** of `perf.page_repeat` (3) requests, an
  endpoint on the **95th percentile** of `perf.repeat` (10);
- a case that fails is **re-measured once** before it is called an app bug —
  `tf.sh perf run --only <id>`. Fast the second time is `flake`, not a bug.

The browser numbers come from an unthrottled browser on the machine running
the suite, so a pass is a floor, not a promise about a phone on 4G. **Never
raise a budget to turn a case green** — change it only when the team agrees
the budget itself was wrong, and say so in the commit.

A 401/403 on a timed endpoint is UNJUDGED, not fast: a refusal says nothing
about the endpoint. A role with no session is UNJUDGED too — run
`/testwright:setup`.

## Budgets

Defaults and the `framework.json` block are in `references/budgets.md`. The
page budgets follow Google's "good" thresholds for Core Web Vitals; the rest
are conservative starting points. Every budget is a `FAIL` when broken, never
a warning — a budget nobody enforces is decor.

## Load testing (`--load`) — opt-in, fenced, and loud about it

Load sends real concurrent traffic, so it has more guards than anything else:

1. the production guard (`allow_remote`) as always, **and** the host must be
   local or listed in `perf.load.allow_hosts` — `allow_remote` alone is not
   enough, because a shared staging box is not yours to stress;
2. `users` and `seconds` are capped by `perf.load.max_users` (20) and
   `perf.load.max_seconds` (60);
3. `tf.sh perf load` without `--yes` only prints the plan. **Show the plan to
   the user and get a yes before running it with `--yes`.**

Targets are `perf.load.targets` (default `/`). A GET only — a load case that
writes would fill the database. HTTP 429 is counted and reported, not treated
as an error: rate limiting under load is often the design working.

## From failure to bug

1. `test-triager` gets each failing perf case, per **testwright:triage**:
   re-measure once; still over budget → `app-bug`; fast now → `flake`; only
   slow against a remote or cold environment → `environment`.
2. `perf-auditor review` reads every failure of the run and writes
   `tests/.cache/perf/causes.txt`, grouping failures that share a cause (one
   bundle failing every page's weight budget is one bug, not twelve).
3. `bug-reporter` files **one bug per cause**, not per case, using the
   severity in `references/bug-patterns.md`, with the measured number, the
   budget, and the suspect file:line from a RISK case's description.

## Out of scope

CPU and memory profiling, flame graphs, database query plans, and anything
that needs an APM agent installed in the app. Lighthouse scores: the numbers
here are the same metrics, measured without adding a dependency. Soak and
capacity testing: `--load` is a smoke test for concurrency bugs, capped at
seconds, not a capacity plan.
