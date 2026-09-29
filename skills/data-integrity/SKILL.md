---
name: data-integrity
description: Prove that what a web app saves is what it was sent, and that its records only move between states the code allows - round-trip reads in a fresh request, truncation and encoding, owner and timestamp fields, deletes and orphans, and illegal state transitions such as cancelling a shipped order. Use for /testwright:run --data, when writing DATA or STATE cases, when reading a state machine out of the code, or when a user asks whether data is actually persisted correctly.
---

# Data integrity

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

Two agents, one idea: **the success message is not evidence.** A write is
proved by reading the record back. A state rule is proved by trying the move
it forbids.

- `data-verifier` writes `DATA-NNN` cases for every flow whose `writes` field
  in `tests/.cache/flows.txt` is not `-`.
- `state-machine-mapper` writes `tests/.cache/states.txt` and `STATE-NNN`
  cases for every move the code forbids, plus legal moves no flow covers.

Both run under `--data`, after `flow-mapper`, one call per feature. Their
cases write, so they are `tags=destructive`, `status=Skipped`, and run only
with `--allow-destructive`. Checklist categories 5 (CRUD & Persistence), 8
(Workflow & States) and 19 (Database & Data Verification).

## What a fresh read is

- a new request to the app's own read route (`GET /api/notes/7`, the detail
  page), made **after** the write returned;
- for a page, a new navigation to the view, not the page the form redirected
  to with the values still in memory;
- never the write's own response body. An API that echoes the request back
  proves nothing about what it stored.

## What to compare

| Field kind | Expected on the read |
| --- | --- |
| Sent by the client | Byte for byte what was sent: the longest allowed value, Unicode, apostrophes and emoji included. Truncation is the classic silent bug |
| Computed by the server | Present and plausible. Owner = the signed-in user, never a client-supplied value. `created_at` set; `updated_at` moves on update |
| Not accepted from the client | Unchanged, even when the client sent it (`role`, `owner_id`, `price` on an order line). That is mass assignment |
| After delete | 404, or marked deleted when the code soft-deletes, and absent from every list. Records that belonged to it are removed or re-parented, never left orphaned |

## The state file

`tests/.cache/states.txt`, one machine per line, four tab-separated fields:

```
entity <TAB> states <TAB> allowed moves <TAB> actions
order	pending|paid|shipped|delivered|cancelled	pending>paid|pending>cancelled|paid>shipped|paid>cancelled|shipped>delivered	pay=POST /api/orders/{id}/pay@app.py:412|ship=POST /api/orders/{id}/ship@app.py:412|cancel=POST /api/orders/{id}/cancel@app.py:405!unguarded
```

`!unguarded` marks an action whose handler checks no current state. Its
illegal moves are the most likely real bugs, so they are written and
reported first.

## A STATE case passes when

The move is refused (4xx, or a visible error on a page) **and** a fresh read
shows the state unchanged. A 4xx that changed the state anyway is a failure:
the guard ran after the write.

## Database checks

Only with `"db": { "readonly_url": "..." }` in `tests/credentials.json`, which
stays out of git like every other secret. Only as a single `SELECT` through
the project's own client. Never select a password, hash or token column, and
never print the URL. Without it, the app's own read route is the evidence,
which is usually the better test anyway: it is what users see.
