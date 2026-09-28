---
name: triage
description: Diagnose why a case failed and assign a verdict — app bug, stale test, environment, or flake — with the evidence each verdict requires. Use whenever a failing/error row needs a root cause, before filing a bug or touching pass_streak/flake_count, or when a case fails on a locator and might self-heal.
---

# Triage

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Delegate one failing case at a time to the `test-triager` agent; look across
runs for instability with `flake-analyst`, and judge a `tags=visual` diff with
`visual-reviewer`.

**A verdict decides whether a bug is recorded.** Hand every case triaged
`app-bug` to the `bug-reporter` agent, which writes it into
`tests/bug-report.xlsx` with `tf.sh bug from`. `stale-test`, `environment` and
`flake` never become bugs: an out-of-date test, a server that was down, and a
case that flips on its own are not defects in the app, and recording them
trains a team to stop reading the bug sheet. That is why a verdict needs the
evidence below before it is assigned.

A verdict without evidence is a guess. Every one of the four categories below
requires something concrete before you assign it — "probably flaky" is not a
diagnosis, it is how real bugs get waved away.

| Verdict         | Required evidence                                                                                                                         |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **app bug**     | actual output contradicts `expected` on a fresh, reproduced run; behaviour, not markup, is wrong                                          |
| **stale test**  | the app changed on purpose (route moved, copy changed, field renamed) — cite the diff or source file that shows it                        |
| **environment** | preflight/login failed, non-2xx before the app logic ran, or a dependency (DB, third-party API) was unreachable — cite the specific error |
| **flake**       | the case flipped verdict across runs with **no** code change in `source_files` between them — cite both run timestamps                    |

Never assign a verdict from the failure row alone. Re-run once against fresh
evidence (`tests/evidence/<id>/`) before deciding — a single sample cannot
distinguish app bug from environment.

## Performance failures (`tags=perf`) — re-measure before blaming the app

A timing is a sample, not a fact. The re-run above is, for a perf case, a
re-measure:

- **An engine case** (`PERF-NNN`, `PERF-API-NNN`, `PERF-SITE-*`, an api
  `PERF-RISK-NNN`): `tf.sh perf run --only <id>`. Still over budget, by a
  similar margin → **app bug**. Inside budget now → **flake**, citing both
  numbers. Slow only against a remote or freshly started environment, while
  the same route is fast locally → **environment**.
- **A browser case** (`tags=vitals`): the findings that are not timings —
  bytes over budget, a render-blocking file, an uncompressed or unsized
  resource, too many requests — are deterministic and need no re-measure:
  **app bug**. A failure that rests only on LCP or TBT needs a second
  `perf-auditor vitals` call first; return `NEXT re-measure` and let the main
  thread make it.
- **A load case** (`PERF-LOAD-NNN`): a 5xx rate over budget is an **app bug**
  on the first run — errors under concurrency do not come from noise. A p95
  failure alone gets one re-run of `tf.sh perf load --yes`, with the user's
  say-so, since it sends traffic again.

Never re-measure by raising the budget. Patterns and severities for the bug:
the **performance** skill's `references/bug-patterns.md`.

## Locator failure vs assertion failure — self-heal only the former

A **locator** failure (element not found, selector timeout) can be self-healed
by re-deriving the locator from a fresh snapshot and reporting the patch — never
silently. An **assertion** failure (found the element, value is wrong) means the
app did something different than expected — that is never self-healed. Decline
to self-heal if the fresh snapshot shows _behaviour_ changed, not just markup —
that's an app bug or stale test wearing a locator failure's clothes. Full
procedure and the decline criteria are in `references/self-heal.md`.

## Findings that are not a failing case

The four verdicts explain why a case failed. They do not cover the finding with
no verdict yet, the check that could not run, or the disagreement that is
nobody's bug — a proposed bound the app does not have, with no project rule
saying which is right, is a **Decision needed**, not a `Fail`. Those
dispositions, and why severity (observed impact) and priority (when it gets
fixed) are two separate judgements: `references/classification.md`.

## Flake quarantine

A case that flips PASS/FAIL across runs with no matching change in its
`source_files` is unstable, not informative. After it flips **3 times**
(`flake_count` on the row), set:

```sh
tf.sh set <id> status=Flaky flake_count=<n>
```

`flaky` cases are excluded from the gating verdict but never dropped from the
CSV and never hidden from the run report — list them in their own section,
separate from real failures, per the **testwright:reporting** skill. Mixing them into the
failure list is what trains users to stop reading the failure list.

`pass_streak` resets to 0 on any FAIL; a long streak after a flip is what
distinguishes "fixed" from "still flaky" — do not clear `flake_count` just
because the streak recovered.
