# Performance bug patterns

The catalogue `perf-case-author` searches for, `perf-auditor review` groups
failures by, and `bug-reporter` takes severity from. Each pattern has a **code
signal** (what to grep for, in the feature's own files only), a **runtime
symptom** (what the case measures), and the **case** that proves it.

Severity is the default; raise it one step when the slow path is on a flow
the app exists for (checkout, sign-in, the main dashboard), lower it one step
for an admin-only or rarely used page.

## Server and data

| Pattern | Code signal | Runtime symptom | Case | Severity |
| --- | --- | --- | --- | --- |
| **N+1 query** | a query, ORM getter or HTTP call inside a loop over a result set: `for ... in ...:` then `.get(`, `.find(`, `.objects.`, `fetch(`, `await db.`; lazy relations read in a template loop; no `select_related`/`prefetch_related`/`include`/`joinedload`/`with(` | p95 grows with the row count; slow even with a small response | `type=api` GET on the list, widest filter | High |
| **Unpaginated list** | a list handler returning `.all()`, `findAll()`, `SELECT` with no `LIMIT`, no `page`/`limit`/`cursor` parameter read | response size over `perf.api_max_kb` with no paging parameter | `type=api` GET on the list | High |
| **Unbounded search or export** | `LIKE '%...%'`, regex over a table, CSV/PDF export built in the request, no row cap | p95 over budget on a broad term; timeouts | `type=api` GET with a term that matches everything | Medium |
| **Missing index** | a filter or sort on a column with no index in the migrations/schema (`WHERE status =`, `ORDER BY created_at` with no `index`/`db_index`/`@@index`) | p95 grows with table size; fine on seed data | `type=api` GET with that filter; `Test Data` states the rows needed | Medium |
| **Synchronous I/O in a request** | sending mail, resizing images, calling a third-party API or `sleep` inside the handler rather than a queue/job | TTFB over budget on that route only | `type=api` or page on the route | Medium |
| **Work repeated per request** | config, templates, or a large file read or parsed on every request; no cache around an expensive computation | TTFB over budget on every page | page `PERF-NNN` | Medium |
| **Concurrency collapse** | a global lock, a single worker, a small connection pool, an in-process queue | fine alone, 5xx or timeouts under `--load` | `PERF-LOAD-NNN` | High |

## Delivery

| Pattern | Code signal | Runtime symptom | Case | Severity |
| --- | --- | --- | --- | --- |
| **No compression** | no gzip/brotli middleware, server or CDN config | `PERF-NNN` / `PERF-SITE-002` report uncompressed HTML, JS or CSS | engine | Medium |
| **No caching of static files** | static files served without `Cache-Control`, no hashed file names | `PERF-SITE-003` | engine | Low |
| **Redirect chains** | `http`→`https`→`www`→trailing slash done as separate redirects | `PERF-NNN`: more than one redirect | engine | Low |

## Front end

| Pattern | Code signal | Runtime symptom | Case | Severity |
| --- | --- | --- | --- | --- |
| **Oversized bundle** | one entry point importing a whole library (`import _ from 'lodash'`, `moment`, an icon set, a chart library on every page); no code splitting / dynamic `import()` | page weight over `vitals.max_kb`; high TBT | page, `vitals` | Medium |
| **Render-blocking resources** | `<script src>` in `<head>` without `defer`/`async`/`type=module`; several stylesheets in `<head>`; web fonts with no `font-display` | late FCP/LCP; `blocking` list in the vitals evidence | page, `vitals` | Medium |
| **Unoptimised images** | large PNG/JPEG in `public/`/`static/`; no `srcset`/`sizes`; no `loading=lazy` below the fold; no image pipeline | LCP element is an image; `oversized_images`; page weight | page, `vitals` | Medium |
| **Layout shift** | `<img>`/`<video>`/`<iframe>` without `width`/`height` or `aspect-ratio`; banners or ads injected above content; web fonts swapping late | CLS over `vitals.cls`; `unsized_images` | page, `vitals` | Medium |
| **Long tasks** | heavy work on load (parsing large JSON, sorting big arrays, synchronous loops, large hydration) | TBT over `vitals.tbt_ms` | page, `vitals` | Medium |
| **Polling or a render loop** | `setInterval` with a short delay, `useEffect` without deps that sets state, a re-fetch on every render | request count keeps climbing; TBT high | page, `vitals` | Medium |
| **Slow third-party script** | analytics, chat, A/B or tag-manager scripts loaded synchronously | third-party host in `largest` or `blocking` | page, `vitals` | Low |

## Writing the bug

A perf bug's description states, in this order: **what is slow**, **the number
against its budget** (`p95 2746 ms, budget 500 ms`), **how it was measured**
(10 requests after a warm-up; unthrottled browser), **the suspect** (the
`file:line` from the RISK case, or the resource from the vitals evidence), and
**what else it drags down** (the other cases in the same cause).
