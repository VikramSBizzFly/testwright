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
| 5 | Functional — CRUD & Persistence | 029-036 | 8 | 6/1/1/0 | `page` cases that re-read the record in a fresh request, not just the toast; `--data` (`data-verifier`) writes them per writing flow |
| 6 | Functional — Search & Lists | 037-047 | 11 | 0/8/3/0 | `page` cases: filter, sort, paginate, no-match empty state |
| 7 | Functional — Business Rules | 048-055 | 8 | 3/4/1/0 | `page` + `api`; the rule must hold when posted directly |
| 8 | Functional — Workflow & States | 056-062 | 7 | 2/3/2/0 | flows, plus an illegal transition per state — `--data` (`state-machine-mapper`) reads the machine out of the code |
| 9 | **Field & Form Validation** | 063-080 | 18 | 4/10/4/0 | `references/field-library.md` + `references/validation-rules.md` — the largest single category |
| 10 | Boundary & Data Limits | 081-086 | 6 | 1/3/2/0 | equivalence-class sampling per constrained field |
| 13 | Navigation & Routing | 110-118 | 9 | 1/4/4/0 | `tf.sh routes`, plus deep links, back button, 404; `--links` for broken links, dead anchors and redirect loops |
| 14 | Negative Testing | 119-126 | 8 | 4/3/1/0 | `page` + `api` with the values in `validation-rules.md` |
| 15 | Edge Cases & Error Scenarios | 127-136 | 10 | 5/3/2/0 | `page` + `api`; empty, maximum, concurrent, interrupted; `--resilience` for a page whose API fails, drops or is slow; `--edge` (`concurrency-prober`) for lost updates, double submits and oversells |
| 16 | Security Testing | 137-148 | 12 | 7/4/1/0 | `--security` (**security** skill); `--headers` for CSP, framing, CORS, HSTS, banners and cookie flags |
| 17 | Session & Authentication | 149-156 | 8 | 3/3/2/0 | `--security` + the **auth** skill: expiry, reuse after logout, fixation |
| 18 | Role & Permission | 157-161 | 5 | 3/2/0/0 | the free `tf.sh rbac` sweep, judged from the rendered page |
| 20 | Reports & Exports | 169-177 | 9 | 3/3/3/0 | cases that download and **parse** the file, not just assert a 200: `--edge` (`export-verifier`, `tf.sh export-check`), with rows, columns, encoding and formula injection |
| 21 | File Upload / Download | 178-187 | 10 | 2/4/4/0 | `page` cases from the file-upload kind; `--edge` (`upload-prober`): size, type, renamed and empty files, dangerous names, all benign |
| 23 | API Testing | 198-207 | 10 | 1/6/2/1 | `api` cases — free (`references/api-contracts.md`); `--contract` for response drift from the OpenAPI spec |
| 24 | Integration / End-to-End | 208-216 | 9 | 5/4/0/0 | flows run end to end |
| 27 | Responsive & Resolution | 232-236 | 5 | 0/1/4/0 | `--responsive` |
| 29 | Accessibility | 243-251 | 9 | 0/5/4/0 | `--a11y` |
| 38 | Regression | 305-310 | 6 | 3/3/0/0 | the run itself; `--only-failing`, the flake list, `--impact` for what a change can break, and `tf.sh trend` |
| 40 | Defect Management | 316-321 | 6 | 1/2/3/0 | `tests/bug-report.xlsx` via `/testwright:report --bug`; `--dedupe` for one defect per cause, `--sync` for the issue tracker |
| 41 | Release Readiness / Exit Criteria | 322-329 | 8 | 6/2/0/0 | the run verdict and its exit code; `tf.sh release` GO/NO-GO against the team's criteria, and the `release-gate` sign-off |

## Partly covered — say which part

Claiming these whole is the easiest way to make a report dishonest.

