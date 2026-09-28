---
name: security
description: Decide whether the app actually refused someone, and probe the authorization boundaries a role-by-route matrix cannot express. Use when generating or judging a permission case, when running the security pass, or when a run's verdict turns on whether protected content rendered.
---

# Security

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

This framework opens a real browser for one reason, and it is this one.

**A refusal and a leak both return `200`.** A page reading "Access denied" and a
page dumping every salary are indistinguishable by status code, and a guard
implemented in JavaScript does not exist for `curl` to hit at all. So the
question is never what the response code said. It is: **did the protected
content actually render?**

That is why a permission check is `type=page` and never `type=api`, however
tempting the zero-token price is. A false pass here costs more than every token
it saved.

## Two layers

**The matrix, free.** `tf.sh rbac routes.txt privileged.txt` sweeps every role
against every route and generates the `AUTH-*`, `API-*` and `PERM-<ROLE>-*`
families. Give it a real `privileged.txt` — without one it falls back to a name
heuristic and says so. This cheap pass is what makes hundreds of permission
cases correct rather than guessed.

**The probes, deliberate.** Four boundaries the matrix cannot express: IDOR,
forced browsing, session reuse after logout, and open redirect. Delegate these
to the `security-prober` agent, one call per feature. Worked examples and the
evidence each verdict needs: `references/probes.md`.

**Parity, the fifth probe.** The four above ask what someone can reach. Parity
asks whether a rule the browser enforces is enforced at all: `maxlength` is one
devtools edit away, `type=number` is advisory, a hidden control is not a
permission. Submit the value the page refused, with the client out of the way,
and check nothing was written. Which rules must hold server-side, and how to
probe each without leaving the authorization boundary:
`references/client-server-parity.md`.

## Verdict and reporting

Tag these cases `tags=security`. `tf.sh summary` pins them above everything else
and exits **`2`**, distinct from an ordinary failure. A 91% green run while a
logged-out visitor can read payroll is not a passing run, and the panel is built
to say so.

Evidence records **that** protected content rendered — never the content.
Redact on write: a leaked salary pasted into `tests/evidence/` has simply moved
the leak somewhere else.

## Security headers (`--headers`, `tags=headers`) — free, over curl

The defences a browser applies only when the server asks for them. `tf.sh
headers cases` writes the cases and `tf.sh headers run` judges them for zero
tokens:

- `HDR-NNN`, one per page:
  - a Content-Security-Policy, and one that does not allow `'unsafe-inline'`
    script without a nonce or hash;
  - `X-Frame-Options` or CSP `frame-ancestors`, against clickjacking;
  - `X-Content-Type-Options: nosniff`;
  - no Referrer-Policy that leaks full URLs;
  - HSTS of at least 180 days, when the page is served over https.
- `HDR-SITE-001` CORS: an arbitrary Origin, or `null`, is never echoed back
  with credentials. It checks the home page and up to ten GET endpoints.
- `HDR-SITE-002` no `Server` or `X-Powered-By` banner names a version, and a
  missing page shows no stack trace.
- `HDR-SITE-003` session cookies are HttpOnly and SameSite, and Secure on
  https. `tf.sh login` keeps each cookie's name and attributes in
  `tests/.auth/<role>.setcookie`, never its value.
- `HDR-SITE-004` plain http redirects to https. It is skipped when the target
  itself is http.

A check a project has ruled out goes in `framework.json` as
`"headers": { "skip": ["csp-inline"] }`, using the bracketed name from the
finding. These are `tags=headers`, not `tags=security`: a missing header is a
missing defence, not someone reaching what they must not, so it does not pin
the panel or exit `2`. Severity is Medium for CSP, framing and CORS, and Low
for banners and nosniff. Raise CORS to Critical when the endpoint that trusts
any origin returns personal data.

## Scope — authorization only

Probe what a user is allowed to reach. **Never** send an injection payload,
brute-force a login, fuzz an input, run anything that degrades the service, or
attempt a CAPTCHA or 2FA challenge. Never act on what you reached: no deleting,
modifying or exporting the data a probe exposed.

And never run any of this against a non-local `base_url`. `tf.sh preflight`
refuses one without `allow_remote`, and that refusal is a feature.
