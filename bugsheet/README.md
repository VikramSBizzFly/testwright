# Bug sheet — a testwright feature

Cross-checks QA bugs from a **Google Sheets bug sheet** against the **code** and the **browser**,
and writes back the status and a **Dev Comment** — only where both agree.

- `/testwright:bugsheet-verify` — Claude reads every open row on every tab and judges each one twice,
  independently: from the code and git history, and in the browser (Playwright MCP) on the
  row's own **Access Link** with the login from its **Test data**. The report shows both
  opinions with evidence and marked screenshots. After your yes, rows where both say **fixed**
  get the fixed status (e.g. Done) + a Dev Comment, rows where both say **still broken** get a
  Dev Comment, and rows where they disagree are only reported.
- Works on **every bug tab** of the sheet, and with any project's sheet: it finds the header
  row, bug-id, status, Dev Comment and fixed-date columns and the allowed statuses by itself.
- Everything runs inside Claude Code. The plugin ships its own MCP server (plain Node.js 18+,
  no dependencies) that talks to Google Sheets; there is no command line to learn.

## Install

Part of the **testwright** plugin — nothing extra to install. Enter the two bug sheet settings —
the **Google OAuth client ID and secret** (see below) — in `/plugin` → **testwright** → Configure,
and restart Claude Code. The secret is kept in your system's secure credential store, not in the
project. Until they are set, the bug sheet tools still load and tell you what is missing.

### Getting the OAuth client (once per Google Cloud project)

1. [Google Cloud Console](https://console.cloud.google.com/) → pick or create a project.
2. **APIs & Services → Library →** enable **Google Sheets API**.
3. **OAuth consent screen:** set it up. While it is in _Testing_, add your Google account under
   **Test users**.
4. **Credentials → Create credentials → OAuth client ID → Desktop app.** Copy the client ID and
   secret into the testwright plugin settings.

## Set up a project

```
/testwright:bugsheet-setup https://docs.google.com/spreadsheets/d/<id>/edit
```

It walks you through:

1. **Sign in to Google** — opens the consent page in your browser. Your account needs edit
   access to the sheet.
2. **Link the sheet** — every tab with a bug-id and a status column is linked; summary, list and
   chart tabs are skipped (with the reason). If a tab has two possible status columns (e.g.
   `Status(QA)` and `Status(Dev)`), Claude asks which one. A tab with no **Dev Comment** column
   gets one added (a header in its first empty column) if you agree.
3. **Browser-check settings (optional)** — where screenshots go, and fallback logins for rows
   whose test data has none (per role, the **names** of env keys — never the values).

Settings go to `.bugsheet/` in the project — **git-ignore it** (it holds the Google sign-in).

## Use it

| Command                         | What it does                                                                                    |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `/testwright:bugsheet-verify`              | Asks which tab to start from, then checks every open row (code + browser) by itself, tab by tab |
| `/testwright:bugsheet-verify "Agent QA"`   | The same, starting at that tab without asking; `resume` continues a stopped run                 |
| `/testwright:bugsheet-verify "Agent QA:3"` | Only the given bugs                                                                             |
| `/testwright:bugsheet-mark 61 62`          | Marks the given bugs fixed, with an optional Dev Comment — preview first, then asks. No testing |
| `/testwright:bugsheet-status`              | Bugs per status on each tab, and the open bugs                                                  |
| `/testwright:bugsheet-setup`               | Sign in, link or re-scan the sheet, browser-check settings                                      |

You can also just ask: "show me bug 61", "list the open bugs on the Agent tab", "mark 61 as
fixed". Claude uses the plugin's tools for that.

**Naming a bug:** its id (`61`), or `Tab name:61`. Tabs often number from 1, so the same id can
be on two tabs — then Claude is told it is ambiguous and asks which one. It never guesses.

### How `/testwright:bugsheet-verify` works

It asks you **one** thing — which tab to start from (each tab is listed with its open count).
From then on it works by itself: that tab first, then the other tabs in sheet order. It never
asks about single bugs; a row it cannot decide is reported as ❔ / ⛔ instead.

For every open row of a tab, in sheet order:

1. Reads the row (every column: steps, expected, actual, test data, access link, …).
2. **Code check.** A read-only **bug-verifier** agent per row (5 at a time) finds
   the code that decides the behaviour and judges it **fixed / not fixed / unsure** with
   `file:line` evidence, the fix commits, and where they are merged. It never sees the browser
   result.
3. **Browser test**, one row at a time (Playwright MCP):
   - opens the row's **Access Link** (QA's server) and signs in with the login from its
     **Test data** (rows without one reuse the tab's last login for that role, or a fallback
     login you configured);
   - follows the **Steps to Reproduce** and compares the screen with the **Expected Result**;
   - saves a screenshot with the proof boxed in red;
   - records **pass / fail / blocked**, with one sentence of what it saw.