| # | Category | IDs | n | C/H/M/L | Covered / not covered |
| --- | --- | --- | --- | --- | --- |
| 2 | Test Design & Coverage | 008-015 | 8 | 3/5/0/0 | authoring covers the design rules; `--trace` maps requirements to cases (**traceability** skill). Sign-off stays human |
| 11 | UI / Visual Verification | 087-101 | 15 | 0/4/10/1 | layout and rendering yes, via `page` and opt-in visual regression; brand and design-comp fidelity no |
| 12 | UX / Usability | 102-109 | 8 | 0/3/5/0 | mechanical checks only, through `--ux`: submit feedback, double-submit protection, confirming destructive actions, errors at the field, dialog focus, the title. Whether a flow *feels* right is a human judgement |
| 19 | Database & Data Verification | 162-168 | 7 | 4/2/1/0 | what the app exposes, through `--data` round-trip reads; a single read-only `SELECT` when `db.readonly_url` is given. Schema, index and constraint checks stay out |
| 22 | Notification Testing | 188-197 | 10 | 2/5/3/0 | in-app notifications yes; email through `--notifications` against a sandbox outbox (Mailpit/MailHog), never live delivery; SMS only through a provider sandbox |
| 28 | Performance (Observational) | 237-242 | 6 | 0/4/2/0 | `--perf` (**performance** skill): server timing, endpoint p95, page weight, Web Vitals, and code patterns that will be slow at scale. `--load` adds a short, capped concurrency test. Not soak or capacity testing |
| 30 | Localization | 252-258 | 7 | 0/4/3/0 | `--i18n`: clipped labels under a longer locale, RTL, `lang`, locale formats, untranslated strings; `--content` for missing translations and raw keys. Translation accuracy no |
| 34 | Compliance, Privacy & Legal | 283-289 | 7 | 0/5/2/0 | `--privacy` (**privacy** skill): secrets and PII in responses and URLs, exposed API fields, trackers before consent, tokens in browser storage. Not a legal opinion |
| 35 | Content & Documentation | 290-295 | 6 | 0/0/4/2 | `--content`: placeholder copy, leaked templates and values, garbled text, and clear copy defects (`content-reviewer`); not editorial quality |
| 36 | Analytics Verification | 296-299 | 4 | 1/1/2/0 | `--analytics`: whether each event fires, once, with its properties and no personal data. Not whether the warehouse received it |
| 37 | Exploratory / Ad-hoc | 300-304 | 5 | 0/2/3/0 | `--explore`: a time-boxed scout of the riskiest routes, whose oddities become cases, never verdicts. Open-ended human exploration stays human |

## Out of scope — report as out of scope, not as a gap

| # | Category | IDs | n | Why |
| --- | --- | --- | --- | --- |
| 1 | Test Readiness & Entry Criteria | 001-007 | 7 | Process gates — signed-off requirements, environment readiness. Nothing to execute |
| 25 | Browser Compatibility | 217-224 | 8 | One browser per MCP session. At Tier 1/2, `--cross-browser` runs the promoted specs in Firefox and WebKit too; a grid of browser versions stays out |
| 26 | Device & OS Compatibility | 225-231 | 7 | Real devices, not viewport emulation. `--responsive` and `--mobile` (manifest, offline, zoom, input types) are not device checks |
| 31 | Mobile App Specific | 259-270 | 12 | Native apps. This tool tests web apps |
| 32 | Installation & Upgrade | 271-277 | 7 | Deployment and migration, outside a test run |
| 33 | Backup, Recovery & Failover | 278-282 | 5 | Infrastructure behaviour, and destructive by nature |
| 39 | UAT Support | 311-315 | 5 | Human acceptance |
| 42 | Post-Deployment Verification | 330-336 | 7 | Production. The production guard refuses a non-local target unless explicitly allowed. `--post-deploy` is the one exception: a read-only, anonymous smoke check of `postdeploy.base_url`. Anything that writes stays out |

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
