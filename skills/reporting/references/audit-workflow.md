# Audit mode — a full pass over an app, and the records it leaves

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

An ordinary run answers "did anything break?". An **audit** answers a slower
question: *what is the state of this application, what did we actually check,
and what do we still not know?* Use it when someone asks for a QA audit, a
pre-release assessment, or a baseline on an app nobody has tested before.

It is the same engine and the same workbooks. What changes is that coverage and
its limits are the deliverable, not a footnote.

## Where testwright stops

Audit here means **inspect, run and report**. testwright does not repair the
application: your source is read-only, and that is a published guarantee, not
an oversight. The fix step belongs to whoever owns the code — hand them the
defect record and the reproduction, and pick the audit back up afterwards.

A run that changes the app is not a measurement of it.

## The sequence

| Stage | Command | What it produces |
| --- | --- | --- |
| 1. Discover | `/testwright:setup` | stack, tier, routes, roles, sessions |
| 2. Baseline | `/testwright:run --all` | the first honest verdict, including what would not run |
| 3. Initial report | `/testwright:report` | the panel, plus the coverage statement below |
| 4. Record defects | `/testwright:report --bug <id>` | one `BUG-` row per root cause in `tests/bug-report.xlsx` |
| — | *(the team fixes)* | outside this tool |
| 5. Regression | `/testwright:run --only-failing` then `--all` | what the fix moved, and what it broke |
| 6. Second pass | `/testwright:run --fresh` | re-authored against the changed app, so stale tests do not masquerade as passes |
| 7. Final report | `/testwright:report` + `--coverage` | the verdict, the diff against the baseline, the remaining gaps |

Stage 6 matters more than it looks. Re-running the same cases after a fix
proves the fix; **re-deriving** the cases proves the app did not quietly move
somewhere the old cases no longer look.

## Record the baseline before anything changes

Before stage 2, capture what you are measuring: the branch, the commit, whether
the working tree was dirty, the base URL, and which roles have a working
session. A verdict without a build identity cannot be compared to the next one,
and `tf.sh diff` will happily compare two runs against different code.

If a blocker has to be cleared before the suite can run at all, record the
original failure first, then the minimal thing you changed. Both identities,
both results.

## The coverage statement

Every audit report says three things, in this order:

1. **What ran and what it found** — the `tf.sh summary` panel, verbatim.
2. **What did not run, and why** — blocked cases, roles with no session, stages
   skipped, and the checklist categories that are out of scope for this tool
   (`references/qa-checklist.md` in the **authoring** skill names them).
3. **What is still unknown** — the areas with thin or no coverage, from
   `tf.sh cover`.

Point 2 is the one people drop, and it is the one that makes the rest
trustworthy. A report claiming 94% green while three roles never logged in is
worse than no report.

## Records

The two workbooks already are the records — `tests/testcases.xlsx` (Flows, Test
Cases, Results) and `tests/bug-report.xlsx`. Do not build a parallel set of
markdown files beside them; a second copy goes stale within a day.

What is worth keeping alongside, per audit, is short:

```
tests/results/     the run files tf.sh diff compares
tests/evidence/    per-case evidence, credential-free on write
```

A defect record needs: the linked cases, the module and roles, the build, the
preconditions and fixture, steps, expected, actual, the evidence path, and
whether it was executed or established by reading the code. `tf.sh bug from`
fills in what it can look up; the judgement — description, severity, priority —
is the `bug-reporter` agent's, per `references/bug-reports.md` and the
**triage** skill's `references/classification.md`.

## Language that is not allowed

- Never "no bugs found" or "bug free". Say what ran, what passed, and what was
  not covered.
- Never call an audit complete while its coverage is partial — mark the
  coverage and carry on.
- Never turn a `Not Run` into a result because the code looked right.
- Never report a pass for a case that ran without a session.
