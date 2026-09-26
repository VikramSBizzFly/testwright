# The 336-checkpoint QA checklist

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

A 42-category checklist of 336 checkpoints, `QA-001` to `QA-336`. Use it for
two things: as a prompt when authoring (what would a QA lead expect tested
here that the route list never suggests?), and as the denominator when
reporting coverage.

Source priority mix: Critical 99, High 139, Medium 93, Low 5. **That is a test
priority, not an observed defect severity** — a Critical checkpoint you have
not run is not a Critical bug. Nothing here starts as a finding.

## How to use it

- **Authoring.** Take the categories that apply to the feature. A checkout
  form is categories 9, 10, 14, 15 and 7 — not just "does the happy path work".
- **Coverage.** `/testwright:report --coverage` groups gaps by category, and
  says *out of scope* where that is the honest answer instead of counting it
  as a gap. Padding the denominator with checks this tool cannot run makes
  coverage look worse and means less.
- **Don't import the IDs into the workbook.** These are a prompt and a
  denominator. A case gets its own stable `AREA-NNN` id; reference a `QA-` id
  in the scenario text when it is worth the traceability.

`n` is the checkpoint count; `C/H/M/L` the source priority mix.

## Covered by a run

| # | Category | IDs | n | C/H/M/L | How testwright covers it |
| --- | --- | --- | --- | --- | --- |
| 3 | Smoke / Sanity | 016-022 | 7 | 5/2/0/0 | `page` cases tagged `smoke` |
| 4 | Functional — Core Flows | 023-028 | 6 | 3/3/0/0 | the **flows** skill, then one `page` case per journey |
| 5 | Functional — CRUD & Persistence | 029-036 | 8 | 6/1/1/0 | `page` cases that re-read the record in a fresh request, not just the toast |
| 6 | Functional — Search & Lists | 037-047 | 11 | 0/8/3/0 | `page` cases: filter, sort, paginate, no-match empty state |
| 7 | Functional — Business Rules | 048-055 | 8 | 3/4/1/0 | `page` + `api`; the rule must hold when posted directly |
| 8 | Functional — Workflow & States | 056-062 | 7 | 2/3/2/0 | flows, plus an illegal transition per state |
| 9 | **Field & Form Validation** | 063-080 | 18 | 4/10/4/0 | `references/field-library.md` + `references/validation-rules.md` — the largest single category |
| 10 | Boundary & Data Limits | 081-086 | 6 | 1/3/2/0 | equivalence-class sampling per constrained field |
| 13 | Navigation & Routing | 110-118 | 9 | 1/4/4/0 | `tf.sh routes`, plus deep links, back button, 404 |
| 14 | Negative Testing | 119-126 | 8 | 4/3/1/0 | `page` + `api` with the values in `validation-rules.md` |
| 15 | Edge Cases & Error Scenarios | 127-136 | 10 | 5/3/2/0 | `page` + `api`; empty, maximum, concurrent, interrupted |
| 16 | Security Testing | 137-148 | 12 | 7/4/1/0 | `--security` (**security** skill) |
| 17 | Session & Authentication | 149-156 | 8 | 3/3/2/0 | `--security` + the **auth** skill: expiry, reuse after logout, fixation |
| 18 | Role & Permission | 157-161 | 5 | 3/2/0/0 | the free `tf.sh rbac` sweep, judged from the rendered page |
| 20 | Reports & Exports | 169-177 | 9 | 3/3/3/0 | `page` cases that download and **parse** the file, not just assert a 200 |
| 21 | File Upload / Download | 178-187 | 10 | 2/4/4/0 | `page` cases from the file-upload kind |
| 23 | API Testing | 198-207 | 10 | 1/6/2/1 | `api` cases — free (`references/api-contracts.md`) |
| 24 | Integration / End-to-End | 208-216 | 9 | 5/4/0/0 | flows run end to end |
| 27 | Responsive & Resolution | 232-236 | 5 | 0/1/4/0 | `--responsive` |
| 29 | Accessibility | 243-251 | 9 | 0/5/4/0 | `--a11y` |
| 38 | Regression | 305-310 | 6 | 3/3/0/0 | the run itself; `--only-failing`, and the flake list |
| 40 | Defect Management | 316-321 | 6 | 1/2/3/0 | `tests/bug-report.xlsx` via `/testwright:report --bug` |
| 41 | Release Readiness / Exit Criteria | 322-329 | 8 | 6/2/0/0 | the run verdict and its exit code |

