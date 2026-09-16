# Classification — dispositions, severity and priority

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

The four verdicts in the **triage** skill answer one question: *why did this
case fail?* They apply to a failing row and decide whether a bug is recorded.

This file covers the things that are not a failing row — the finding that has
no verdict yet, the check that could not run, the disagreement that is nobody's
bug — and how to separate how bad something is from when it gets fixed.

## Dispositions

Use these in the case's notes or the bug record, alongside (never instead of) a
verdict.

| Disposition | Means | What it needs |
| --- | --- | --- |
| **Confirmed** | Reproducible failure, or a clear contract violation | The evidence the `app bug` verdict already requires. Say whether it was executed or established by reading the code — they are not the same claim |
| **Potential** | Plausible concern, not yet proven | The exact step that would settle it. **Never counted in the defect total** |
| **Preventive** | A worthwhile improvement with no evidence of current incorrect behaviour | Say plainly that nothing is broken. A missing nice-to-have is not a defect |
| **Already satisfied** | The app already does this | Still needs a run to claim a pass. "It looks implemented" is not a verdict |
| **Decision needed** | Intended behaviour is genuinely unresolved | The question, the options, and who decides. The common case: `references/field-library.md` in the **authoring** skill proposes a bound the app does not have, and no project rule says which is right. That is **not** a `Fail` |
| **Blocked** | Applicable, but could not be run | Why — no session, no browser, a dependency down, a human step. This is the `environment` verdict's disposition, and it is a coverage gap, never a pass |

An unreadable app, an unavailable browser and a missing database are all
**Blocked**. None of them is a clean result, and none should be reported as one.

## Severity is not priority

Two separate judgements, and the `bug-reporter` agent records both.

**Severity — observed impact.** What actually happens, measured on the run you
did:

| Severity | Observed |
| --- | --- |
| Critical | Major failure, a material security compromise, or data loss |
| High | An important workflow substantially fails |
| Medium | A limited failure with a usable workaround |
| Low | Minor presentation or maintainability |

**Priority — when it gets fixed.** Derived from severity plus exposure, how
many users hit it, what it blocks, and what the team already planned.

A Critical defect on a feature behind a flag nobody has enabled may be a low
priority. A Medium defect on the login page may be the first thing fixed.
Collapsing the two into one number is how a bug sheet stops being read.

Two traps:

- **A source checklist priority is not a severity.** The **authoring** skill's
  `references/qa-checklist.md` marks 99 checkpoints Critical. That is how important the *check* is, not how
  bad any finding is. Never copy it into a bug's severity field.
- **Never copy a scanner's severity.** Validate the premise first — a tool that
  flags a missing index or a "weak" rule has not run your app.

## One root cause, one bug

A single defect that trips eight cases is one `BUG-` record linked to eight
cases, not eight records. Duplicating a symptom per case inflates the count and
buries the fix. `tf.sh bug from` links additional cases to an existing record
rather than opening a second one.

## Status is four things, not one

The workbook's `Status` column is the verification result and nothing else.
When a report needs to say more, keep these apart: whether the check **applies**
to this product, whether the behaviour is **implemented**, whether it has been
**verified** by an actual run, and the **state of any defect** found. A check
can be applicable, implemented, unverified and defect-free all at once — and
reporting that as a pass would be a lie.
