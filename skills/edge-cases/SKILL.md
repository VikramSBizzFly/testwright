---
name: edge-cases
description: Test where web apps break at the edges - exports that are empty, wrong or carry formula injection (export-verifier, tf.sh export-check), file uploads over the limit, of the wrong type or with dangerous names (upload-prober), writes that race - lost updates, double submits, oversells (concurrency-prober), mechanical UX rules like double-submit protection and confirming destructive actions (ux-heuristics-reviewer), and aimed, time-boxed exploratory testing (exploratory-scout). Use for /testwright:run --edge, --ux or --explore, or when a user asks to test exports, uploads, race conditions, double clicks, or to "poke around and try to break it".
---

# Edge cases

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

The happy path is tested. These are the places it stops being happy: the
file, the second click, the second user, the input nobody planned for.
Everything here that writes is `tags=destructive` and runs only with
`--allow-destructive`, against a local target.

## Exports (`export-verifier`, `tf.sh export-check`)

`tf.sh export-check <file> [--rows N] [--columns a,b]` opens a downloaded
file, free, and fails on:

- **an HTML page saved as the export**: a login or error page with a `.csv`
  name, the commonest broken export;
- **an empty file**, or a CSV row whose field count differs from the header;
- **invalid UTF-8**: names garbled in Excel;
- **a row count that differs from what the screen showed** (`--rows`), or a
  missing column (`--columns`);
- **formula injection**: a cell starting `=`, `+`, `-` or `@` followed by a
  letter or `(`. Excel runs it when the file is opened. The fix is to prefix
  such cells with `'`;
- **a PDF** without `%PDF` or `%%EOF` (truncated);
- **an xlsx** that is not a real zip, has no sheet, or holds a
  `HYPERLINK`/`WEBSERVICE` formula.

`export-verifier` finds the exports in the code, downloads each as the role,
takes the expected count from the list the export mirrors, and runs the
check. The downloaded files are deleted after the run, because they hold
real records.

## Uploads (`upload-prober`)

The server must hold every rule the browser suggests. The probe files are
generated on the spot, and all of them are benign:
- one byte over the limit;
- zero bytes;
- a text file renamed `.png`;
- a disallowed extension;
- a huge but valid image;
- filenames containing `../` and `<b>`.

**Refused** means a 4xx and a readable message, never a 500 and never a
timeout. **Accepted** means stored under a safe name: never a raw `../` in
the path, never unescaped HTML in the page. Never a script, a polyglot, a
zip bomb or anything that executes.

## Concurrency (`concurrency-prober`)

The request is sent N times at the same moment (`xargs -P`), and the result
read back:

| Bug | Code smell | Probe | Pass |
| --- | --- | --- | --- |
| Lost update | read, change in code, save; no lock, version or atomic update | 10 increments | final = start + 10 |
| Double submit | a create with no unique key or idempotency key | the same create twice | one record, or the second refused |
| Silent overwrite | an edit with no version check, where the UI promises conflict detection | two edits | both kept, or a 409 |
| Oversell | check-then-act on stock or quota | N buys of N-1 | at most N-1 succeed |

## UX heuristics (`--ux`, `ux-heuristics-reviewer`)

Six mechanical rules, each a known cause of user error:
- a submit shows feedback;
- the submit button disables while saving;
- a destructive action confirms (or offers undo);
- an error sits at its field;
- focus moves into a dialog and back;
- the page title says where you are.

Taste, colour and wording are out.

## Exploratory (`--explore`, `exploratory-scout`)

Aimed: the three riskiest routes, by recent change, thin coverage and
failure history. Bounded: 25 browser actions per route. It tries what
scripts never do:
- back mid-flow and deep links;
- reload after submit, and two tabs;
- empty, huge, emoji and right-to-left input;
- `-1` and `1e309` in number fields.

It watches the console and the network while it does. **Every oddity
becomes a proposed case (`tags=explored`), never a verdict or a bug.** The
case runs, and triage decides.
