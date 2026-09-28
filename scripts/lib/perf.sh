# shellcheck shell=sh
# lib/perf.sh -- perf: how fast the app answers, over curl
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Most of what makes an app slow is visible from outside without a browser:
# time to first byte, how big each response is, whether it is compressed,
# whether a static file is cached, how an endpoint's latency spreads over ten
# requests, and what happens when twenty people ask at once. All of that is a
# curl request and costs no tokens. What is not -- Largest Contentful Paint,
# layout shift, long tasks, render-blocking scripts -- only exists inside a
# browser, so those cases go to the `perf-auditor` agent instead of being
# guessed at here. They are UNJUDGED `needs-browser`, listed in
# tests/.cache/perf/vitals.txt.
#
# Every case carries `tags=perf`. The ids say what each one checks:
#
#   PERF-NNN        one per page: server timing, HTML size, compression
#   PERF-API-NNN    one per GET endpoint: p50/p95 over `perf.repeat` requests
#   PERF-WV-NNN     one per page, `tags=perf,vitals`: Web Vitals, in a browser
#   PERF-LOAD-NNN   `tags=perf,load`: concurrent users, only under `perf load`
#   PERF-SITE-001   every same-site asset the pages link resolves
#   PERF-SITE-002   text assets are compressed
#   PERF-SITE-003   static assets can be cached
#
# `perf-case-author` adds PERF-RISK-NNN cases from reading the code; they run
# here (type=api, or a page without `vitals`) or in the browser (with `vitals`).
#
# Timing is noisy, so no verdict rests on one request: the first request warms
# the route up and is thrown away, and the verdict is taken on the median (a
# page) or the 95th percentile (an endpoint) of the rest.

cmd_perf() {
  _perf_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_perf_sub" in
    cases) _perf_cases "$@" ;;
    run)   _perf_run "$@" ;;
    load)  _perf_load "$@" ;;
    *) die "perf: expected 'cases <routes> [privileged]', 'run [--only <ids>]' or 'load [--yes]'" ;;
  esac
}

# ===================================================================== cases

