---
name: privacy
description: Find where a web app gives away personal data or secrets - keys and card or ID numbers in page source, passwords and tokens in URLs, API responses that expose password hashes or tokens, personal pages a shared cache may keep, trackers that load before consent, and tokens or personal data left in browser storage. Use for /testwright:run --privacy, when writing or judging a tags=privacy case, or when a user asks whether an app leaks personal data, respects cookie consent, or is GDPR/CCPA-ready in what it observably does.
---

# Privacy

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

This is about **observable behaviour**, not a legal opinion: what the app sends,
what it stores in the browser, and whom it tells. Whether a finding breaks a
particular law is for the team and their counsel. That something personal
left the app when it should not have is a fact a test can prove.

## Where each check runs

| Case | Tags | What it proves | Runs on |
| --- | --- | --- | --- |
| `PRIV-NNN` | `privacy` | No key, token, private key, card number (Luhn) or SSN in the page source. No sensitive value in a link's URL. No password form submitted by GET. A personal page is `Cache-Control: private` or `no-store` | `tf.sh privacy run`, curl, free |
| `PRIV-API-NNN` | `privacy` | The JSON of a GET endpoint the suite requests has no `password`, `password_hash`, `salt`, `secret`, `api_key`, `ssn`, `card_number` or `cvv` field, and no token outside a sign-in endpoint | `tf.sh privacy run`, curl, free |
| `PRIV-SITE-001` | `privacy` | The home page links to a privacy policy that loads | `tf.sh privacy run`, curl, free |
| `PRIV-BR-NNN` | `privacy,browser` | Trackers load only after consent, and rejecting consent stops them. No token, email or card number sits in localStorage or sessionStorage. No session-like cookie is readable from script | `privacy-auditor`, one browser call |

`tf.sh privacy cases <routes> <privileged>` writes them all. The engine leaves
each browser case UNJUDGED and lists it in `tests/.cache/privacy/browser.txt`.

## The rule that overrides everything: never copy what you found

Evidence says **what kind** of thing leaked, **where**, and at most a masked
prefix (`abcd... (24 chars)`). It never contains the value. A key pasted into
`tests/evidence/` or a bug report has not been reported, it has been leaked a
second time, into a folder that often ends up in CI artifacts. The engine
masks for you. An agent writing evidence must do the same.

## Consent

`privacy.consent_required: true` in `tests/framework.json` makes every tracker
before consent a failure, whether or not the page shows a banner. Set it for
an audience in the EU, the UK, California or anywhere else that requires
opt-in. Without it, trackers fail only on a page that shows a consent banner,
because the banner is the app's own promise. `privacy.allow_hosts` lists
third parties the team has decided are fine: its CDN, a font host.
`references/trackers.md` is the list the auditor matches hosts against.

## Severity

| Finding | Severity |
| --- | --- |
| A secret key, private key or password hash exposed to the client | Critical |
| Another person's personal data (card, SSN, email) visible to someone else | Critical |
| A token in localStorage; a session cookie readable from script | High |
| A password or token in a URL; a personal page cacheable by shared caches | High |
| Trackers before consent where consent is required, or after it is rejected | High |
| An email in an HTML comment; no privacy-policy link | Low |

## Out of scope

Legal advice, the content of the privacy policy, data retention, what
happens in the database or third-party systems, and consent records kept
server-side. Those need access or judgement this tool does not have.