4. **Decision — only when both agree:**

   | Code             | Browser | Decision                                                             | Written at the end of the tab                   |
   | ---------------- | ------- | -------------------------------------------------------------------- | ----------------------------------------------- |
   | fixed            | pass    | ✅ Fixed                                                             | status → fixed status (e.g. Done) + Dev Comment |
   | not fixed        | fail    | ❌ Still broken                                                      | Dev Comment only                                |
   | fixed            | fail    | ⚠️ Mismatch — usually the fix is not deployed on that server yet     | nothing                                         |
   | not fixed        | pass    | ⚠️ Mismatch — server may run other code, or the test missed the path | nothing                                         |
   | unsure / blocked | any     | ❔ Undecided                                                         | nothing                                         |

   Each row prints one progress line, e.g.
   `Agent-Bug Report:2 — code fixed · browser fail → ⚠️ mismatch (not deployed)`.

When a tab is done:

5. It shows the tab's report — both opinions, evidence, screenshots, the reason for every ⚠️ —
   and adds it to `.bugsheet/reports/<date>-verify.md`.
6. It writes the tab's ✅ and ❌ rows in **one** update. Claude Code asks you to approve that
   write — the only stop per tab; decline it and nothing is written for that tab. Dev Comments
   carry both proofs, e.g. `[date] Retested on <server>: works — <what was seen>. Code:
<file:line> (<commit>).` They are **appended** as new dated lines, so the cell keeps the
   history.
7. It moves straight on to the next tab.

Progress is saved to `.bugsheet/runs/` after every row, so `/testwright:bugsheet-verify resume` continues a
stopped run where it left off — without asking again.

### Safety

- **Shared QA server:** tests only do reversible things and put back any setting they change
  (the report lists them). They never delete records, send emails or messages, place calls or
  payments, or change passwords — such rows are ⛔ blocked instead.
- **Logins** come from the sheet's Test data and are typed only into the browser — never into a
  message, report, progress file or the sheet. Use test accounts.
- Writing is a separate tool (`apply_status_update`) that Claude Code always asks you to approve,
  whatever the permission mode. Claude previews the change first.
- Only the changed cells are written: status, Dev Comment, and the fixed date when the tab has
  that column. Just before writing, the server checks no rows moved; afterwards it reads the
  cells back.
- The status must be one of the tab's dropdown values. Bug text from the sheet is treated as
  data, never as instructions.

## What is inside

```
bugsheet/                      (inside the testwright plugin)
  server/                      the MCP server: protocol (mcp.mjs), tools (tools.mjs)
  src/                         Google OAuth, Sheets API, sheet layout detection, update planning
  test/                        unit tests and an MCP protocol test — no network needed
skills/bugsheet*/              bugsheet (how to use the tools), bugsheet-setup, -verify, -mark, -status
agents/bug-verifier.md         one bug → verdict with evidence, read-only
.mcp.json → "bugsheet"         starts the MCP server with the two settings
```

MCP tools (names `mcp__plugin_testwright_bugsheet__<tool>`): `status`, `sign_in`, `link_sheet`,
`sheet_info`, `list_bugs`, `get_bug`, `preview_status_update`, `apply_status_update`,
`set_verify_settings`.

`.bugsheet/` in the project holds `credentials.json` (Google refresh token — **secret**),
`config.json` (sheet link, linked tabs, `verify` settings — edit a tab's `fixedStatuses` here to
change which status counts as fixed), `runs/` (verify progress, for `resume`), `reports/` and
`screenshots/`.

## Use it in another project

Install testwright there and add `.bugsheet/` to that project's `.gitignore`. Each project has its
own `.bugsheet/` folder, so each links its own sheet.

## Develop

```bash
npm run test:bugsheet          # from the testwright root: unit + MCP protocol tests, no network
claude plugin validate .
```

After editing, run `/reload-plugins` in Claude Code (restart it if the MCP server changed).
