---
name: bugsheet-setup
description: Set up the bug sheet plugin for this project — check the Google OAuth client, sign in to Google, link the bug sheet (every bug tab), and optionally save browser-check settings.
argument-hint: "[sheet link]"
disable-model-invocation: true
allowed-tools: mcp__plugin_testwright_bugsheet__status, mcp__plugin_testwright_bugsheet__sheet_info, mcp__plugin_testwright_bugsheet__sign_in, mcp__plugin_testwright_bugsheet__link_sheet, mcp__plugin_testwright_bugsheet__set_verify_settings
---

# Set up the bug sheet

Arguments: `$ARGUMENTS` — optionally the sheet's link. Tools are the bugsheet MCP tools
(`mcp__plugin_testwright_bugsheet__…`). Go step by step; skip steps that are already done.

## 1. Check

Call `status`.

- **`oauthClient` missing** → the user enters the client in the plugin settings, then restarts
  Claude Code. Explain how to get one (once per Google Cloud project):
  1. Google Cloud Console → enable **Google Sheets API**.
  2. **OAuth consent screen** — set it up; while in _Testing_, add their Google account under
     **Test users**.
  3. **Credentials → Create credentials → OAuth client ID → Desktop app**.
  4. Run `/plugin`, open **testwright**, and enter the Client ID and Client secret there (the
     secret is kept in the system's secure credential store).

  Stop here until they come back. Never ask for the secret in the chat.

## 2. Sign in

If `signedIn` is false: call `sign_in`. It opens Google's sign-in page and returns the URL —
show the URL in case the browser did not open. Ask the user to say "done" when Google shows
"bugsheet is signed in", then call `status` and check `signedIn` is true. If `signIn.state`
is `failed`, show the error and offer to try again.

The Google account needs **edit** access to the sheet.

## 3. Link the sheet

Use the link from `$ARGUMENTS`, or ask for it (the browser address bar of the sheet). Call
`link_sheet` with `url`.

- `saved: true` → show each linked tab (header row, id/status/title columns, statuses, fixed
  statuses, whether it has a fixed-date and a **Dev Comment** column) and the skipped tabs with
  their reasons.
- `missingDevComment` → those tabs have no Dev Comment column, so `/testwright:bugsheet-verify` cannot
  write its notes there. Ask the user whether to add one; if yes, call `link_sheet` again with
  `addDevCommentColumn: true` (it adds a "Dev Comment" header in each such tab's first empty
  column). If the column exists under another name, use `columns` instead, e.g.
  `{ "*": { "devComment": "Developer Notes" } }`.
- `needsChoice` → a tab has two possible columns for a field (e.g. `Status(QA)` and
  `Status(Dev)`). Ask the user which one (AskUserQuestion, one question per tab/field), then call
  `link_sheet` again with `columns`, e.g. `{ "Agent QA": { "status": "Status(Dev)" } }` or
  `{ "*": { … } }` for every tab.
- A tab skipped that should be linked → ask which headers are its id and status, then call
  again with `tabs` and `columns`.

## 4. Browser-check settings (optional)

`/testwright:bugsheet-verify` retests each row in the browser on the row's own **Access Link** with the
login in its **Test data**, so usually nothing is needed here. Optional settings, saved with
`set_verify_settings`:

- `screenshotDir` — where marked screenshots go (default `.bugsheet/screenshots`);
- `logins` — for rows without a login in their test data: per role, the **names** of two env
  keys, never the values, e.g. `{ admin: "ADMIN_EMAIL_KEY,ADMIN_PASSWORD_KEY" }`, read from
  `envFile` (default `.env.local`).

## 5. Finish

- Check `.gitignore` has `.bugsheet/` (it holds the Google sign-in). Add it if missing, and
  tell the user.
- Suggest `/testwright:bugsheet-status` to see the bugs, and `/testwright:bugsheet-verify` to check them.
