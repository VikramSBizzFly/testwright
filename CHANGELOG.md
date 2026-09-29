# Changelog

Notable changes to this plugin. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: [semver](https://semver.org), with the meaning of each bump spelled
out under **Versioning** in [README.md](README.md). `tf.sh version` prints the
version you have installed.

`0.2.0` and `0.3.0` were developed together and landed on `main` as one series
of reviewed pull requests (#1-#6), split by area: the engine and workbook, the
agents, the skills, plain-language activation, command wiring, and docs.

## [2.7.0] - 2026-09-29

A **minor** release: eight new flags, four engine subcommands, seven agents
and three skills. Existing suites keep working untouched.

This is phase 4 of the roadmap: the words, the emails, and what happens when
things go wrong or wear on.

### Added

- **`--content`** (`tf.sh content cases|run`, `scripts/lib/content.sh`):
  - `CONTENT-NNN`, one per page, reads the visible text for placeholder
    copy, markers, unfilled templates, leaked `undefined`/`NaN`/`[object
    Object]`, missing translations, raw i18n keys, mojibake and server
    warnings. A blank page fails too.
  - Each check has a name `content.skip` can switch off.
  - The **`content-reviewer`** agent reads client-rendered pages in a
    browser. Its review fails only copy defects: developer-speak errors,
    empty empty-states, clear typos, two names for one thing, and controls
    that don't say what they do.
- **`--i18n`**: the **`i18n-auditor`** agent opens each page in every locale
  and fails on:
  - labels clipped or overflowing, but only where the base locale fits;
  - right-to-left locales that are not mirrored;
  - a wrong `lang`;
  - base-locale date and number formats;
  - untranslated strings.
- **`--notifications`** (`tf.sh notifications mark|cases|run`,
  `scripts/lib/notifications.sh`, `scripts/tf-outbox.py`). It reads a
  local sandbox outbox, Mailpit or MailHog, and never a remote one.
  - `NOTIF-SITE-001` judges every email since the mark. Each needs a
    subject and a plain-text part, and must contain no password, key,
    token, card number or unfilled template. Its same-site links must
    resolve.
  - The **`outbox-checker`** agent writes one `NOTIF-NNN` per
    email-sending flow (`to: ... | subject: ...`), plus its trigger case.
- **`--resilience`**: the **`resilience-prober`** agent fails each page's
  API in the browser only: a 500, a dropped connection, a slow answer. It
  expects a readable error, not a stuck spinner, a blank page or
  `undefined`.
- **`--memory`**: the **`leak-hunter`** agent moves between an SPA's views
  ten times and measures the heap after forced garbage collection (Chrome
  DevTools Protocol). It fails a steady rise over `robustness.leak_mb`, or
  DOM nodes that keep growing.
- **`--cross-browser`**: the **`cross-browser-runner`** agent runs the
  promoted specs in Chromium, Firefox and WebKit through the project's own
  Playwright config, and reports only the verdicts that differ (Tier 1/2).
- **`--analytics`**: the **`analytics-verifier`** agent checks each tracked
  event fires once, with its properties and no personal data. The events
  come from a tracking plan or from the code's `track()` calls.
- **`--post-deploy`** (`tf.sh postdeploy [--yes]`, `scripts/lib/postdeploy.sh`):
  a read-only, anonymous smoke check of `postdeploy.base_url`. It checks:
  - each route answers 2xx within `max_ms`;
  - each page has a title and no stack trace;
  - the TLS certificate has more than `min_cert_days` left.

  GET only, capped and paced; without `--yes` it only prints the plan. It
  is the one engine command that reaches a remote host on purpose, fenced
  by its own settings.
- **`tf.sh audit-cases i18n|resilience|memory`**: one agent-audited case per
  page, written for free.
- **Skills**: **localization**, **notifications** and **robustness**.
- **`framework.json`** gains `content`, `i18n`, `notifications`,
  `robustness`, `analytics` and `postdeploy` blocks.
- **The demo app** has new faults, and the demo serves a Mailpit-compatible
  outbox:
  - a `/welcome` page with every content bug, and a German version with a
    clipped label;
  - an SPA feed that spins forever when its API fails and leaks about 1 MB
    per navigation;
  - a password-reset email with the password in clear, no text part, and a
    link that 404s.

### Changed

- **The execution skill lists every browser agent in one place.** The rule
  is one at a time; the lists in individual agents are reminders.
- `stack-detector` now owns only the keys it detects, and keeps every other
  `framework.json` key as the user's setting. This replaces a list of
  protected keys that grew with every release.
- The QA checklist now credits categories 15, 22, 30, 35 and 36. Its
  out-of-scope notes for 25 (browsers) and 42 (post-deploy) say what is now
  covered.

### Fixed

- **The demo app sent the wrong `Content-Length` for non-ASCII pages.** It
  counted characters, not bytes, which truncated any page with a character
  like `ü`.

## [2.6.0] - 2026-09-28

A **minor** release: one new run flag, seven report flags, four engine
subcommands, seven agents and two skills. Existing suites keep working
untouched.

This is phase 3 of the roadmap: what the suite says over time, and what a
team does with it.

### Added

- **Four free engine reports** (`scripts/lib/insight.sh`):
  - `tf.sh trend [N] [--family F]` shows each run's pass rate, grouped by
    check family, with a sparkline.
  - `tf.sh release [--json]` returns GO or NO-GO (exit 1) against
    `"release"` in `framework.json`. It takes its facts from the store and
    the bug sheet, not from one result file:
    - the pass rate of judged cases;
    - no failing security case;
    - every smoke case passing;
    - the open Critical and High bugs;
    - the age of the last run.
  - `tf.sh trace [--gaps]` reads `tests/requirements.txt` and marks each
    requirement passing, failing, not run or uncovered.
  - `tf.sh dupes [0.7]` lists near-duplicate cases: same type, route and
    role, with most words shared.
- **`/testwright:run --impact <base|PR>`**. The `pr-impact-analyst` agent
  starts from `tf.sh impacted` and follows the change outward, through
  callers and flow code paths, two hops. It rates the risk and writes the
  selection to run. The selection always includes the smoke cases, and on a
  high-risk change every security case.
- **`/testwright:report --trend`**: `trend-reporter` says per family whether
  quality is rising, falling or flat, with an optional self-contained HTML
  dashboard.
- **`--release`**: `release-gate` writes the sign-off page. A NO-GO stays a
  NO-GO unless a named person waives each failed criterion.
- **`--trace`**: `requirements-tracer` reads the PRD, stories or a ticket
  export into `tests/requirements.txt` and maps the cases whose pass proves
  each requirement (the **traceability** skill).
- **`--garden`**: `suite-gardener` proposes what to merge, retire, repoint,
  restore or promote. It applies only what is approved, and never deletes a
  row.
- **`--dedupe`**: `bug-deduper` groups open bugs by a nameable root cause
  and links duplicates through QA Comments on approval.
- **`--sync`**: `issue-syncer` files GitHub issues for open bugs on
  approval, redacted, and records the link. It reads linked issues back to
  find bugs closed upstream that need a retest.
- **`--explain <id>`**: the **explain** skill answers "what does this test,
  why did it fail, what now" in plain words.
- **`"release"` in `framework.json`**: `min_pass_rate`, `max_open_critical`,
  `max_open_high`, `require_security_clean`, `require_smoke_pass`,
  `max_age_hours`.

### Changed

- The QA checklist credits categories 2, 38, 40 and 41. The `qa` skill and
  the prompt hint know the new report questions.

## [2.5.0] - 2026-09-28

A **minor** release: three new flags, two engine subcommands, four agents
and three skills. Existing suites keep working untouched.

This is phase 2 of the roadmap: what the app gives away, and whether what it
saves is what it was sent.

### Added

- **`/testwright:run --privacy`** (`tf.sh privacy cases|run`,
  `scripts/lib/privacy.sh`, the **privacy** skill).
  - `PRIV-NNN`, per page, over curl:
    - keys, private keys, Luhn-valid card numbers and SSN patterns in the
      source;
    - passwords and tokens in link URLs;
    - password forms submitted by GET;
    - a personal page without `Cache-Control: private` or `no-store`.
  - `PRIV-API-NNN`: the field names of each GET response, so an API that
    serialises `password_hash`, `secret` or `ssn` is caught.
  - `PRIV-SITE-001`: a privacy-policy link that loads.
  - Evidence names the kind of thing found and a masked prefix, never the
    value.
- **The `privacy-auditor` agent** (`PRIV-BR-NNN`). In a fresh browser it
  checks third-party requests before consent against
  `references/trackers.md`, and whether rejecting consent stops them. It
  also flags tokens, emails and card numbers in localStorage or
  sessionStorage, and session-like cookies readable from script.
  `privacy.consent_required`, `privacy.allow_hosts` and `privacy.trackers`
  in `framework.json` tune it.
- **`/testwright:run --data`** (the **data-integrity** skill):
  - **`state-machine-mapper`** reads each record's states, allowed moves and
    guarding lines out of the code into `tests/.cache/states.txt`. It writes
    a `STATE-NNN` case for every forbidden move, actions with no state check
    first.
  - **`data-verifier`** writes `DATA-NNN` round-trip cases for every writing
    flow:
    - every field reads back exactly, at its longest and with Unicode;
    - computed fields are right, and client-sent protected fields are
      ignored;
    - a delete leaves no orphans.

    It can add one read-only `SELECT` when `db.readonly_url` is given.
  - Both write data, so both arrive `Skipped` for `--allow-destructive`.
- **`/testwright:run --seed`** (the **test-data** skill):
  - **`tf.sh preconditions`** lists every data need the cases state, with
    the cases that depend on it, from Preconditions and from volume-stating
    Test Data.
  - **`test-data-seeder`** plans how to create that data through the
    project's own seeds or its API, never raw SQL. It writes
    `tests/data/seed.sh`, which is marked `tw-seed`, idempotent and
    local-only, and runs it only on the user's yes.
- **The demo app**:
  - a users endpoint that serialises `password_hash`;
  - a change-password form sent by GET;
  - an email in an HTML comment and a tracker script;
  - orders whose `cancel` skips the state check that `ship` makes;
  - notes cut to 20 characters on save;
  - a privacy page.

### Changed

- The cost projection's `vitals` row is now `audits`. It counts every case
  that needs one browser audit call: Web Vitals and privacy browser cases.
- `run-api`, compiling and the browser queue leave `tags=privacy` to
  `tf.sh privacy` and `privacy-auditor`. `privacy-auditor` joins every
  browser agent's serial list.
- The QA checklist now credits categories 5, 8, 19 and 34.
- **`tf.sh next-id <PREFIX> <n>`** returns a batch of ids. Nothing is reserved
  until a merge, so an agent that asked once per case got the same id every
  time. Every authoring agent now asks for its batch at once.

### Fixed

- **`--allow-destructive` never ran a Skipped api case.** Authoring parks a
  destructive case as `Skipped`, and the execution skill says
  `--allow-destructive` un-parks it. `run-api` skipped every Skipped case
  before it looked at the flag, so an api case marked that way could never
  run. It now runs destructive-tagged Skipped cases under the flag; any
  other Skipped case stays skipped.
- **A templated route is UNJUDGED, not a 404.** An api case whose route still
  holds a `{param}` used to request the literal template and fail. It now
  says to seed a record and set the route.

Found by running `state-machine-mapper` against the demo app. Its STATE
cases for cancelling a shipped or delivered order fail on the demo's real
bug, and its cases for illegal `ship` and `deliver` moves pass.

## [2.4.0] - 2026-09-28

A **minor** release: three new flags and three engine subcommands, all free
over curl. No new agents. Existing suites keep working untouched.

This is phase 1 of the roadmap: the checks that need no browser and no tokens
and still find real bugs.

### Added

- **`/testwright:run --headers`** (`tf.sh headers cases|run`,
  `scripts/lib/headers.sh`).
  - `HDR-NNN`, one per page, checks:
    - a CSP that does not allow `'unsafe-inline'` script;
    - `X-Frame-Options` or `frame-ancestors`;
    - `nosniff`;
    - no Referrer-Policy that leaks full URLs;
    - HSTS on https.
  - `HDR-SITE-001..004`, across the site:
    - CORS never trusts an arbitrary or `null` origin with credentials;
    - no version banner, and no stack trace on an error page;
    - session cookies are HttpOnly, SameSite, and Secure on https;
    - http redirects to https.
  - A project can rule a check out with `headers.skip`.
- **`/testwright:run --links`** (`tf.sh links cases|run`,
  `scripts/lib/links.sh`).
  - `LINK-NNN`, one per page:
    - every same-site link resolves, with no redirect loop;
    - every `#anchor` exists;
    - an https page loads nothing over http.
  - `LINK-SITE-001` crawls from `/` for pages the route list missed.
  - Off-site links are never fetched. A link that could change state (sign
    out, delete, cancel) is never followed.
- **`/testwright:run --contract`** (`tf.sh contract cases|run`,
  `scripts/lib/contract.sh`, `scripts/tf-contract.py`).
  - `CONTRACT-NNN`, one per GET operation in the OpenAPI 3 or Swagger 2 JSON
    spec, compares the live status and body with the response schema.
  - The spec is found in the project, or fetched from where the app serves
    it.
  - Drift is reported by JSON path. `contract.strict` also reports
    undocumented fields.
  - The checker uses only the standard library. Without Python the cases are
    UNJUDGED.
- **`scripts/lib/checks.sh`**, the shared run loop, which is where the next
  families will plug in:
  - page selection;
  - case rows;
  - cached fetching;
  - evidence;
  - folding verdicts back;
  - `.meta` and the summary.
- **`tf.sh login` keeps cookie attributes**: the names and flags of the
  cookies a login sets, never their values, in
  `tests/.auth/<role>.setcookie`, for the cookie-flag check.
- **`framework.json`** has new `headers`, `links` and `contract` blocks.
- **The demo app** has deliberate faults for each check:
  - only `/` sends good security headers;
  - `/api/profile` reflects any Origin with credentials and drops a field
    its `/openapi.json` contract requires;
  - `/about` links to a missing page and to a missing anchor.

### Changed

- `tf.sh cost` has a free `checks` bucket, and the summary counts the new
  families as free.
- `run-api` leaves `tags=contract` cases to `tf.sh contract`. Compiling, page
  modelling and the browser queue skip every engine-judged tag.
- The security, signals and authoring skills, the `qa` skill, the prompt hint
  and the QA checklist (categories 13, 16 and 23) know about the new flags.

## [2.3.0] - 2026-09-28

A **minor** release: two new flags, a new engine subcommand, two new agents
and a new skill. Existing suites keep working untouched, and nothing needs
migrating.

`tags=perf` and `perf_budget_ms` were documented, but nothing read them: no
case was ever generated, and no run ever timed anything. Most of what makes an
app slow is visible from outside without a browser — time to first byte, how
big a response is, whether it is compressed or cached, how an endpoint's
latency spreads — so the engine does that over curl for no tokens. Only the
metrics that exist inside a browser cost an agent call.

### Added

- **`/testwright:run --perf`.** It generates the perf cases, times them over
  curl straight after `run-api` (and the SEO pass), then opens a browser for
  Web Vitals, and groups the failures into causes before any bug is filed.
- **`/testwright:run --load`.** A short, capped concurrent-user test. It prints
  the plan and asks before sending anything.
- **`tf.sh perf cases`, `tf.sh perf run [--only <ids>]` and
  `tf.sh perf load [--yes]`** (`scripts/lib/perf.sh`):
  - `PERF-NNN`, one per page: first byte and full response (median of three
    after a warm-up), HTML size, compression, redirect chains.
  - `PERF-API-NNN`, one per GET endpoint the suite already tests: p50/p95 over
    ten requests, response size, and a large response with no paging
    parameter.
  - `PERF-SITE-001..003`: linked assets arrive, text assets are compressed,
    static assets are cacheable.
  - `PERF-WV-NNN`, one per page, goes to the browser.
  - `PERF-LOAD-NNN`, one per load target: error rate, p95 and requests per
    second under concurrent curl workers.

  Findings go to `tests/evidence/<id>/perf.txt`, and every result row carries
  the measured milliseconds.
- **The `perf-auditor` agent.** Two modes:
  - `vitals` runs one fixed Performance API script per page and judges it
    against the budgets. The script reads LCP and its element, CLS, TBT, page
    weight, request count, and render-blocking, uncompressed, unsized and
    oversized resources.
  - `review` groups the run's failures into `tests/.cache/perf/causes.txt`,
    so one bundle failing every page is one bug.
- **The `perf-case-author` agent.** It reads one feature's code for the
  patterns behind real perf bugs — N+1 queries, unpaginated lists, unbounded
  search, missing indexes, oversized bundles, polling — and writes a
  `PERF-RISK-NNN` case for each suspect, naming the file and line.
- **The `performance` skill**, with two references:
  - `references/budgets.md`: every budget, its default and why.
  - `references/bug-patterns.md`: the code signal, runtime symptom and
    severity for each pattern.
- **`"perf"` in `tests/framework.json`**:
  - page, endpoint and Web Vitals budgets;
  - sample counts;
  - `expect_compression`;
  - a `load` block with targets, `allow_hosts`, and hard caps on users and
    seconds.
- **The demo app** now serves requests on threads and has four slow spots:
  - `/slow`;
  - a `/heavy` page that fails LCP, CLS and TBT;
  - an unpaginated N+1 `/api/catalog`;
  - `/api/flaky-load`, which fails under concurrency.

### Changed

- `tf.sh cost` has two new buckets: a free `perf` one, and a `vitals` one
  priced per browser call. The summary counts engine perf rows as free and
  points UNJUDGED vitals cases at `perf-auditor`.
- `run-api`, page modelling, compiling and the `test-runner` queue leave
  `tags=perf` cases out: `tf.sh perf` owns their verdicts.
- Triage re-measures a perf failure once before calling it an app bug, and
  never by raising a budget. The bug reporter files perf bugs once per cause,
  with the number against its budget.
- The **signals** skill hands performance to the new skill. The `qa` skill,
  the prompt hook and the QA checklist know about `--perf` and `--load`.

### Not in this release

- CPU or memory profiling, query plans, anything that needs an APM agent, and
  Lighthouse itself. Soak and capacity testing.
- Browser numbers come from an unthrottled browser, so a pass is a floor, not
  a promise about a phone on a slow network.
- The `perf-auditor` and `perf-case-author` agents have not yet been run end
  to end as agents. The measuring script was run in a real browser.

## [2.2.0] - 2026-09-26

A **minor** release: a new flag, a new engine subcommand and a new agent.
Existing suites keep working untouched, and nothing needs migrating.

Nothing checked whether the app could be found. A page could ship with no
title, a `noindex` left over from staging or a robots.txt that blocks every
crawler, and every run stayed green. Almost all of SEO is in the HTML the
server sends, so it is a curl request, not a browser session — the engine does
it for no tokens, and an agent handles only what needs rendering or judgement.

### Added

- **`/testwright:run --seo`.** It generates the SEO cases, runs them over curl
  straight after `run-api`, and only then opens a browser, for the pages that
  need one.
- **`tf.sh seo cases` and `tf.sh seo run`** (`scripts/lib/seo.sh`). One
  `SEO-NNN` case per public page checks the status and redirects, title and
  description length, one h1, an absolute canonical that resolves, `lang`,
  viewport, Open Graph tags, `noindex` (by meta tag or `X-Robots-Tag`),
  hreflang and image alt text. Four site cases check robots.txt, the sitemap
  (every URL live and indexable, no public page missing), soft 404s, and
  duplicate titles and descriptions. Findings go to
  `tests/evidence/<id>/seo.txt`. A canonical or sitemap URL on the production
  host is checked by its path on `base_url`, so the production guard holds.
- **The `seo-auditor` agent.** `render` judges a page that is an empty shell
  until JavaScript runs, which the engine leaves UNJUDGED `needs-render`.
  `review` flags placeholder titles, titles about the wrong thing, and JSON-LD
  that is invalid or missing what Google needs to show it.
- **`"seo"` in `tests/framework.json`**: `noindex_allow` for pages hidden on
  purpose, and `max_sitemap_urls` (default 200).
- **The demo app** has a correct home page, a flawed `/about`, a
  client-rendered `/app`, a robots.txt and a sitemap to try it on.

### Changed

- `tf.sh cost` counts `tags=seo` cases in their own free bucket, and the
  summary counts them as free. Page modelling, compiling and the `test-runner`
  queue leave them out.
- The summary's "could not be judged" and "skipped" notes name the real
  reason instead of always assuming an API or destructive case.
- The `qa` skill, the prompt hook and the **signals** skill know about SEO;
  the QA checklist notes it sits outside its 42 categories.

### Not in this release

- Rankings, keywords, backlinks, page speed, or anything that needs a
  third-party SEO service.
- The `seo-auditor` agent has not yet been run end to end.

## [2.1.1] - 2026-09-22

A **patch** release: no change to the plugin itself.

### Changed

- **The marketplace moved.** The catalog left this repo for
  [VikramSBizzFly/bizzfly-marketplace](https://github.com/VikramSBizzFly/bizzfly-marketplace)
  and is now called `BizzFly`. It lists testwright and
  [bizzfly-rules](https://github.com/VikramSBizzFly/bizzfly-rules). Install with
  `/plugin install testwright@BizzFly`. If you added the old `bizzfly`
  marketplace, run `/plugin marketplace remove bizzfly` and add the new one. See
  **Upgrading from an older marketplace** in the README.
- README and TRY-IT: new install steps, settings for enabling it across a team,
  and how testwright works alongside bizzfly-rules.

## [2.1.0] - 2026-09-16

A **minor** release: new knowledge, no new surface you have to type. Existing
suites keep working untouched, and nothing needs migrating.

Until now, everything the framework knew about a form field came from two
places — a grep for validation decorators in the source, and whatever
`required` or `minlength` the DOM happened to admit to. It could see that a
field was constrained; it had no idea what the field *was*. So an email field
and a coupon code got the same four boundary cases, and nothing ever asked
whether the server enforced the rule the browser did.

### Added

- **A field library** (`skills/authoring/references/field-library.md`). Match a
  discovered field to a kind — person name, money, OTP, file upload, date
  range — and get the cases that kind actually needs, including the ones the
  DOM never advertises: an email that must reject a duplicate, an OTP that must
  die after one use, a price that must refuse three decimals.
- **Rule families and what a rejection should look like**
  (`references/validation-rules.md`), plus the mandatory checks per input type.
  Its first rule is that **Expected Result** describes the rule rather than
  quoting the app's wording — asserting someone else's error text is how a
  working app gets a red run.
- **A 336-checkpoint QA checklist in 42 categories**
  (`references/qa-checklist.md`), used as a prompt when authoring and as the
  denominator when reporting coverage. It marks which categories this tool
  genuinely cannot cover — browser and device compatibility, native mobile,
  install and upgrade, backup and failover, UAT, post-deployment — so coverage
  stops counting them as gaps.
- **A fifth security probe: client-server parity**
  (`skills/security/references/client-server-parity.md`). The other four ask
  what someone can reach; this asks whether a rule the browser enforces exists
  on the server at all. `maxlength` is one devtools edit away. Stays inside the
  same boundary as the rest of the security pass — a value the browser would
  have refused, never an attack payload.
- **Dispositions, and severity split from priority**
  (`skills/triage/references/classification.md`). The four verdicts explain why
  a case failed; these cover the finding with no verdict yet. A proposed bound
  the app never agreed to is a **Decision needed**, not a `Fail` — the library
  is a default to propose, never a truth to enforce.
- **Audit mode** (`skills/reporting/references/audit-workflow.md`) for a
  baseline pass over an app nobody has tested, where coverage and its limits
  are the deliverable. testwright still only inspects, runs and reports: your
  source stays read-only, and the fix belongs to whoever owns the code.

### Fixed

- Mangled markdown in the authoring skill's page-vs-api paragraph.

### Not in this release

The library is prose the model reads, not data the engine queries. A
`tf.sh fields <kind>` lookup would make per-field expansion deterministic and
free, the way `tf.sh rbac` already does for permissions. That is the natural
next step and a larger piece of work.

## [2.0.0] - 2026-09-16

A **major** release: the plugin, its commands and its skills are renamed.
Nothing about how the plugin works changed, but every command you type and
every skill you address by name is spelled differently, so under README's
**Versioning** this is MAJOR.

`test-framework` was a category, not a name — it described a shelf rather than
the thing on it. It was also the marketplace's name, so
`test-framework@test-framework` stuttered — and collided with any other local
marketplace someone had given the same obvious name. `testwright` echoes
Playwright, which it drives, and says what it does: it writes the tests.

### Renamed

- **The plugin is `testwright`**, published from the **`bizzfly`** marketplace.
  The pairing reads as `testwright@bizzfly`: who made it, and what it is.
- **The GitHub repository is `VikramSBizzFly/testwright`** (was
  `VikramSBizzFly/test-framework-plugin`). GitHub redirects the old URL, so an
  existing clone or marketplace entry keeps resolving — but the redirect is a
  courtesy, not a promise, and the new name is the one to write down.

### Changed

- **The three commands are namespaced**: `/testwright:setup`,
  `/testwright:run` and `/testwright:report` (were `/test-setup`, `/test-run`
  and `/test-report`). The files behind them are `commands/setup.md`,
  `commands/run.md` and `commands/report.md`; Claude Code supplies the
  `testwright:` prefix from the plugin name. Every flag is unchanged.
- **The thirteen `test-*` skills dropped the prefix**: `discovery`,
  `authoring`, `codegen`, `compilation`, `execution`, `triage`, `reporting`,
  `signals`, `stack-detection`, `flows`, `auth`, `security`, `ci`. Addressed in
  full they are `testwright:discovery` and so on, so the plugin namespace was
  already saying "test" twice. The `qa` entry-point skill keeps its name — it is
  what plain-language requests land on, and it was never prefixed.
- **Agent names are unchanged.** `stack-detector`, `login-broker`,
  `route-crawler`, `case-author` and the rest are addressed the same way they
  always were.

### Fixed

- **The language templates told you to run a command that never existed.** When
  a role had no saved session, `templates/dotnet/PlaywrightBase.cs`,
  `templates/java/PlaywrightBase.java` and `templates/python/conftest.py` all
  skipped the test with `run /test-auth <role>`. There has never been a
  `/test-auth` command — sessions come from the engine — so all three now say
  `run: tf.sh login <role>`. The js template has no such guard and needed no
  change.

### Migration

- **Remove the old marketplace first**, or the two entries will sit side by
  side:

  ```text
  /plugin marketplace remove test-framework
  /plugin marketplace add VikramSBizzFly/testwright
  /plugin install testwright@bizzfly
  ```

- **Nothing in your project changes.** `tests/` is untouched: the workbook, the
  suites, the credentials, the sessions, the results and the bug report all
  carry over exactly as they are. There is no schema change and no converter to
  run — only the names you type.

## [1.0.0] - 2026-09-15

A **major** release: the visible test case columns change. Under the rules in
README's **Versioning**, a schema change is MAJOR even though existing suites
migrate on their own and nothing needs to be done by hand.

### Changed

- **Test cases use the QA team's ten columns**: Test Case ID, Module, Test
  Scenario, Test Description, Preconditions, Test Case Steps, Test Data,
  Expected Result, Actual Result, Status. The old `area`, `who`, `what to do`,
  `what should happen`, `priority` and `notes` columns are gone from the sheet.
- **Status uses QA words**: `Not Run`, `Pass`, `Fail`, `Blocked`, `Flaky`,
  `Skipped`. Any older spelling (`new`, `passing`, `skipped`, ...) written by an
  older prompt is converted on the way in.
- **Actual Result is written by the runner.** `run-api` records `HTTP 401`, the
  browser runner one sentence of what it saw.
- **An ERROR or UNJUDGED case becomes `Blocked`.** In 0.4 it left `status`
  unchanged; that let a case that could not be judged keep reading `Pass` from
  an earlier run. `Blocked` keeps it visibly out of both Pass and Fail.
- `who` moved to a hidden state `role` column. It is still set from
  Preconditions in plain words ("Logged in as admin") when authoring omits it.
- `priority` is gone. A bare `/test-run` falls back to cases tagged `smoke`;
  migration tags every former `high` case `smoke`.
- `notes` became Test Description. Test Description and Actual Result join
  Status as columns a re-merge never overwrites.
- `stats` reports status, type and role. `prune` dedupes on Preconditions,
  Steps and Expected Result.

### Added

- **`tests/bug-report.xlsx`** — a Bugs sheet in the team's columns: Bug No,
  Module, Bug Description, Steps to Reproduce, Expected Result, Actual Result,
  Test data, Status(QA), QA Comments, Severity, Priority, Reporter, Environment,
  Access Link, Bug Link, found date, Dev Comment.
- **A bug is recorded automatically when triage calls a failure an app bug** —
  never for a stale test, an environment failure or a flake.
- **`tf.sh bug from <case>`** fills everything that can be looked up (number,
  module, steps, expected and actual, reporter from git, environment, access
  link, date), so the agent supplies only a description, severity, priority and
  reasoning. A second failure updates the bug instead of duplicating it; a
  Closed or Fixed bug that fails again is Reopened; a bug marked Not a Bug is
  left alone. `tf.sh bug set` and `tf.sh bug list` round it out.
- A value containing a password or token from `credentials.json` is refused by
  `tf.sh bug`.
- On `xlsx --import` a person owns Status(QA), QA Comments, Severity, Priority,
  Bug Link and Dev Comment; the rest is regenerated from the case. A row typed
  into the sheet with no Bug No becomes a new bug.
- The run panel ends with the open-bug count and names any open bug whose case
  now passes — the retest to do next. It never changes the exit status, and
  stays out of `--quiet` and `--json`.
- `bugs.csv` has the case store's guarantees: validated writes, backups, the
  integrity gate, `check`, `restore`, and the PreToolUse write guard.

### Migration

- **Automatic.** Any `tf.sh` call converts a 0.4 suite, and a 0.1-0.3 suite
  chains through both converters in one call. Every id, status and note is
  kept; the files replaced are left as `.old`, and for the oldest suites that
  is still the original file rather than the 0.4 midpoint.

### Fixed

- `setmany` now resolves column aliases the way `set` always did.
- `_tf_commit` validates a temp file against the store it is replacing, not
  against a guess from the temp file's own name.

## [0.4.0] - 2026-09-15

### Added

- **`run-api` sends real requests.** An `api` case now carries `method`, `body`
  (inline or `@file`), `headers`, `expect_code` and `repeat`, so POST-only
  endpoints, webhook signatures (`{{hmac-sha256:NAME}}`), brute-force lockouts
  and sign-out can be tested. Secrets, cookies and environment values are
  placeholders resolved at send time. `rbac` API rows now say `method=GET` and
  `expect_code=refused`.
- **UNJUDGED verdict.** A case `run-api` cannot judge — a non-GET case with no
  `expect_code`, a `405` on a case with no `method`, a missing secret — is listed
  apart with its reason instead of counted as a failure, and leaves `status`
  alone. `summary --json` reports `unjudged`.
- **`tf.sh check` and `tf.sh restore`.** `check` says whether the store parses,
  with line numbers. `restore` puts back the newest backup that does, or
  rebuilds from the workbook, keeping the damaged file aside.
- **Store write guard.** A `PreToolUse` hook blocks Write/Edit and shell
  redirects, `tee`, `sed -i`, `mv`/`cp` and Python opens that would rewrite
  `testcases.csv` or `.cache/state.csv` directly.
- `merge` accepts **tab-separated** input and `--check` for a dry run. The
  authoring agents now write TSV.
- `example/demo-app.py` has POST-only JSON, sign-out, signed-webhook and 2FA
  lockout endpoints to try `run-api` on.

### Changed

- **`preflight` proves sessions instead of checking files exist.** It drops
  expired cookies, sends one real request per role to `login.session_probe` (or
  `roles.<role>.probe`, then `login.success_indicator`), compares it with a
  logged-out request, logs a dead role in again once, and **exits 3** if any role
  is still dead or the probe cannot tell. `--warn-only` keeps the old behaviour.
- **Every store write is validated.** Field counts, header and unclosed quotes
  are checked before a file replaces `testcases.csv` or `state.csv`; a write
  that would drop rows is refused (except `prune --apply`); backups are kept in
  `tests/.cache/backups/`. A damaged store stops every command with exit 3.
- `merge` rejects a whole file on any malformed row, with its line number, and
  builds both store files aside before replacing either.
- `run-api`: an ERROR no longer marks a case `failing`; a sign-out or
  `ends-session` case runs on a throwaway login; each request uses a copy of
  the session.
- `tf.sh` is split into modules under `scripts/lib/`. Same commands, same
  output.

### Fixed

- `merge` put text containing a comma into the wrong columns (hand-written CSV
  with unquoted commas was accepted), and a short row inherited values from the
  row before it.
- `run-api` sent a case written for `normal user` logged out: the display label
  was used as the role key. Empty columns also shifted the fields after them.
- `xlsx --import` split a record on a line break typed into a cell, and dropped
  cases that were missing from the sheet despite saying it kept them.

## [0.3.0] - 2026-09-12

### Added

- **`tests/testcases.xlsx` is the store.** Flows, test cases and their statuses
  live in one workbook with three sheets, frozen headers, filters, dropdowns and
  colour-coded status. `scripts/tf-xlsx.py` writes it with the Python standard
  library alone — no openpyxl, nothing installed into your project.
- **The plugin updates it after every run.** `tf.sh xlsx --status` writes each
  case's verdict, timestamp and evidence path back, and rolls every flow up from
  the cases covering it. A verdict that did not change rewrites nothing.
- **You can edit the workbook.** `tf.sh xlsx --import` reads hand edits back
  before a run; a row with a blank id becomes a new case. Hand edits win, and a
  row deleted from the sheet is reported, never deleted from the suite.
- **`flow-mapper` agent + `test-flows` skill** — reads a feature area's code in
  depth and records what the software actually does end to end: the journey, the
  code path down to the data layer, what it writes, and how it can fail. Every
  branch must cite `path:line`. A flow nothing tests shows as **not covered**.
- **`responsive-auditor` agent** and `/test-run --responsive` — every page at
  390, 768 and 1280, failing only on horizontal overflow, clipped or overlapping
  text, controls pushed off-screen, a nav that never collapses, and tap targets
  under 24px. Reflow is not a failure.
- `case-author` now covers a whole page: every interactive element gets a case,
  every flow gets an end-to-end case plus one per real failure branch, and every
  page gets a responsive case.
- The trigger hook and the `qa` skill now cover everything the plugin does —
  flows, journeys, responsive, accessibility, the workbook — not just testing.
- **Migration happens by itself.** Any `tf.sh` call on an out-of-date suite
  converts it — old 20-column schema, old top-level CSV layout, or both — before
  running. `TF_NO_AUTO_MIGRATE=1` opts out.

### Changed

- The engine's CSV moved to `tests/.cache/testcases.csv`; a suite created before
  the workbook keeps working where it is until `tf.sh migrate` adopts it.
  **Upgrading is automatic**: the first `tf.sh` call on an out-of-date suite
  migrates both the schema and the layout, keeps every id, status and note, and
  leaves a `.old` backup. `tf.sh migrate` still exists if you want to force it;
  `TF_NO_AUTO_MIGRATE=1` holds a suite exactly where it is.
- Visual baselines are per width: `tests/baselines/<id>@<width>.png`.
- `viewport` — a column declared in the state schema since the beginning and
  never used — now carries the width a responsive case failed at.

### Fixed

- `need_state` creates `tests/.cache/` before writing into it. A suite that had
  never had that directory made failed with an awk error instead.
- `tf_python` verifies the interpreter actually runs. On Windows `python3` is
  usually an App Execution Alias that resolves on PATH, prints an advert for the
  Microsoft Store and exits 49 — being on PATH is not evidence of being Python.

## [0.2.0] - 2026-09-12

### Added

- 13 agents, so each stage runs in its own context instead of the main
  conversation: `stack-detector`, `login-broker`, `route-crawler`,
  `case-author`, `api-case-author`, `test-compiler`, `a11y-auditor`,
  `visual-reviewer`, `security-prober`, `flake-analyst`, `bug-reporter`,
  `coverage-analyst`, `ci-wirer`.
- `tf.sh storage-state <role>` — converts the curl cookie jar into Playwright
  storage state at `tests/.auth/<role>.json`.
- `tf.sh version`.
- Flags: `/test-run --crawl --a11y --security`, `/test-setup --ci`,
  `/test-report --flakes`.
- **It activates on its own.** A new `qa` skill routes a plain-language request
  ("find bugs in my app", "can a normal user see the payroll page?") to the
  right command, runs the free checks immediately, and asks before a browser
  run, anything destructive, or a non-local target. A `UserPromptSubmit` hook
  (`hooks/hooks.json` + `scripts/qa-hint.sh`) adds one line of context when a
  prompt mentions testing, and is silent otherwise.
- Three skills for the agents that had none: **test-auth** (sessions, the two
  auth artifacts, credential handling), **test-security** (the rendered-content
  rule, the four authorization probes, scope limits) and **test-ci** (exit codes
  as the job verdict, flags, what runs per tier).
- References: `test-authoring/references/api-contracts.md`,
  `test-reporting/references/bug-reports.md`, and a real crawl procedure in
  `test-discovery/references/live-crawl-and-delegation.md`.

### Fixed

- **A logged-out browser run could report green.** `tf.sh login` wrote only
  `tests/.auth/<role>.cookies`, which just curl reads, while every browser agent
  reads `tests/.auth/<role>.json` — a file nothing produced. A role with a
  session for the API pass and none for the browser pass is refused everything,
  and every permission case "passes". `login-broker` now leaves both.
- `page-modeler` and `spec-writer` were never invoked by any command, so page
  models were never built and passing cases were never promoted to native specs.
- Stale vocabulary in agents and skills: `--type ui`, `--status passed`,
  `ui`/`rbac`/`auth` case types, and `type=a11y|perf|visual` (now `tags=`).
- `status=flaky` is set by triage but was missing from the documented schema.
- **Exit code `3` was documented but never produced.** `tf.sh` only returned
  0/1/2, so CI could not tell "the app never started" from "tests failed". The
  production guard and `tf.sh preflight` now exit `3`.
- `tf.sh preflight` only checked the curl cookie jar, so a role missing its
  browser storage state was reported as ready; it now names that gap.

### Changed

- `/test-run` delegates discovery, authoring, compilation, execution and
  reporting to agents rather than doing them inline.
- New `/test-run` step 3.5 (model each route once, then compile recipes on
  paper) and step 4.5 (promote passing cases to native specs at Tier 1/2).

## [0.1.0] - 2026-09-10

### Added

- Initial release: `/test-setup`, `/test-run` and `/test-report`; nine skills;
  five agents (`test-explorer`, `page-modeler`, `test-runner`, `test-triager`,
  `spec-writer`); `scripts/tf.sh`, the deterministic POSIX engine; per-stack
  templates for js/python/java/dotnet; and `example/demo-app.py`, a fixture app
  with two deliberate bugs.

---

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json` — the only place it lives.
2. Add the entry above, newest first, with today's date.
3. `git commit -m "Release vX.Y.Z"`
4. `git tag vX.Y.Z && git push --follow-tags`
