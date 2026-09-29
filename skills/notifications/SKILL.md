---
name: notifications
description: Test the emails a web app sends against a sandbox outbox (Mailpit or MailHog), never real delivery - that each expected message arrives after its trigger, and that every message is safe and complete - no password, key, token or card number, no unfilled template, working same-site links, a subject and a plain-text part. Use for /testwright:run --notifications, when writing NOTIF cases, or when a user asks to test emails, password resets, invites or receipts.
---

# Notifications

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

## The sandbox, never real mail

Point the app's SMTP settings at a local catcher while testing. Nothing
leaves the machine:

```sh
docker run -d -p 8025:8025 -p 1025:1025 axllent/mailpit   # SMTP :1025, API :8025
```

Then set `SMTP_HOST=localhost SMTP_PORT=1025` (or the framework's
equivalent) and `"notifications": { "outbox": "http://localhost:8025" }` in
`tests/framework.json`. MailHog's API works too. The engine refuses an outbox
on any host that is not local: a remote outbox is somebody's real mail.
Reading it needs `python3` (standard library only); without it, cases are
UNJUDGED.

## The run

```sh
tf.sh notifications mark     # before the run: only mail after this counts
... run the suite (run-api fires the triggers) ...
tf.sh notifications run      # judge every email since the mark
```

- `NOTIF-SITE-001` judges **every** email since the mark.
- `NOTIF-NNN`, written by `outbox-checker` from the code that sends mail,
  asserts one message arrived. Its Test Data is `to: <address> | subject:
  <words>`, and its trigger is a separate `api` case
  (`tags=notifications-trigger`).

## A clean email

| Check | Why |
| --- | --- |
| It arrives, to the right address, with the expected subject | The feature exists only in the inbox |
| A subject | Mail with no subject is spam-filtered and unreadable in a list |
| A plain-text part | Text-only clients, screen readers and spam filters |
| Same-site links return 2xx | A reset or confirm link that 404s makes the feature broken |
| No password, key, token, card number or SSN in it | Email is stored, forwarded and searched forever. A reset *link* with a single-use token is fine; a password is not |
| No `{{template}}`, `undefined` or `[object Object]` | "Hi {{first_name}}" in a customer's inbox |

Off-site links are counted and never fetched. Findings go to
`tests/evidence/<id>/notifications.txt`, naming the message by its subject,
and, like every privacy finding, never quoting the secret itself.

## Severity

A password or token in clear is **Critical**. A broken reset or confirm
link, or an expected message that never arrives, is **High**. A missing
plain-text part or subject is **Low**.

## Out of scope

Deliverability (SPF, DKIM, DMARC, reputation), rendering in specific mail
clients, and SMS carriers. Check SMS only through a provider's test API when
it offers one, and never to a real number.