# perf cases [routes_file] [privileged_file] -- case rows for `merge`.
#
# Pages come from the route list: no API routes and no parameterised ones (a
# made-up id times a 404, not the page). A privileged page is timed as the
# first role in credentials.json, since that is who actually waits for it.
# Endpoints come from the suite's own GET `type=api` cases, which already know
# the route and the role -- a perf case is never a second guess at either.
_perf_cases() {
  routes_file="${1:-$CACHE/routes.txt}"; priv_file="${2:-}"
  [ -f "$routes_file" ] || die "perf cases: no route list at $routes_file"
  if [ -n "$priv_file" ] && [ -f "$priv_file" ]; then
    priv="$(cat "$priv_file")"
  else
    priv="$(grep -iE '/(admin|settings|manage|internal|config|users|roles|permissions|billing|audit|reports?|payroll|employees|dashboard|account)' "$routes_file" || true)"
  fi
  first_role="$(json_keys "$CREDS" roles 2>/dev/null | head -1)"

  printf '%s,type,route,tags,role\n' "$HEADER"
  _perf_site_case 1 "Every file the pages load actually arrives" \
    "Fetch every same-site script, stylesheet and image the timed pages link" \
    "Each returns 200; none is missing or failing"
  _perf_site_case 2 "Text files are sent compressed" \
    "Fetch each same-site script and stylesheet with Accept-Encoding: gzip, br" \
    "Every text file over 1 KB comes back gzip or br encoded"
  _perf_site_case 3 "Static files can be cached by the browser" \
    "Fetch each same-site script, stylesheet and image and read its caching headers" \
    "Each has Cache-Control with a max-age, or an ETag / Last-Modified to revalidate"

  n=0; p=0
  while IFS= read -r route; do
    route="$(printf '%s' "$route" | tr -d '\r')"
    case "$route" in
      ''|*/api/*|/api/*|*:*|*'['*|*'<'*|*'{'*|*'*'*|*.txt|*.xml|*.js|*.css|*.png|*.jpg|*.svg|*.ico) continue ;;
    esac
    who=nobody; pre="Not logged in"
    if printf '%s\n' "$priv" | grep -qxF -- "$route"; then
      [ -n "$first_role" ] || continue
      who="$first_role"; pre="Logged in as $first_role"
    fi
    n=$((n + 1))
    printf 'PERF-%03d,Performance,%s,%s,%s,%s,,%s,,Not Run,page,%s,perf,%s\n' \
      "$n" \
      "$(csv_esc "$route answers quickly")" \
      "$(csv_esc "Server response time and size of $route")" \
      "$(csv_esc "$pre")" \
      "$(csv_esc "Request $route once to warm it up | then 3 more times and take the median")" \
      "$(csv_esc "First byte within perf.ttfb_ms (800 ms); whole response within perf_budget_ms (3000 ms); HTML under perf.max_html_kb; sent compressed; at most one redirect")" \
      "$route" "$who"
    printf 'PERF-WV-%03d,Performance,%s,%s,%s,%s,,%s,,Not Run,page,%s,"perf,vitals",%s\n' \
      "$n" \
      "$(csv_esc "$route loads and settles fast in a real browser")" \
      "$(csv_esc "Core Web Vitals and page weight of $route")" \
      "$(csv_esc "$pre")" \
      "$(csv_esc "Open $route in a browser | read LCP, CLS, long tasks, requests and bytes from the Performance API")" \
      "$(csv_esc "LCP within 2500 ms; CLS under 0.1; long tasks under 200 ms in total; page weight and request count within budget; nothing render-blocking that could be deferred")" \
      "$route" "$who"
  done < "$routes_file"

  # Endpoints: each distinct route+role among the suite's GET api cases.
  if [ -f "$CSV" ] && [ -f "$STATE" ]; then
    cmd_select --type api --cols id,route,role,method,tags --format csv 2>/dev/null |
      awk "$AWKLIB"'NR > 1 { csvsplit($0, F)
        m = toupper(F[4]); if (m != "" && m != "GET") next
        t = "," F[5] ","
        if (index(t, ",perf,") || index(t, ",destructive,") || index(t, ",ends-session,")) next
        if (F[2] == "" || F[2] ~ /[:{<\[*]/ || F[2] ~ /(log|sign)[-_]?(out|off)/) next
        k = F[2] "\t" F[3]; if (k in SEEN) next; SEEN[k] = 1
        print F[2] "\t" F[3] }' > "$CACHE/.perf-api.$$"
    while IFS="$(printf '\t')" read -r route who; do
      [ -n "$route" ] || continue
      p=$((p + 1))
      pre="Not logged in"; case "$who" in ''|nobody|anonymous) who=nobody ;; *) pre="Logged in as $who" ;; esac
      printf 'PERF-API-%03d,Performance,%s,%s,%s,%s,,%s,,Not Run,api,%s,perf,%s\n' \
        "$p" \
        "$(csv_esc "GET $route stays fast when asked repeatedly")" \
        "$(csv_esc "Latency spread and response size of GET $route")" \
        "$(csv_esc "$pre")" \
        "$(csv_esc "Request GET $route once to warm it up | then perf.repeat (10) more times")" \
        "$(csv_esc "95th percentile within perf.api_p95_ms (500 ms); response under perf.api_max_kb, or paged")" \
        "$route" "$who"
    done < "$CACHE/.perf-api.$$"
    rm -f "$CACHE/.perf-api.$$"
  fi

  # Load targets: framework.json perf.load.targets, else the home page.
  l=0
  { _seo_json_list "$FRAMEWORK" targets; } > "$CACHE/.perf-load.$$" 2>/dev/null
  [ -s "$CACHE/.perf-load.$$" ] || echo / > "$CACHE/.perf-load.$$"
  while IFS= read -r route; do
    [ -n "$route" ] || continue
    l=$((l + 1))
    printf 'PERF-LOAD-%03d,Performance,%s,%s,Not logged in,%s,,%s,,Not Run,%s,%s,"perf,load",nobody\n' \
      "$l" \
      "$(csv_esc "$route holds up with many users at once")" \
      "$(csv_esc "Concurrent load on $route - opt-in, sends real traffic, local or allow-listed hosts only")" \
      "$(csv_esc "perf.load.users (10) simulated users request $route for perf.load.seconds (15)")" \
      "$(csv_esc "Error rate under perf.load.max_error_rate (1%); 95th percentile within perf.load.p95_ms (1500 ms)")" \
      "$(case "$route" in /api/*) echo api ;; *) echo page ;; esac)" "$route"
  done < "$CACHE/.perf-load.$$"
  rm -f "$CACHE/.perf-load.$$"

  echo "perf: $n page case(s), $n vitals case(s), $p endpoint case(s), $l load case(s) + 3 site case(s)" >&2
}

_perf_site_case() { # <n> <scenario> <steps> <expected>
  printf 'PERF-SITE-%03d,Performance,%s,,Not logged in,%s,,%s,,Not Run,page,/,perf,nobody\n' \
    "$1" "$(csv_esc "$2")" "$(csv_esc "$3")" "$(csv_esc "$4")"
}

# ============================================================== shared setup

# Budgets, from framework.json, with the defaults the skill documents.
_perf_budgets() {
  _perf_num() { _v="$(json_get "$FRAMEWORK" "$1" 2>/dev/null || true)"
    case "$_v" in ''|*[!0-9.]*) echo "$2" ;; *) echo "$_v" ;; esac; }
  B_PAGE="$(_perf_num perf_budget_ms 3000)"
  B_TTFB="$(_perf_num perf.ttfb_ms 800)"
  B_HTML_KB="$(_perf_num perf.max_html_kb 500)"
  B_API_P95="$(_perf_num perf.api_p95_ms 500)"
  B_API_KB="$(_perf_num perf.api_max_kb 256)"
  B_REPEAT="$(_perf_num perf.repeat 10)"
  B_PAGE_REPEAT="$(_perf_num perf.page_repeat 3)"
  B_COMPRESS="$(json_get "$FRAMEWORK" perf.expect_compression 2>/dev/null || echo true)"
  [ "$B_REPEAT" -gt 50 ] 2>/dev/null && B_REPEAT=50
  [ "$B_PAGE_REPEAT" -gt 10 ] 2>/dev/null && B_PAGE_REPEAT=10
  [ "$B_REPEAT" -ge 1 ] 2>/dev/null || B_REPEAT=10
  [ "$B_PAGE_REPEAT" -ge 1 ] 2>/dev/null || B_PAGE_REPEAT=3
}

_perf_setup() {
  need_csv
  assert_target_allowed
  have curl || die "perf: curl not found"
  base="$(json_get "$CREDS" base_url | sed 's#/*$##')"
  base_host="$(_seo_host "$base")"
  roles="$(json_keys "$CREDS" roles 2>/dev/null | tr '\n' ' ')"
  mkdir -p "$RESULTS" "$CACHE"
  ts="$(date +%Y%m%d-%H%M%S)"
  out="$RESULTS/run-$ts.csv"
  echo 'id,type,role,route,expected,actual,verdict,ms' > "$out"
  PERF_DIR="$CACHE/perf"
  PERF_TMP="$CACHE/.perf.$$"
  US="$(printf '\037')"
  _perf_budgets
}

# Fold a results file back into the store -- the same mapping every runner uses.
_perf_fold() {
  now="$(date +%Y-%m-%dT%H:%M:%S)"
  awk -F, -v now="$now" 'NR > 1 {
    st = ($7 == "PASS") ? " status=Pass" : \
         (($7 == "FAIL") ? " status=Fail" : \
         ((($7 == "ERROR") || ($7 == "UNJUDGED")) ? " status=Blocked" : ""))
    act = $6
    if (act != "" && act != "-") { gsub(/ /, "+", act); act = " actual=" act } else act = ""
    print $1 st act " last_result=" $7 " last_run=" now
  }' "$1" | cmd_setmany
}

# ======================================================================= run

# perf run -- every `tags=perf` case except load. Pages and endpoints first:
# the site cases judge the assets those pages linked.
#
# perf run --only <id>[,<id>...] re-measures just those cases -- what triage
# does before calling a slow case a bug, since one slow sample can be noise.
# It keeps the rest of tests/.cache/perf/ as the last full run left it.
_perf_run() {
  only=""
  [ "${1:-}" = "--only" ] && { only="${2:-}"; [ -n "$only" ] || die "perf run: --only needs a list of ids"; }
  _perf_setup
  if [ -z "$only" ] || [ ! -d "$PERF_DIR" ]; then
    rm -rf "$PERF_DIR"; mkdir -p "$PERF_DIR"
    : > "$PERF_DIR/vitals.txt"; : > "$PERF_DIR/assets.txt"
    printf 'id\troute\trole\tttfb_ms\ttotal_ms\tbytes\tencoding\n' > "$PERF_DIR/server.tsv"
    printf 'id\troute\trole\tp50_ms\tp95_ms\tbytes\tcodes\n' > "$PERF_DIR/api.tsv"
  fi

  work="$CACHE/.perf-cases.$$"
  cmd_select --tag perf --cols id,type,route,tags,status,role --format csv 2>/dev/null |
    awk -v us="$US" -v only="$only" "$AWKLIB"'NR > 1 { csvsplit($0, F)
      if (index("," F[4] ",", ",load,")) next
      if (only != "" && !index("," only ",", "," F[1] ",")) next
      if (only != "" && index("," F[4] ",", ",vitals,")) next
      print F[1] us F[2] us F[3] us F[4] us F[5] us F[6] }' |
    sort -t "$US" -k1,1 > "$work"
  { grep -v '^PERF-SITE-' "$work"; grep '^PERF-SITE-' "$work"; } > "$work.o"
  mv "$work.o" "$work"

  run_t0=$(date +%s%N 2>/dev/null || echo 0)
  _tf_progress_init "$(grep -c . "$work" 2>/dev/null || echo 0)"
  skip=0; unjudged=0
  while IFS="$US" read -r id typ route tags status who; do
    [ -n "${id:-}" ] || continue
    if [ "$(qa_status "$status")" = "Skipped" ]; then
      skip=$((skip + 1)); _tf_progress_tick SKIP perf "$id"; continue
    fi
    : > "$PERF_TMP.find"; PERF_VERDICT=""; PERF_NOTE=""; PERF_MS=0
    expected="within budget"
    case ",$tags," in
      *,vitals,*)
        printf '%s\t%s\t%s\n' "$id" "${route:-/}" "${who:-nobody}" >> "$PERF_DIR/vitals.txt"
        PERF_VERDICT=UNJUDGED; PERF_NOTE="-"; expected="needs-browser: handed to perf-auditor" ;;
      *)
        case "$id" in
          PERF-SITE-001) _perf_assets_resolve ;;
          PERF-SITE-002) _perf_assets_compressed ;;
          PERF-SITE-003) _perf_assets_cached ;;
          *) if [ "$typ" = api ]; then _perf_api "$id" "${route:-/}" "$who"
             else _perf_page "$id" "${route:-/}" "$who"; fi ;;
        esac ;;
    esac

    if [ "$PERF_VERDICT" = SKIP ]; then
      skip=$((skip + 1)); _tf_progress_tick SKIP perf "$id"; continue
    fi
    [ -n "$PERF_VERDICT" ] || { [ -s "$PERF_TMP.find" ] && PERF_VERDICT=FAIL || PERF_VERDICT=PASS; }
    [ "$PERF_VERDICT" = UNJUDGED ] && unjudged=$((unjudged + 1))

    ev="$TESTS_DIR/evidence/$id/perf.txt"
    if [ -s "$PERF_TMP.find" ]; then
      mkdir -p "$TESTS_DIR/evidence/$id"
      { echo "$id $route"; [ -n "$PERF_NOTE" ] && echo "measured: $PERF_NOTE"; sed 's/^/- /' "$PERF_TMP.find"; } > "$ev"
      nf="$(grep -c . "$PERF_TMP.find")"
      actual="$(head -1 "$PERF_TMP.find")"
      [ "$nf" -gt 1 ] && actual="$actual (and $((nf - 1)) more in $ev)"
    else
      rm -f "$ev"; rmdir "$TESTS_DIR/evidence/$id" 2>/dev/null
      actual="${PERF_NOTE:-ok}"
    fi

    printf '%s,perf,%s,%s,%s,%s,%s,%s\n' "$id" "${who:-nobody}" "$(_api_nocomma "$route")" \
      "$(_api_nocomma "$expected")" "$(_api_nocomma "$actual" | cut -c1-200)" "$PERF_VERDICT" "$PERF_MS" >> "$out"
    _tf_progress_tick "$PERF_VERDICT" perf "$id"
  done < "$work"
  _tf_progress_done
  rm -f "$work" "$PERF_TMP".*

  _perf_fold "$out"

  run_t1=$(date +%s%N 2>/dev/null || echo 0)
  {
    echo "time=$(date +%H:%M:%S)"
    echo "duration_ms=$(( (run_t1 - run_t0) / 1000000 ))"
    echo "skipped=$skip"
    echo "skip_reason=behind a login with no session, or not a page"
    echo "unjudged=$unjudged"
  } > "${out%.csv}.meta"

  [ -s "$PERF_DIR/vitals.txt" ] &&
    echo "perf: $(grep -c . "$PERF_DIR/vitals.txt") page(s) need a browser for Web Vitals -- hand $PERF_DIR/vitals.txt to perf-auditor" >&2
  cmd_summary "$out"
}

# ------------------------------------------------------------------ fetching

# _perf_fetch <path> <role> [--follow] -- one timed request. Asks for
# compression without decoding it, so the size is what crossed the wire and
# Content-Encoding says whether the server compressed. Leaves the body in
# $PERF_TMP.body and headers in $PERF_TMP.hdr; sets P_CODE, P_TTFB, P_TOTAL
# (ms), P_BYTES, P_HOPS, P_URL.
_perf_fetch() {
  set -- "$1" "$2" "${3:-}"
  _f_args="-s -D $PERF_TMP.hdr -o $PERF_TMP.body --max-time 30 -H Accept-Encoding:gzip,deflate,br -A Mozilla/5.0(compatible;testwright-perf)"
  _f_jar=""
  _f_role="$(_api_role "$2")"
  [ -n "$_f_role" ] && [ -f "$TESTS_DIR/.auth/$_f_role.cookies" ] && _f_jar="$TESTS_DIR/.auth/$_f_role.cookies"
  if [ "$3" = --follow ]; then _f_redir="-L --max-redirs 5"; else _f_redir="--max-redirs 0"; fi
  case "$1" in http://*|https://*) _f_url="$1" ;; /*) _f_url="$base$1" ;; *) _f_url="$base/$1" ;; esac
  # shellcheck disable=SC2086
  _f_w="$(curl $_f_args $_f_redir ${_f_jar:+-b "$_f_jar"} \
          -w '%{http_code} %{time_starttransfer} %{time_total} %{size_download} %{num_redirects} %{url_effective}' \
          "$_f_url" 2>/dev/null)"
  set -- $_f_w
  P_CODE="${1:-000}"; P_BYTES="${4:-0}"; P_HOPS="${5:-0}"; P_URL="${6:-}"
  P_TTFB="$(printf '%s' "${2:-0}" | awk '{ printf "%d", $1 * 1000 + 0.5 }')"
  P_TOTAL="$(printf '%s' "${3:-0}" | awk '{ printf "%d", $1 * 1000 + 0.5 }')"
  [ -f "$PERF_TMP.body" ] || : > "$PERF_TMP.body"
  [ -f "$PERF_TMP.hdr" ] || : > "$PERF_TMP.hdr"
}

# The last response's header, lowercased -- after redirects, the final one.
_perf_hdr() {
  tr -d '\r' < "$PERF_TMP.hdr" | awk -v n="$1" 'BEGIN { n = tolower(n) ":" }
    tolower($0) ~ /^http\// { v = "" }
    tolower(substr($0, 1, length(n))) == n { v = substr($0, length(n) + 1); sub(/^[ \t]+/, "", v); v = tolower(v) }
    END { print v }'
}

_perf_find() { printf '%s\n' "$*" >> "$PERF_TMP.find"; }

# _perf_pct <p> -- the p-th percentile (nearest rank) of numbers on stdin.
_perf_pct() { sort -n | awk -v p="$1" '{ a[++n] = $1 } END { if (!n) { print 0; exit }
  r = int((p / 100) * n + 0.999999); if (r < 1) r = 1; if (r > n) r = n; print a[r] }'; }

_perf_kb() { awk -v b="$1" 'BEGIN { if (b < 1024) printf "%d B", b; else if (b < 1048576) printf (b >= 10240 ? "%d KB" : "%.1f KB"), b / 1024; else printf "%.1f MB", b / 1048576 }'; }

_perf_is_login() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *login*|*signin*|*sign-in*|*sign_in*|*/auth*|*oauth*|*sso*) return 0 ;;
  esac
  return 1
}

