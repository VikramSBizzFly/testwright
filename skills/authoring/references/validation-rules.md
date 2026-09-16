# Validation rules — message families, patterns, input types

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Use this to write the **Expected Result** of a validation case, and to decide
what a rejection should look like. Companion to `references/field-library.md`,
which says what to test; this says what should happen when it fails.

## Assert the behaviour, not the wording

An app has its own voice. `Full Name cannot be less than 2 characters.` is one
plausible phrasing of a rule, not the required text. A case that asserts that
exact string will fail on a working app that says `Please enter at least 2
characters` — a false failure, which costs more than the case was worth.

So: **Expected Result describes the rule and the observable outcome.**

```
Expected Result: The form is not submitted, the Email field is flagged, and no
                 account is created.
```

Quote exact wording only when the project has adopted it — a style guide, an
i18n catalogue, or a message the team asked you to pin. Then the case is about
the wording, and say so in the scenario.

Where a message template does earn its place is **classification**: it tells
you which rule family a rejection belongs to, so triage can tell "the app
rejected it for the right reason" from "the app rejected it for the wrong one".

Parameter convention, where a project does adopt templates: `{Field}`,
`{Min}`, `{Max}`, `{Parent}`.

## Rule families

Severity is the source's: **Blocking** stops submission, **Warning** allows it
with a caution, **Info** and **Success** are neither errors nor failures.

| Family | Covers | Severity | What a passing app does |
| --- | --- | --- | --- |
| Presence | required, empty or whitespace-only, consent, a field that becomes required because of another | Blocking | Refuses, flags the specific field, and says which; a summary at the top is not enough on its own |
| Length | min, max, exact | Blocking | Measures the **trimmed** value, in characters not bytes |
| Value range | min, max, negative, decimals not allowed, precision | Blocking | Casts before comparing; survives `1e99` and overflow |
| Character class | alphabetic, alphanumeric, digits only, no spaces, no leading or trailing space, must start with a letter | Blocking | Rejects the pasted and posted value, not just the typed one |
| Format | invalid format, type mismatch, invalid URL | Blocking | Same rule on both sides, so the two never disagree |
| Identity | duplicate, value taken, reserved, must differ from another field | Blocking | Enforced at the database, not by a SELECT-then-INSERT that races |
| Reference | record not found, record in use, orphan reference | Blocking | Refuses rather than writing a dangling id |
| Date and time | format, impossible day or month, past or future not allowed, range order, minimum age | Blocking | Uses the **server** clock; rejects `31-02` |
| Selection | nothing selected, invalid option, min or max selections, duplicate in a list | Blocking | Confirms the option exists, is active, and belongs to this tenant |
| Authentication | credentials mismatch, account not found, account locked, session expired, attempt limit | Blocking | Never reveals which of identifier or password was wrong |
| One-time secrets | OTP mismatch, OTP expired, captcha failed | Blocking | Single-use, session-bound, dead after success |
| Password policy | strength, mismatch, reuse | Blocking | Never logs the plain value |
| File | too large, too small, bad extension, bad format, corrupt, password-protected, macro or archive, failed security scan | Blocking | Decides on magic bytes, not the filename or `Content-Type` |
| Markup and injection | script or HTML not allowed | Blocking | Sanitises on input **and** escapes on output; a blacklist is not the defence |
| Business rule | insufficient balance, stock exhausted, slot gone, outside working hours, plan limit | Blocking | Re-checks inside the transaction that writes |
| Transport | server error, network error, rate limit, double submit | Blocking / Warning | Fails visibly; a retry does not duplicate the effect |
| Non-error states | no records found, unsaved or no change, success | Info / Success | An empty result is an empty state, **not** an error — a case that treats it as one is wrong |

## Patterns

Where the app declares a pattern, test it; do not import one.

- **Compile and run it in the app's own runtime.** A pattern that works in one
  engine can be a syntax error in another. A bare inline `(?i)` is not portable
  and is a syntax error in JavaScript.
- **Say whether a match means accept or reject.** A pattern used as a blocklist
  and the same pattern used as an allowlist produce opposite verdicts.
- **Syntax is not validity.** A well-formed email address may not be
  deliverable, a well-formed URL may point at an internal host, a well-formed
  date may be `31-02`. Test the parsed meaning separately from the shape.
- **Test the pattern's cost.** A pattern with nested quantifiers can hang on a
  crafted input. A submit that never returns is a finding.

Values worth trying against almost any text field: an empty string, a single
space, a leading and trailing space, a very long value, a newline, an emoji, a
right-to-left name. These belong in `Test Data`, and the expected result is
either acceptance or a clean refusal — never a stack trace, and never the value
echoed back into the page unescaped.

For markup handling, use **inert** text that looks like markup — `<b>test</b>`,
or a literal `<script>` tag with no payload in it — and assert it comes back
escaped and displayed as text. That is a rendering check, and it is the whole
of what belongs in a validation case.

**Do not write attack payloads.** No `alert(1)`, no SQL fragment, no path
traversal, no fuzzing. Proving an app is *exploitable* is outside this tool's
scope and the **security** skill refuses it explicitly — including against a
local fixture, so the rule never has to be remembered differently per target.
An escaping check tells you the same thing without the payload.

## Input types and their mandatory checks

Fall back to this when a field matches no kind in `references/field-library.md`.

| Input type | Mandatory checks |
| --- | --- |
| text | required, min, max, allowed characters, trim, no script |
| textarea | required, min, max, no HTML, whitespace, counter |
| password | required, min, max, complexity, match, spaces preserved, masked |
| number | required, numeric, min and max **value**, negative, precision |
| text + dropdown | country code chosen, digits only, length per country |
| select | required, value in the master list, dependent reset |
| multi-select | at least one, maximum, no duplicates |
| radio | exactly one, no pre-selection without a business default |
| checkbox | consent ticked, group minimum, never pre-ticked |
| toggle | dependent field complete before enabling, save feedback |
| date picker | format, day/month/year range, past or future limit, range order |
| time picker | format, start before end, future time when scheduling |
| file | required, min and max size, MIME, extension, scan, corruption |
| url | scheme, host, valid TLD, no spaces |
| rich text | min and max **after** stripping tags, allowed tags, server sanitisation |
| color | valid hex |
| button | disabled while submitting, confirmation when destructive, no double submit |
| captcha | solved before submit, re-verified server-side |
| search | minimum characters, escaped input, empty state |
| static label | nothing — display only |
