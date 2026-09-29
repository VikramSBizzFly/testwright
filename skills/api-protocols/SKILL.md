---
name: api-protocols
description: Test the parts of a web app that are not plain pages and REST - a GraphQL API (per-field authorization, required arguments, depth, batching and introspection limits, via graphql-case-author), realtime channels over WebSocket, Socket.IO or Server-Sent Events (session, room isolation, message shape, reconnect, via websocket-prober), and the mobile-web layer (manifest, service worker offline page, zoom, input types, via mobile-web-auditor). Use for /testwright:run --realtime or --mobile, when the app has a GraphQL endpoint, or when a user asks to test GraphQL, websockets, realtime updates, a PWA or offline mode.
---

# API protocols

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

## GraphQL (`graphql-case-author`)

One URL, many operations, so the route sweep sees one endpoint and the RBAC
matrix misses every field. **Authorization in GraphQL is per field and per
resolver.** That is what the cases target.

- Every case is `type=api`, `method=POST`, with a JSON body
  `{"query": ..., "variables": ...}`. It runs on curl through `run-api`, free.
- **A refusal is usually HTTP 200** with `"errors"` and `"data": null`. So a
  refusal case says `expect_code=200` and puts the refusal in Expected, and
  the triager reads the body when it fails. A GraphQL refusal returning 401
  is fine too, and the case can say so.
- Once per endpoint:
  - **introspection** from an anonymous client should be off outside
    development;
  - **depth**: 15 nested levels should be refused;
  - **batching**: 50 queries in one request should be refused or capped.

  Each is a single request, never a flood.
- Mutations are `destructive` and `Skipped` until `--allow-destructive`.

## Realtime (`--realtime`, `websocket-prober`)

curl cannot speak WebSocket, so the probes run in the page's own origin
through `browser_evaluate`, the way the app's client connects. Per channel:

| Check | Pass |
| --- | --- |
| Needs a session | an anonymous connection closes, errors or gets an auth error, and never streams data |
| Room isolation | subscribing to another user's room (by an id taken from their real data, never guessed) is refused |
| Message shape | every field the client reads is present in the server's message |
| Reconnect | after 3 s offline (`context.setOffline`), the page reconnects without a reload |

A probe sends a few messages, never a flood, and never a message that
writes unless `--allow-destructive`.

## Mobile web (`--mobile`, `mobile-web-auditor`)

What `--responsive` does not check:

| Rule | Why |
| --- | --- |
| No `user-scalable=no` or `maximum-scale<2` | Blocking zoom fails WCAG 1.4.4, and people with low vision need it |
| A manifest with `name`, `start_url`, `display` and 192/512 icons, when the app presents itself as installable | Otherwise "Add to Home Screen" is broken or absent |
| A service worker serves an offline page | Otherwise the browser's own error page appears inside an "app" |
| `type=email` / `type=tel` / `inputmode=numeric` and `autocomplete=one-time-code` where they fit | The right keyboard, and one-tap codes |
| No hover-only controls | A phone has no hover |

A plain website with no manifest and no service worker is not failed for
lacking them. Native apps are out of scope.