## Partly covered — say which part

Claiming these whole is the easiest way to make a report dishonest.

| # | Category | IDs | n | C/H/M/L | Covered / not covered |
| --- | --- | --- | --- | --- | --- |
| 2 | Test Design & Coverage | 008-015 | 8 | 3/5/0/0 | authoring covers the design rules; sign-off and traceability to requirements are human |
| 11 | UI / Visual Verification | 087-101 | 15 | 0/4/10/1 | layout and rendering yes, via `page` and opt-in visual regression; brand and design-comp fidelity no |
| 12 | UX / Usability | 102-109 | 8 | 0/3/5/0 | mechanical checks only — focus order, feedback on submit. Whether a flow *feels* right is a human judgement |
| 19 | Database & Data Verification | 162-168 | 7 | 4/2/1/0 | only what the app exposes. Direct schema, index and constraint checks need database access testwright does not take |
| 22 | Notification Testing | 188-197 | 10 | 2/5/3/0 | in-app notifications yes; email and SMS only against an outbox or provider sandbox, never live delivery |
| 28 | Performance (Observational) | 237-242 | 6 | 0/4/2/0 | page-level timings from a run (**signals** skill). Not load, soak or capacity testing |
| 30 | Localization | 252-258 | 7 | 0/4/3/0 | layout under a longer locale and RTL yes; translation accuracy no |
| 34 | Compliance, Privacy & Legal | 283-289 | 7 | 0/5/2/0 | observable behaviour — consent recorded, PII not leaked into a response. Not a legal opinion |
| 35 | Content & Documentation | 290-295 | 6 | 0/0/4/2 | presence of help text and error copy; not editorial quality |
| 36 | Analytics Verification | 296-299 | 4 | 1/1/2/0 | whether the event fires, from network requests. Not whether the warehouse received it |
| 37 | Exploratory / Ad-hoc | 300-304 | 5 | 0/2/3/0 | by definition unscripted; a run can suggest where to look, not do it |

## Out of scope — report as out of scope, not as a gap

| # | Category | IDs | n | Why |
| --- | --- | --- | --- | --- |
| 1 | Test Readiness & Entry Criteria | 001-007 | 7 | Process gates — signed-off requirements, environment readiness. Nothing to execute |
| 25 | Browser Compatibility | 217-224 | 8 | One browser per run; cross-browser needs a grid this does not drive |
| 26 | Device & OS Compatibility | 225-231 | 7 | Real devices, not viewport emulation. `--responsive` is not a device check |
| 31 | Mobile App Specific | 259-270 | 12 | Native apps. This tool tests web apps |
| 32 | Installation & Upgrade | 271-277 | 7 | Deployment and migration, outside a test run |
| 33 | Backup, Recovery & Failover | 278-282 | 5 | Infrastructure behaviour, and destructive by nature |
| 39 | UAT Support | 311-315 | 5 | Human acceptance |
| 42 | Post-Deployment Verification | 330-336 | 7 | Production. The production guard refuses a non-local target unless explicitly allowed |

## Beyond the checklist

**SEO** is not one of the 42 categories, so it adds nothing to the coverage
denominator. `--seo` covers it anyway (**signals** skill): whether each public
page can be indexed and what it shows in a search result, robots.txt, the
sitemap, soft 404s, duplicate titles and structured data. Rankings, keywords
and backlinks are out of scope.

## Two rules about counting

- **A shared root cause is one defect.** One bug that trips eight checkpoints
  is one `BUG-` record linked to eight, not eight bugs.
- **Never report "no bugs".** A finished run with everything passing means the
  cases that ran, passed. No checklist proves absence, and this one does not
  claim to.
