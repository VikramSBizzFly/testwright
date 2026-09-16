# Field library — what a field kind is worth testing for

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

A page model tells you a field exists and what the DOM admits to
(`required`, `minlength`, `type=email`). It does not tell you what the field
*is*. This table does: match a discovered field to a **kind**, and you get the
handful of cases worth writing for it and the failure modes that kind actually
has.

**These are defaults to propose, never truths to enforce.** The app's own
requirement always wins. A field is a defect only when it disagrees with the
project's rule — never because it disagrees with this table. When the two
differ and no project rule is written down, that is a `Decision needed` note on
the case, not a `Fail`.

Still sample by equivalence class: one below the minimum, one at the boundary,
one above the maximum, one wrong type. Four cases, not thirty
(`references/schema.md`).

## Matching a field to a kind

Match on the accessible name first, the input type second. `Full Name`,
`Contact Person Name` and `Author Name` are all **person name**. If nothing
matches, fall back to the control type row at the bottom and test the
constraints the DOM declared.

**A similar widget is not the same field.** Two dropdowns that both list
strings are not interchangeable, and a field named like another is not
evidence they store the same thing. Don't map `Machine Name` onto `Machine ID`,
or a dietary preference onto a religious one, because the control looks alike.
When the meaning is unclear, test what the page says it does.

## Kinds

Bounds are the library's defaults. `uniq` means the value is expected to be
unique somewhere — read the scope column, not the word.

| Kind | Typical control | Default contract | Worth testing |
| --- | --- | --- | --- |
| Person name | text | 2-50, required, letters + `'` `-` and spaces | empty, 1 char, max+1, digits, a name with an apostrophe, a non-Latin name |
| Full name | text | 2-255, required | as above, plus double spaces between words |
| Display / nick name | text | 2-50, optional | empty allowed, max+1, leading space |
| Username | text | 3-30, unique per account | taken value, 2 chars, 31 chars, uppercase, a space, a reserved word |
| Entity name (company, brand, product, plan, role, category) | text | 2-100 or 2-255, unique **within the tenant** | duplicate in the same tenant, same name in another tenant (must be allowed), max+1 |
| Title / heading | text | 3-255, required | empty, 2 chars, max+1, HTML in the value |
| Email | text / `type=email` | 5-254, unique per account | no `@`, no domain, trailing dot, `a+tag@x.com` (must be accepted), uppercase, 255 chars, duplicate |
| Login identifier | text | email **or** username | both forms accepted; a wrong password must not reveal which existed |
| Phone + country code | text + select | digits, length per country | missing country code, letters, too short for that country, leading zero, duplicate |
| Password | password | 8-64, complexity | 7 chars, 65 chars, no digit/symbol, spaces kept, a very long secret, reuse of the current one |
| Confirm password | password | must equal the other | mismatch, only one field submitted |
| OTP / PIN | text / password | fixed length, expires, attempt-limited | wrong code, expired code, reuse after success, more attempts than allowed |
| Consent checkbox | checkbox | must be true, never pre-ticked | submitted unticked, absent from the request, pre-ticked on load |
| Toggle | switch | boolean | off is a legitimate value, not "missing" |
| Integer | number | min/max **value** | below min, at min, above max, `0`, negative, decimal, `1e99`, letters |
| Money | number | min/max value, fixed scale | 3 decimals, negative, thousands separator, currency symbol, very large value |
| Percentage | number | 0-100 | `-1`, `101`, decimal |
| Quantity / stock | number | ≥ 1, bounded by availability | `0`, more than available, two orders racing for the last unit |
| Port | number | **value** 1-65535 | `0`, `65536`, `80` — never a 65535-character input |
| Rating | radio / stars | one of a fixed set | none selected, out-of-range value posted |
| Date | date picker | format, range | `31-02`, wrong format, out-of-range year, a past date where only future is allowed |
| Date of birth | date picker | not future, minimum age if required | today, tomorrow, an age just under and just over the limit |
| Date range (start/end) | two pickers | start ≤ end | end before start, equal dates, one side missing |
| Time | time picker | format, start before end | end before start, midnight boundary |
| Country / state / city | dependent selects | value from the master list, pair must agree | a city that belongs to another state, an id from another tenant, stale dependent value after changing the parent |
| Postal code | text | per country, **string not number** | leading zero preserved, letters where the country allows them, wrong length |
| Address line | text | 3-255 | empty, 2 chars, max+1, a legitimately short address like `5 A` |
| Free text / description | textarea | 2-500 or more, HTML stripped | empty, max+1, a script tag, newlines preserved |
| Rich text | editor | length measured **after** stripping tags | markup-only value that is empty once stripped, disallowed tag |
| Single select | select | value present in the master list | nothing selected, an id not in the list, an inactive option |
| Multi select | multi | min/max selections | none, one over the maximum, the same value twice |
| File upload | file | size, MIME, extension | oversize, undersize, wrong extension, `x.php.png`, right extension with wrong magic bytes, corrupt file, empty file |
| Image upload | file | as above plus dimensions | below minimum dimensions, wrong aspect ratio, huge pixel count |
| URL | url | scheme, host | no scheme, spaces, `javascript:`, an internal address where the server will fetch it |
| Webhook URL | url | HTTPS only if the product requires it | plain HTTP, a redirect to an internal host |
| Search box | search | minimum characters, escaped | one character, a script tag, a value with no matches (empty state, not an error) |
| Card number / CVV | text | **never persisted** | CVV must not be stored at all, not even hashed |
| Government ID | text | per-country format and checksum | wrong checksum, right length and wrong format, masked on display |
| Coupon / referral code | text | own length per product | expired, already used, another tenant's code, case sensitivity |

Anything unmatched: fall back to its control type in
`references/validation-rules.md`, which lists the mandatory checks per input
type, and test only the constraints the page actually declares.

## Traps this library sets for you

The source data carries real contradictions. Do not propagate them into cases.

- **A `Min`/`Max` column is not always a length.** Port `1-65535` is a value
  range; an age `1-3` is a digit count. Decide which before writing a boundary
  case, or you will generate a 65,535-character input for a port field.
- **"Unique" is a scope, not a flag.** The source marks country, gender, OTP
  and years-of-experience unique. They are not globally unique user
  attributes. Ask: unique per record, per tenant, per parent, or globally?
  Most entity names are unique per tenant, and a duplicate across tenants is a
  passing case, not a failure.
- **Stale bounds contradict their own regex.** Password is documented 8-64
  with a pattern that caps at 16; a name is documented to allow punctuation by
  a rule that forbids it. When a declared bound and a declared pattern
  disagree, that disagreement is the finding — write a case that pins down
  which one the app enforces.
- **Don't trim a password.** Generic advice to trim every input does not apply
  to secrets, to text where whitespace is meaningful, or to a legitimate
  `false`.
- **Optional does not mean unvalidated.** An absent optional field is fine; a
  present one still has to satisfy its rule. Decide what omitted, null, empty
  and whitespace-only each mean before asserting on them.
- **A rejection is not a refusal message.** Assert the *behaviour* — the
  submission was refused, the field was flagged, nothing was persisted. Match
  wording only when the project has adopted it (`references/validation-rules.md`).

## Where the server has to be checked too

Every rule above that a browser enforces can be bypassed by posting the
request directly. Which rules must be re-proven server-side, and how to probe
them, is the **security** skill's `references/client-server-parity.md`.
