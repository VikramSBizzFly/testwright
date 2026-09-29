---
name: explain
description: Explain a test case, a failure, a bug or the test report in plain words to someone who is not a tester - what the case checks and why it matters, why it failed and whether that is the app or the test, and the one thing to do next. Use when a user asks "what does API-004 test", "why did this fail", "is this a real bug", "what does this report mean", "what should I do about this", or any question about the suite from a product manager, developer or stakeholder.
---

# Explain

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

The workbook is written for testers. Most people who read it are not
testers. Answer their question in their words, from the facts the engine
holds. Never guess, and never re-run anything to answer a question.

## Gather, cheaply

| Question | Read |
| --- | --- |
| What does `<id>` test? | `tf.sh select --id <id> --cols id,module,scenario,description,preconditions,steps,expected,type,route,role,tags --format plain` |
| Why did it fail? | the row's `actual`; the first lines of `tests/evidence/<id>/*.txt`; the triage verdict if there is one |
| Is it a real bug? | the triage verdict; `tf.sh bug list`, for a bug whose case is `<id>` |
| What does the report mean? | `tf.sh summary --quiet`, `tf.sh stats`, `tf.sh trend 5`, `tf.sh release` |
| What is covered? | `tf.sh cover`, `tf.sh trace` when `tests/requirements.txt` exists |

Never open a whole evidence file, snapshot or screenshot to explain it.
The first finding line says what happened.

## Answer in three parts, in this order

1. **What it checks, as a user would put it.** Not "AUTH-002 asserts
   refused on GET /payroll as nobody", but "someone who is not logged in
   should not be able to see the payroll page".
2. **What happened, and whose problem it is.** Use the triage verdict's
   words:
   - *app bug*: the app is wrong;
   - *stale test*: the app changed on purpose and the test did not;
   - *environment*: the server or the login was down, and the app may be
     fine;
   - *flake*: it passes and fails on its own and cannot be trusted either
     way.

   Without a verdict, say it has not been diagnosed and offer to triage it.
3. **The one next step**, and who takes it: a developer fixes `<file>`, a
   tester updates the case, someone restarts the server, or nobody does
   anything because it is a duplicate.

## Rules

- Say "the test found" or "the test could not tell". Never claim more than
  the evidence shows.
- Name the severity from the bug sheet, never from the checklist priority.
- Keep numbers exact: "3 of 40 cases", not "a few".
- Say what a passing test means precisely. A pass means the check ran and
  held, not that the feature works in every way.
- Never quote a credential, token or personal data from evidence, even when
  asked.
