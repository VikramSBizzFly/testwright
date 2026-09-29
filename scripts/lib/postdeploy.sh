# shellcheck shell=sh
# lib/postdeploy.sh -- postdeploy: a read-only smoke check of a live deploy
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Everything else in this engine refuses a non-local host: the production
# guard exists because a test suite that writes is dangerous against real
# data. A deploy still deserves one question -- is it up and serving what it
# should? -- and that question can be asked without writing anything. So this
# is the one command that talks to a remote host on purpose, and it is fenced
# differently:
#
#   - its target is `postdeploy.base_url`, never the suite's base_url, so it
#     cannot be pointed at production by accident;
#   - GET only, no cookies, no credentials, no session: an anonymous visitor;
#   - only `postdeploy.routes`, or else the public `smoke` cases' routes;
#   - at most `postdeploy.max_requests` (30), one request a second;
#   - without --yes it prints the plan and sends nothing.
#
# Checks per route: it answers 2xx (after at most 3 redirects, none to an
# error page), within `postdeploy.max_ms` (3000); an HTML page has a <title>
# and no stack trace. Once per host: an https certificate valid for at least
# `postdeploy.min_cert_days` (14) more days. Results go to a results file and
# the summary panel; nothing is written to the case store.

cmd_postdeploy() {
  _yes=0; [ "${1:-}" = "--yes" ] && _yes=1
  have curl || die "postdeploy: curl not found"
  _pd="$(json_get "$FRAMEWORK" postdeploy.base_url 2>/dev/null || true)"
  _pd="$(printf '%s' "$_pd" | sed 's#/*$##')"
  [ -n "$_pd" ] || die3 "postdeploy: set \"postdeploy\": { \"base_url\": \"https://...\" } in $FRAMEWORK -- it is never taken from credentials.json"
  _pdhost="$(_seo_host "$_pd")"
  _max="$(_chk_num postdeploy.max_requests 30)"; _ms="$(_chk_num postdeploy.max_ms 3000)"
  _days="$(_chk_num postdeploy.min_cert_days 14)"

  mkdir -p "$CACHE" "$RESULTS"
  _chk_list postdeploy routes > "$CACHE/.pd.$$"
  if [ ! -s "$CACHE/.pd.$$" ] && [ -f "$CSV" ]; then
    cmd_select --tag smoke --cols route,role,method --format plain 2>/dev/null |
      awk -F '\t' '($2 == "" || $2 == "nobody") && ($3 == "" || toupper($3) == "GET") && $1 ~ /^\// && $1 !~ /[{<:*]/ && !S[$1]++ { print $1 }' > "$CACHE/.pd.$$"
  fi
  [ -s "$CACHE/.pd.$$" ] || echo / > "$CACHE/.pd.$$"
  head -n "$_max" "$CACHE/.pd.$$" > "$CACHE/.pd.$$.r"; mv "$CACHE/.pd.$$.r" "$CACHE/.pd.$$"
  _n="$(grep -c . "$CACHE/.pd.$$")"

  echo "postdeploy: $_n GET request(s) to $_pdhost, one a second, anonymous, read-only:" >&2
  sed 's/^/  /' "$CACHE/.pd.$$" >&2
  if [ "$_yes" != 1 ]; then
    rm -f "$CACHE/.pd.$$"; echo "postdeploy: nothing sent. Re-run with --yes to check the deploy." >&2; return 0
  fi

  out="$RESULTS/run-$(date +%Y%m%d-%H%M%S).csv"
  echo 'id,type,role,route,expected,actual,verdict,ms' > "$out"
  _t="$CACHE/.pd.$$"; _i=0
  _tf_progress_init "$_n"
  while IFS= read -r _r; do
    [ -n "$_r" ] || continue
    _i=$((_i + 1)); _id="$(printf 'POSTDEPLOY-%03d' "$_i")"
    [ "$_i" -gt 1 ] && sleep 1
    : > "$_t.find"
    _w="$(curl -s -D "$_t.hdr" -o "$_t.body" -L --max-redirs 3 --max-time 30 -A 'Mozilla/5.0 (compatible; testwright-postdeploy)' \
           -w '%{http_code} %{time_total} %{url_effective}' "$_pd$_r" 2>/dev/null)"
    set -- $_w
    _code="${1:-000}"; _ms_got="$(printf '%s' "${2:-0}" | awk '{ printf "%d", $1 * 1000 }')"; _eff="${3:-}"
    case "$_code" in
      2*) ;;
      000) echo "no response (DNS, TLS or timeout)" >> "$_t.find" ;;
      *) echo "answers HTTP $_code" >> "$_t.find" ;;
    esac
    case "$(printf '%s' "$_eff" | tr 'A-Z' 'a-z')" in *error*|*maintenance*|*/500*|*/404*) echo "redirected to $_eff" >> "$_t.find" ;; esac
    [ "$_ms_got" -gt "$_ms" ] && echo "took ${_ms_got}ms (postdeploy.max_ms is ${_ms}ms)" >> "$_t.find"
    if tr -d '\r' < "$_t.hdr" | grep -qi '^content-type:.*html'; then
      grep -qi '<title[^>]*>[^<]' "$_t.body" || echo "the page has no <title> (an empty or error page?)" >> "$_t.find"
      grep -qE 'Traceback \(most recent|Whoops, looks like|Exception in thread|Werkzeug Debugger|Fatal error:' "$_t.body" &&
        echo "the page shows a stack trace or debug screen" >> "$_t.find"
    fi
    if [ -s "$_t.find" ]; then _v=FAIL; _a="$(head -1 "$_t.find")"; else _v=PASS; _a="HTTP $_code in ${_ms_got}ms"; fi
    [ "$_code" = 000 ] && _v=ERROR
    printf '%s,postdeploy,nobody,%s,2xx within %sms,%s,%s,%s\n' "$_id" "$(_api_nocomma "$_r")" "$_ms" \
      "$(_api_nocomma "$_a" | cut -c1-200)" "$_v" "$_ms_got" >> "$out"
    _tf_progress_tick "$_v" postdeploy "$_id"
  done < "$CACHE/.pd.$$"

  # The certificate, once per host.
  case "$_pd" in https://*)
    _exp="$(curl -sv -o /dev/null --max-time 20 "$_pd/" 2>&1 | sed -n 's/^\*[[:space:]]*expire date:[[:space:]]*//p' | head -1)"
    _left=""
    if [ -n "$_exp" ]; then
      _es="$(date -d "$_exp" +%s 2>/dev/null || date -j -f '%b %d %T %Y %Z' "$_exp" +%s 2>/dev/null || echo "")"
      [ -n "$_es" ] && _left=$(( (_es - $(date +%s)) / 86400 ))
    fi
    if [ -z "$_left" ]; then _v=UNJUDGED; _a="could not read the certificate's expiry"
    elif [ "$_left" -lt "$_days" ]; then _v=FAIL; _a="the TLS certificate expires in ${_left} day(s) (postdeploy.min_cert_days is $_days)"
    else _v=PASS; _a="certificate valid for ${_left} more days"; fi
    printf 'POSTDEPLOY-TLS,postdeploy,nobody,/,cert valid %s+ days,%s,%s,0\n' "$_days" "$(_api_nocomma "$_a")" "$_v" >> "$out" ;;
  esac
  _tf_progress_done
  rm -f "$_t" "$_t".*
  { echo "time=$(date +%H:%M:%S)"; echo "skipped=0"; echo "unjudged=0"; } > "${out%.csv}.meta"
  cmd_summary "$out"
}
