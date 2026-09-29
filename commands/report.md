---
description: Show the last test result again
---

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Show the last result. Arguments: `$ARGUMENTS`
(`--coverage` for gaps · `--bug <id>` for a bug report · `--flakes` for unstable
cases · `--publish` for a shareable page · `--trend` · `--release` · `--trace`
· `--garden` · `--dedupe` · `--sync` · `--explain <id>`).

Run `tf.sh xlsx --status` first so the workbook matches the last run, then
`tf.sh summary` and **print its output verbatim. Add nothing.** It already
renders the verdict, what regressed, what got fixed and what to do next.
Re-describing it costs more than the run did.

Load the **reporting** skill for anything beyond that.

**`--coverage`** → the `coverage-analyst` agent. It runs
`tf.sh cover tests/.cache/routes.txt` and returns uncovered and thin routes
grouped by area and ranked by risk — behind a login, takes input, touches money
or personal data — capped at 20 lines. Print what it returns; do not re-list.

**`--bug <id>`** → the `bug-reporter` agent. It reads `tests/evidence/<id>/` and
`source_files` so the evidence never reaches this conversation, records the bug
in `tests/bug-report.xlsx` with `tf.sh bug from`, and returns a ready
`gh issue create`. Offer the command; let the user run it. It declines a case
triage called anything other than an app bug. **Never put a password in a bug
report.**

Whenever bugs exist, say how many are open and point at `tests/bug-report.xlsx`
— `tf.sh bug list --status Open` has the rows. The run panel already names any
open bug whose case now passes; that is the retest to suggest.

**`--flakes`** → the `flake-analyst` agent: cases that flip verdict across runs
with no matching source change, and the `tf.sh set <id> status=Flaky` commands
to quarantine them. It proposes; you apply only if the user says so.

**`--publish`** → `tf.sh render`, then publish it as an Artifact — after
checking no credential appears anywhere in the HTML.

**`--trend`** → the `trend-reporter` agent. It says, per check family,
whether quality is rising, falling or flat, from `tf.sh trend`. Ask it for a
dashboard (`tests/results/trend.html`) only when the user wants one; publish
it as an Artifact the same way as `--publish`.

**`--release`** → the `release-gate` agent. `tf.sh release` decides GO or
NO-GO from the `"release"` criteria in `tests/framework.json`. The agent
writes the sign-off page in `tests/release/`. **A NO-GO stays a NO-GO**
unless the user names who waives which failed criterion. Pass those names
into the agent's prompt; never invent a waiver.

**`--trace`** → the `requirements-tracer` agent, which reads the
requirements into `tests/requirements.txt` and maps the cases (**traceability**
skill). Print its `TRACE` and `GAPS` lines. Offer `case-author` for the
uncovered requirements.

**`--garden`** → the `suite-gardener` agent: duplicates, cases on dead routes,
stale flakes and never-run cases, proposed in `tests/.cache/garden.txt`.
Show the proposals, and apply only the ones the user approves by calling
the agent again with them.

**`--dedupe`** → the `bug-deduper` agent: open bugs grouped by root cause in
`tests/.cache/bug-groups.txt`. Linking duplicates happens only on the user's
yes, and only through QA Comments.

**`--sync`** → the `issue-syncer` agent. First it lists the open bugs with
no issue, and the linked issues that were closed upstream (to retest).
Filing issues publishes them, so it files only the bugs the user approves,
by number.

**`--explain <id>`** → load the **explain** skill and answer in plain words:
what the case checks, what happened and whose problem it is, and the one
next step. No agent is needed.