# ------------------------------------------------------------------ the checks

# _perf_page <id> <route> <role> -- server timing of one page.
_perf_page() {
  _id="$1"; _route="$2"; _who="$3"
  _r="$(_api_role "$_who")"
  if [ -n "$_r" ] && [ ! -f "$TESTS_DIR/.auth/$_r.cookies" ]; then
    PERF_VERDICT=UNJUDGED; PERF_NOTE="-"; expected="no session for $_r: run /testwright:setup"; return
  fi
  _perf_fetch "$_route" "$_who" --follow                 # warm-up, thrown away
  case "$P_CODE" in 000) PERF_VERDICT=ERROR; PERF_NOTE="no response"; return ;; esac
  if [ "$P_HOPS" -gt 0 ] && _perf_is_login "$P_URL"; then PERF_VERDICT=SKIP; return; fi
  case "$(_perf_hdr content-type)" in ''|*html*) ;; *) PERF_VERDICT=SKIP; return ;; esac

  : > "$PERF_TMP.ttfb"; : > "$PERF_TMP.tot"; _i=0
  while [ "$_i" -lt "$B_PAGE_REPEAT" ]; do
    _perf_fetch "$_route" "$_who" --follow
    echo "$P_TTFB" >> "$PERF_TMP.ttfb"; echo "$P_TOTAL" >> "$PERF_TMP.tot"
    _i=$((_i + 1))
  done
  _ttfb="$(_perf_pct 50 < "$PERF_TMP.ttfb")"; _tot="$(_perf_pct 50 < "$PERF_TMP.tot")"
  _enc="$(_perf_hdr content-encoding)"
  PERF_MS="$_tot"
  PERF_NOTE="ttfb ${_ttfb}ms total ${_tot}ms $(_perf_kb "$P_BYTES")${_enc:+ $_enc}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_route" "$_who" "$_ttfb" "$_tot" "$P_BYTES" "${_enc:-none}" >> "$PERF_DIR/server.tsv"

  case "$P_CODE" in
    2*) ;;
    *) _perf_find "returns HTTP $P_CODE, so its timing says nothing about the page" ;;
  esac
  [ "$P_HOPS" -gt 1 ] && _perf_find "$P_HOPS redirects before the page; each costs a round trip (link the final URL)"
  [ "$_ttfb" -gt "$B_TTFB" ] && _perf_find "first byte after ${_ttfb}ms (median of $B_PAGE_REPEAT); budget perf.ttfb_ms is ${B_TTFB}ms"
  [ "$_tot" -gt "$B_PAGE" ] && _perf_find "full response after ${_tot}ms (median of $B_PAGE_REPEAT); budget perf_budget_ms is ${B_PAGE}ms"
  _max=$((B_HTML_KB * 1024))
  [ "$P_BYTES" -gt "$_max" ] && _perf_find "HTML is $(_perf_kb "$P_BYTES") on the wire; budget perf.max_html_kb is ${B_HTML_KB} KB"
  if [ "$B_COMPRESS" != false ] && [ -z "$_enc" ] && [ "$P_BYTES" -gt 1024 ]; then
    _perf_find "HTML ($(_perf_kb "$P_BYTES")) is sent uncompressed although the request accepted gzip and br"
  fi

  # Collect the same-site assets this page links, for the site cases.
  _perf_links "$_route" >> "$PERF_DIR/assets.txt"
  return 0
}

