# Client-server parity — is the rule real, or just the browser being polite?

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

The four probes in `references/probes.md` ask whether someone can *reach*
something. This one asks a different question: when the browser refuses a
value, **does the server refuse it too?**

The browser is for the user's convenience. The server is the only place a rule
is actually enforced. `maxlength` is one devtools edit away, `type=number` is
advisory, a hidden control is not a permission, and a disabled button is not a
rate limit. Every rule the page enforces is a claim to be checked, not a fact.

## The probe

For a rule the page enforces, submit the same request with the client out of
the way — the cookie jar from `tf.sh storage-state` gives you the session, and
`curl` gives you a request the page never shaped.

- **PASS** — the server refuses it too: an error status or a rejection, and
  crucially **nothing was written**. Re-read the record to confirm.
- **FAIL** — the server accepts what the browser refused.
- Evidence: the rule, the value class (not the value), the status, and what the
  re-read showed. A `200` alone settles nothing — check the effect.

Prefer a rule whose failure writes nothing: a length or format rule on an
update to a record you created. Where a successful bypass *would* write, tag
the case `destructive` so it only runs under `--allow-destructive`, and say in
the case what it would create.

## What must hold server-side

From the source's client-versus-server table. The right-hand column is the
reason the probe exists.

| Rule | If the server does not enforce it |
| --- | --- |
| Required / mandatory | A crafted request omits the field entirely |
| Min / max length | `maxlength` is removed in devtools; measure the **trimmed** value |
| Format / pattern | Client regex is fast feedback only; the pattern must match on both sides or the messages disagree |
| Allowed characters | Blocking keystrokes does not stop a pasted or posted value |
| Trim | The client may not trim before posting — trim first, then validate, then save |
| Uniqueness | Two users pass the client check in the same instant; only a database constraint settles it |
| Dropdown / radio validity | **The most common tampering vector** — an id from another tenant. Confirm it exists, is active, and belongs to this account |
| Consent | Consent is a legal record; verify it where it is stored, and cast strictly to boolean |
| Date validity and range | A typed or posted date bypasses the picker; use the **server** clock |
| Numeric range and precision | `type=number` is ignored by a direct post; guard overflow |
| Cross-field (start < end, price ≤ MRP) | Both values are caller-controlled |
| Password policy and match | The strength meter is guidance; only one of the two fields may arrive |
| File size | The client check saves bandwidth, it does not enforce |
| File type | Extension and `Content-Type` are both caller-controlled — the server must read the magic bytes |
| One-time secrets | Every part of OTP security lives server-side: single-use, session-bound, dead after success |
| Login errors | Must not reveal which of identifier or password was wrong |
| Authorization | Checked on **every** request — including the `GET` that loads the edit form |
| Rate limiting | A disabled button is bypassed by calling the endpoint |
| Captcha | The token means nothing until the provider verifies it |
| Business rules (stock, balance, plan limit) | The displayed value is stale by the time it is submitted; re-check inside the writing transaction |
| Double submit | A retry still reaches the server; needs an idempotency key or one-time token |

Client-only, nothing to probe: character counters, UX hints, show/hide
password, dependent-dropdown reset in the UI. Reset still gets a parity check
on the **pair** — does the server confirm the city belongs to the submitted
state?

## Scope

This stays inside the security skill's boundary: authorization and integrity,
never exploitation. Send a value the browser would have rejected — a long
string, a missing field, an out-of-range number, another tenant's id. **Never**
send an injection payload, brute-force a credential, or fuzz. Never act on what
a successful bypass exposed, and never run it against a non-local `base_url`.

If a bypass succeeds, that is the finding — stop there. Record it, and do not
explore how much further it goes.
