# Stack detection table and output shape

## Table

| Manifest **and** runtime on PATH               | stack    | runner                | binding                      |
| ---------------------------------------------- | -------- | --------------------- | ---------------------------- |
| `package.json` + `node`/`bun`/`deno`           | `js`     | `npx playwright test` | `@playwright/test`           |
| `pyproject.toml`/`requirements.txt` + `python` | `python` | `pytest`              | `pytest-playwright`          |
| `pom.xml`/`build.gradle` + `mvn`/`gradle`      | `java`   | `mvn test`            | `com.microsoft.playwright`   |
| `*.csproj`/`*.sln` + `dotnet`                  | `dotnet` | `dotnet test`         | `Microsoft.Playwright.NUnit` |
| anything else, or runtime absent               | `none`   | —                     | —                            |

Detecting `js` does **not** mean Tier 1. Check the binding is actually present
(`node_modules/@playwright/test`, `pip show pytest-playwright`, …). Absent
binding → Tier 0, with a note.

## Output

```json
{
  "tier": 0,
  "stack": "none",
  "runner": null,
  "spec_dir": "tests/specs",
  "report": null,
  "allow_remote": false,
  "max_tokens_per_run": 200000,
  "perf_budget_ms": 3000,
  "perf": {
    "ttfb_ms": 800, "api_p95_ms": 500, "api_max_kb": 256, "repeat": 10,
    "vitals": { "lcp_ms": 2500, "cls": 0.1, "tbt_ms": 200, "max_kb": 2048, "max_requests": 100 },
    "load": { "targets": ["/"], "allow_hosts": [], "users": 10, "seconds": 15, "max_error_rate": 0.01, "p95_ms": 1500 }
  },
  "seo": { "noindex_allow": [], "max_sitemap_urls": 200 },
  "headers": { "skip": [] },
  "links": { "max_pages": 50, "max_per_page": 200 },
  "contract": { "spec": "", "strict": false },
  "privacy": { "consent_required": false, "allow_hosts": [], "trackers": [] },
  "release": {
    "min_pass_rate": 95, "max_open_critical": 0, "max_open_high": 0,
    "require_security_clean": true, "require_smoke_pass": true, "max_age_hours": 24
  }
}
```