# _perf_api <id> <route> <role> -- latency spread of one endpoint.
_perf_api() {
  _id="$1"; _route="$2"; _who="$3"
  _r="$(_api_role "$_who")"
  if [ -n "$_r" ] && [ ! -f "$TESTS_DIR/.auth/$_r.cookies" ]; then
    PERF_VERDICT=UNJUDGED; PERF_NOTE="-"; expected="no session for $_r: run /testwright:setup"; return
  fi
  _perf_fetch "$_route" "$_who"                         # warm-up, thrown away
  case "$P_CODE" in 000) PERF_VERDICT=ERROR; PERF_NOTE="no response"; return ;; esac

  : > "$PERF_TMP.tot"; _codes=""; _i=0
  while [ "$_i" -lt "$B_REPEAT" ]; do
    _perf_fetch "$_route" "$_who"
    echo "$P_TOTAL" >> "$PERF_TMP.tot"; _codes="$_codes $P_CODE"
    _i=$((_i + 1))
  done
  _p50="$(_perf_pct 50 < "$PERF_TMP.tot")"; _p95="$(_perf_pct 95 < "$PERF_TMP.tot")"
  _codes="$(_api_compact $_codes)"
  PERF_MS="$_p95"
  PERF_NOTE="p50 ${_p50}ms p95 ${_p95}ms $(_perf_kb "$P_BYTES") HTTP $_codes"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_route" "$_who" "$_p50" "$_p95" "$P_BYTES" "$_codes" >> "$PERF_DIR/api.tsv"

  case "$_codes" in
    2*) ;;
    401*|403*) PERF_VERDICT=UNJUDGED; expected="refused (HTTP $_codes): timing a refusal says nothing"; return ;;
    *) _perf_find "answers HTTP $_codes; timing an error says nothing about the endpoint" ;;
  esac
  case "$_codes" in *';5'*|*';000'*) _perf_find "failed intermittently while being timed (HTTP $_codes)" ;; esac
  [ "$_p95" -gt "$B_API_P95" ] && _perf_find "95th percentile ${_p95}ms over $B_REPEAT requests (median ${_p50}ms); budget perf.api_p95_ms is ${B_API_P95}ms"
  _max=$((B_API_KB * 1024))
  if [ "$P_BYTES" -gt "$_max" ]; then
    if printf '%s' "$_route" | grep -qiE '[?&](page|limit|per_page|page_size|pagesize|offset|cursor|after|size|top|take)='; then
      _perf_find "response is $(_perf_kb "$P_BYTES"); budget perf.api_max_kb is ${B_API_KB} KB"
    else
      _perf_find "response is $(_perf_kb "$P_BYTES") with no paging parameter; an unpaginated list grows with the data (budget perf.api_max_kb ${B_API_KB} KB)"
    fi
  fi
  return 0
}

