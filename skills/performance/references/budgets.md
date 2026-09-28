# Performance budgets

Every budget lives in `tests/framework.json`. A missing key uses the default
below. `perf_budget_ms` sits at the top level, where it has always been, so a
suite written before the `perf` block existed keeps working.

```json
{
  "perf_budget_ms": 3000,
  "perf": {
    "ttfb_ms": 800,
    "max_html_kb": 500,
    "page_repeat": 3,
    "api_p95_ms": 500,
    "api_max_kb": 256,
    "repeat": 10,
    "expect_compression": true,
    "vitals": { "lcp_ms": 2500, "cls": 0.1, "tbt_ms": 200, "max_kb": 2048, "max_requests": 100 },
    "load": {
      "targets": ["/"],
      "allow_hosts": [],
      "users": 10, "seconds": 15,
      "max_users": 20, "max_seconds": 60,
      "max_error_rate": 0.01, "p95_ms": 1500
    }
  }
}
```

| Key | Default | Checked by | Why this number |
| --- | --- | --- | --- |
| `perf_budget_ms` | 3000 | `PERF-NNN` | full HTML response; past 3 s most visitors have given up |
| `perf.ttfb_ms` | 800 | `PERF-NNN` | Google's "good" time to first byte |
| `perf.max_html_kb` | 500 | `PERF-NNN` | HTML that large is usually inlined data or a whole list rendered at once |
| `perf.page_repeat` | 3 | `PERF-NNN` | samples after the warm-up; the median is judged (max 10) |
| `perf.api_p95_ms` | 500 | `PERF-API-NNN`, api `PERF-RISK-NNN` | an endpoint a page waits on should answer inside half a second, nearly every time |
| `perf.api_max_kb` | 256 | `PERF-API-NNN` | over this with no paging parameter is reported as an unpaginated list |
| `perf.repeat` | 10 | `PERF-API-NNN` | samples after the warm-up; p95 is judged (max 50) |
| `perf.expect_compression` | `true` | `PERF-NNN`, `PERF-SITE-002` | set `false` when a CDN or proxy in front of production compresses and the dev server does not |
| `perf.vitals.lcp_ms` | 2500 | `PERF-WV-NNN` | Core Web Vitals "good" LCP |
| `perf.vitals.cls` | 0.1 | `PERF-WV-NNN` | Core Web Vitals "good" CLS |
| `perf.vitals.tbt_ms` | 200 | `PERF-WV-NNN` | lab stand-in for INP; Lighthouse's "good" TBT |
| `perf.vitals.max_kb` | 2048 | `PERF-WV-NNN` | total bytes for one page, all resources |
| `perf.vitals.max_requests` | 100 | `PERF-WV-NNN` | requests for one page |
| `perf.load.targets` | `["/"]` | `tf.sh perf cases` | routes that get a `PERF-LOAD` case; GET only |
| `perf.load.allow_hosts` | `[]` | `tf.sh perf load` | non-local hosts you may load-test, on top of `allow_remote` |
| `perf.load.users` / `seconds` | 10 / 15 | `PERF-LOAD-NNN` | concurrent curl workers, and how long each runs |
| `perf.load.max_users` / `max_seconds` | 20 / 60 | `PERF-LOAD-NNN` | hard caps; `users`/`seconds` above them are clamped |
| `perf.load.max_error_rate` | 0.01 | `PERF-LOAD-NNN` | 5xx or no response, as a fraction of all requests |
| `perf.load.p95_ms` | 1500 | `PERF-LOAD-NNN` | p95 under load; looser than `api_p95_ms` on purpose |

Changing a budget changes what "passing" means for everyone reading the
workbook. Change it in the same commit as the reason.
