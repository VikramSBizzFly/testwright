---
name: traceability
description: Tie what the product promised to the tests that prove it - requirements, user stories and acceptance criteria in tests/requirements.txt, mapped to cases, with tf.sh trace reporting which requirements are passing, failing, not run or untested; and tie a code change to the cases it can break. Use for /testwright:report --trace, /testwright:run --impact, when a user asks which requirements are untested, what a PR affects, or needs traceability for an audit or sign-off.
---

# Traceability

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Two directions, one idea: a test is worth what it proves.

- **Requirement → cases.** Every promise has a case whose pass shows the
  promise holds (`requirements-tracer`, `tf.sh trace`).
- **Change → cases.** Every change runs the cases it can break
  (`pr-impact-analyst`, `tf.sh impacted`).

## `tests/requirements.txt`

Committed, human-readable, and one requirement per line, with four
tab-separated fields:

```
REQ-001	An admin can list users	docs/prd.md:20	API-001,AUTH-003
PROJ-142	A sent invoice cannot be edited	jira:PROJ-142	INV-014
```

- **id**: the source's own id when it has one (`PROJ-142`, `AC-3`), else
  `REQ-NNN`. It is stable forever: a requirement keeps its id when reworded.
- **requirement**: one testable statement. A story with five acceptance
  criteria is five lines.
- **source**: `file:line` or a ticket id, so anyone can check the wording.
- **cases**: the ids that prove it. A case also counts when its Test
  Scenario or Test Description names the requirement id (`covers PROJ-142`),
  which is how a person maps one by hand.

People may edit this file. `requirements-tracer` keeps their lines and
changes only the case column of lines it wrote.

## What "covered" means

A case covers a requirement when **passing it would show the requirement
holds**. A page that loads covers nothing but "the page loads". "A
logged-out visitor sees a login page on /reports" covers "reports are for
signed-in users". Mapping loosely makes every requirement green and the
report worthless.

`tf.sh trace` classifies each requirement:

| Status | Meaning |
| --- | --- |
| PASSING | at least one covering case, and none failing |
| FAILING | a covering case fails: the promise is broken right now |
| NOT-RUN | covered on paper, never proved: every covering case is Not Run, Blocked or Skipped |
| UNCOVERED | nothing tests it |

`tf.sh trace --gaps` shows only FAILING and UNCOVERED, the list that matters
for a sign-off.

## Change impact

`tf.sh impacted <base>` is the free, direct part: cases whose own
`source_files` changed. `pr-impact-analyst` adds what hashing misses:
callers of a changed helper, flows whose code path crosses the change, and a
risk rating. It writes the selection to `tests/.cache/impact.txt`, which
`/testwright:run --impact` runs. The selection always includes the `smoke`
cases, and on a high-risk change every `security` case.

## Out of scope

Writing requirements, judging whether they are good ones, and syncing them
with a requirements tool. The tracer reads what exists and never invents a
requirement from the code: code is what was built, not what was asked for.