# _perf_links <route> -- same-site script, stylesheet and image URLs in the
# last fetched page, as paths, one per line.
_perf_links() {
  _enc="$(_perf_hdr content-encoding)"
  case "$_enc" in
    gzip|deflate) _body="$( (gzip -dc < "$PERF_TMP.body" || cat "$PERF_TMP.body") 2>/dev/null)" ;;
    br) return 0 ;;                                     # no portable decoder
    *) _body="$(cat "$PERF_TMP.body")" ;;
  esac
  printf '%s' "$_body" | tr '\r\n' '  ' |
    grep -oiE '<(script|img|source)[^>]*[[:space:]]src=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)|<link[^>]*>' |
    awk -v route="$1" -v host="$base_host" '
      /^<link/ { l = tolower($0); if (l !~ /rel=["'"'"']?(stylesheet|preload|modulepreload|icon)/) next
                 if (!match($0, /[[:space:]]href=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)/)) next
                 u = substr($0, RSTART + 6, RLENGTH - 6) }
      !/^<link/ { match($0, /[[:space:]]src=/); u = substr($0, RSTART + 5) }
      { gsub(/^["'"'"']|["'"'"'].*$/, "", u); sub(/[#].*$/, "", u)
        if (u == "" || u ~ /^(data|blob|javascript):/) next
        if (u ~ /^(https?:)?\/\//) { h = u; sub(/^(https?:)?\/\//, "", h); p = h; sub(/[\/?].*$/, "", h); sub(/:.*$/, "", h)
          if (tolower(h) != host) next; sub(/^[^\/]*/, "", p); u = (p == "" ? "/" : p) }
        else if (u !~ /^\//) { d = route; sub(/[^\/]*$/, "", d); u = d u }
        print u }'
}

# PERF-SITE-001 -- every linked asset arrives.
_perf_assets_list() {
  sort -u "$PERF_DIR/assets.txt" | head -60 > "$PERF_TMP.assets"
  [ -s "$PERF_TMP.assets" ] || { PERF_NOTE="no same-site assets linked from the timed pages"; return 1; }
  PERF_NOTE="$(grep -c . "$PERF_TMP.assets") asset(s) checked"
}

_perf_assets_resolve() {
  _perf_assets_list || return 0
  while IFS= read -r _a; do
    _perf_fetch "$_a" nobody --follow
    case "$P_CODE" in 2*) ;; *) _perf_find "$_a returns HTTP $P_CODE; the page waits on a file that never arrives" ;; esac
  done < "$PERF_TMP.assets"
}

# PERF-SITE-002 -- text assets compressed.
_perf_assets_compressed() {
  _perf_assets_list || return 0
  [ "$B_COMPRESS" = false ] && { PERF_NOTE="compression not expected here (perf.expect_compression)"; return 0; }
  while IFS= read -r _a; do
    _perf_fetch "$_a" nobody --follow
    case "$P_CODE" in 2*) ;; *) continue ;; esac
    case "$(_perf_hdr content-type)" in
      *javascript*|*css*|*json*|*svg*|*text/*) ;;
      *) continue ;;
    esac
    [ -z "$(_perf_hdr content-encoding)" ] && [ "$P_BYTES" -gt 1024 ] &&
      _perf_find "$_a ($(_perf_kb "$P_BYTES")) is sent uncompressed"
  done < "$PERF_TMP.assets"
  return 0
}

# PERF-SITE-003 -- static assets cacheable.
_perf_assets_cached() {
  _perf_assets_list || return 0
  while IFS= read -r _a; do
    _perf_fetch "$_a" nobody --follow
    case "$P_CODE" in 2*) ;; *) continue ;; esac
    _cc="$(_perf_hdr cache-control)"
    case "$_cc" in
      *no-store*) _perf_find "$_a is Cache-Control: no-store; every visit downloads it again" ;;
      *max-age=[1-9]*|*immutable*) ;;
      *) [ -n "$(_perf_hdr etag)$(_perf_hdr last-modified)" ] ||
           _perf_find "$_a has no Cache-Control max-age, ETag or Last-Modified; every visit downloads it again" ;;
    esac
  done < "$PERF_TMP.assets"
  return 0
}

# ====================================================================== load

# perf load [--yes] -- concurrent users against each `tags=perf,load` case.
#
# This is real traffic, so it is fenced three ways beyond the production guard:
# the host must be local or listed in perf.load.allow_hosts (allow_remote alone
# is not enough -- a staging box shared with other people is not a load
# target), users and seconds are capped, and without --yes it only prints the
# plan. No dependency: the virtual users are curl processes under xargs -P.
_perf_load() {
  yes=0; [ "${1:-}" = "--yes" ] && yes=1
  _perf_setup
  mkdir -p "$PERF_DIR"

  case "$base_host" in
    localhost|127.0.0.1|0.0.0.0|::1|*.local|*.localhost|host.docker.internal) ;;
    *) _seo_json_list "$FRAMEWORK" allow_hosts | tr 'A-Z' 'a-z' | grep -qxF -- "$base_host" ||
         die3 "perf load: refusing to load-test '$base_host'.
    It is not local and is not listed in framework.json perf.load.allow_hosts.
    Load testing sends real traffic; list the host there only if it is yours to stress." ;;
  esac

  _lnum() { _v="$(json_get "$FRAMEWORK" "$1" 2>/dev/null || true)"
    case "$_v" in ''|*[!0-9.]*) echo "$2" ;; *) echo "$_v" ;; esac; }
  users="$(_lnum perf.load.users 10)"; secs="$(_lnum perf.load.seconds 15)"
  max_users="$(_lnum perf.load.max_users 20)"; max_secs="$(_lnum perf.load.max_seconds 60)"
  max_err="$(_lnum perf.load.max_error_rate 0.01)"; p95_budget="$(_lnum perf.load.p95_ms 1500)"
  [ "$users" -gt "$max_users" ] && users="$max_users"
  [ "$secs" -gt "$max_secs" ] && secs="$max_secs"
  [ "$users" -ge 1 ] || users=1; [ "$secs" -ge 1 ] || secs=1

  work="$CACHE/.perf-load.$$"
  cmd_select --tag load --cols id,type,route,tags,status,role --format csv 2>/dev/null |
    awk -v us="$US" "$AWKLIB"'NR > 1 { csvsplit($0, F)
      if (!index("," F[4] ",", ",perf,")) next
      print F[1] us F[2] us F[3] us F[5] us F[6] }' | sort -t "$US" -k1,1 > "$work"
  ncases="$(grep -c . "$work" 2>/dev/null || echo 0)"
  [ "$ncases" -gt 0 ] || { rm -f "$work" "$out"; die "perf load: no tags=perf,load cases (tf.sh perf cases writes them)"; }

  echo "perf load: $ncases target(s) x $users user(s) x ${secs}s against $base_host (about $((ncases * secs))s)" >&2
  awk -F"$US" '{ print "  " $1 "  " $3 }' "$work" >&2
  if [ "$yes" != 1 ]; then
    rm -f "$work" "$out"
    echo "perf load: nothing sent. Re-run with --yes to start it." >&2
    return 0
  fi

  run_t0=$(date +%s%N 2>/dev/null || echo 0)
  _tf_progress_init "$ncases"
  skip=0
  while IFS="$US" read -r id typ route status who; do
    [ -n "${id:-}" ] || continue
    if [ "$(qa_status "$status")" = "Skipped" ]; then
      skip=$((skip + 1)); _tf_progress_tick SKIP perf "$id"; continue
    fi
    : > "$PERF_TMP.find"
    _jar=""; _r="$(_api_role "$who")"
    [ -n "$_r" ] && [ -f "$TESTS_DIR/.auth/$_r.cookies" ] && _jar="$TESTS_DIR/.auth/$_r.cookies"
    rm -f "$PERF_TMP".w.*
    _end=$(( $(date +%s) + secs ))
    # Each worker loops until the deadline. The jar is read (-b), never written
    # (-c): twenty processes writing one file would corrupt it.
    awk -v n="$users" 'BEGIN { for (i = 1; i <= n; i++) print i }' |
      xargs -P "$users" -I{} sh -c '
        while [ "$(date +%s)" -lt "$1" ]; do
          curl -s -o /dev/null --max-time 30 ${3:+-b "$3"} -w "%{http_code} %{time_total}\n" "$2" 2>/dev/null || echo "000 30"
        done > "$4.w.$5"' _ "$_end" "$base$route" "$_jar" "$PERF_TMP" {}
    cat "$PERF_TMP".w.* > "$PERF_TMP.all" 2>/dev/null
    rm -f "$PERF_TMP".w.*

    set -- $(awk -v s="$secs" '{ n++; if ($1 == "000" || $1 >= 500) e++; if ($1 == 429) t++; C[$1]++ }
      END { c = ""; for (k in C) c = c (c == "" ? "" : ";") k "x" C[k]
            printf "%d %d %d %.1f %s", n, e, t, (s > 0 ? n / s : 0), (c == "" ? "-" : c) }' "$PERF_TMP.all")
    _n="$1"; _e="$2"; _t="$3"; _rps="$4"; _codes="$5"
    _p95="$(awk '{ printf "%d\n", $2 * 1000 + 0.5 }' "$PERF_TMP.all" | _perf_pct 95)"
    _p50="$(awk '{ printf "%d\n", $2 * 1000 + 0.5 }' "$PERF_TMP.all" | _perf_pct 50)"
    _rate="$(awk -v e="$_e" -v n="$_n" 'BEGIN { printf "%.4f", (n > 0 ? e / n : 1) }')"
    PERF_NOTE="$users users ${secs}s: $_n requests $_rps/s p50 ${_p50}ms p95 ${_p95}ms errors $(awk -v r="$_rate" 'BEGIN { printf "%.1f", r * 100 }')%"

    verdict=PASS
    if [ "$_n" -eq 0 ]; then verdict=ERROR; PERF_NOTE="no request completed"
    else
      awk -v r="$_rate" -v m="$max_err" 'BEGIN { exit !(r > m) }' &&
        _perf_find "$_e of $_n requests failed (HTTP 5xx or no response) under $users concurrent users; budget perf.load.max_error_rate is $max_err"
      [ "$_p95" -gt "$p95_budget" ] &&
        _perf_find "95th percentile ${_p95}ms under $users concurrent users; budget perf.load.p95_ms is ${p95_budget}ms"
      [ "$_t" -gt 0 ] && echo "rate limited: $_t response(s) were HTTP 429 (not counted as errors)" >> "$PERF_TMP.note"
      [ -s "$PERF_TMP.find" ] && verdict=FAIL
    fi

    ev="$TESTS_DIR/evidence/$id/perf.txt"
    if [ -s "$PERF_TMP.find" ]; then
      mkdir -p "$TESTS_DIR/evidence/$id"
      { echo "$id $route"; echo "measured: $PERF_NOTE"; echo "status codes: $_codes"
        [ -f "$PERF_TMP.note" ] && cat "$PERF_TMP.note"; sed 's/^/- /' "$PERF_TMP.find"; } > "$ev"
      actual="$(head -1 "$PERF_TMP.find")"
    else
      rm -f "$ev"; rmdir "$TESTS_DIR/evidence/$id" 2>/dev/null
      actual="$PERF_NOTE"
    fi
    rm -f "$PERF_TMP.note"
    printf '%s,perf,%s,%s,%s,%s,%s,%s\n' "$id" "${who:-nobody}" "$(_api_nocomma "$route")" \
      "error rate <= $max_err and p95 <= ${p95_budget}ms" "$(_api_nocomma "$actual" | cut -c1-200)" "$verdict" "$_p95" >> "$out"
    _tf_progress_tick "$verdict" perf "$id"
  done < "$work"
  _tf_progress_done
  rm -f "$work" "$PERF_TMP".*

  _perf_fold "$out"
  run_t1=$(date +%s%N 2>/dev/null || echo 0)
  {
    echo "time=$(date +%H:%M:%S)"
    echo "duration_ms=$(( (run_t1 - run_t0) / 1000000 ))"
    echo "skipped=$skip"
    echo "skip_reason=marked Skipped in the workbook"
    echo "unjudged=0"
  } > "${out%.csv}.meta"
  cmd_summary "$out"
}
