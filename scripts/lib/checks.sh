# shellcheck shell=sh
# lib/checks.sh -- the shared skeleton of a curl check family
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# seo.sh and perf.sh each carry their own copy of this loop. Everything added
# after them -- headers, links, contract, privacy -- uses this one instead:
# pick the pages a family judges, select its cases, fetch, record one result
# row per case with its findings as evidence, fold the verdicts back into the
# store, write the .meta and print the summary.
#
# A family module defines _<fam>_case <id> <route> <role> <type> and calls
#
#   _chk_run <family> <tag> [--only <ids>]
#
# Inside _<fam>_case, a finding is `_chk_find "text"`; a verdict the finding
# list cannot express is CHK_VERDICT=SKIP|UNJUDGED|ERROR; CHK_NOTE is the
# Actual Result on a pass; CHK_EXPECTED overrides the Expected column.

# _chk_pages <routes_file> <privileged_file> -- the pages a check family can
# judge, as `route<TAB>role`. No API routes, no parameterised routes, no files.
# A privileged page is judged as the first role in credentials.json, or left
# out when there is none.
_chk_pages() {
  _cp_routes="${1:-$CACHE/routes.txt}"; _cp_priv_file="${2:-}"
  [ -f "$_cp_routes" ] || die "no route list at $_cp_routes"
  if [ -n "$_cp_priv_file" ] && [ -f "$_cp_priv_file" ]; then
    _cp_priv="$(cat "$_cp_priv_file")"
  else
    _cp_priv="$(grep -iE '/(admin|settings|manage|internal|config|users|roles|permissions|billing|audit|reports?|payroll|employees|dashboard|account)' "$_cp_routes" || true)"
  fi
  _cp_first="$(json_keys "$CREDS" roles 2>/dev/null | head -1)"
  while IFS= read -r _cp_r; do
    _cp_r="$(printf '%s' "$_cp_r" | tr -d '\r')"
    case "$_cp_r" in
      ''|*/api/*|/api/*|*:*|*'['*|*'<'*|*'{'*|*'*'*|*.txt|*.xml|*.json|*.js|*.css|*.png|*.jpg|*.svg|*.ico) continue ;;
    esac
    if printf '%s\n' "$_cp_priv" | grep -qxF -- "$_cp_r"; then
      [ -n "$_cp_first" ] || continue
      printf '%s\t%s\n' "$_cp_r" "$_cp_first"
    else
      printf '%s\tnobody\n' "$_cp_r"
    fi
  done < "$_cp_routes"
}

# _chk_pre <role> -- the Preconditions wording the engine reads back.
_chk_pre() { case "$1" in ''|nobody|anonymous) echo "Not logged in" ;; *) echo "Logged in as $1" ;; esac; }

# _chk_row <id> <module> <scenario> <description> <role> <steps> <expected> <type> <route> <tags>
_chk_row() {
  printf '%s,%s,%s,%s,%s,%s,,%s,,Not Run,%s,%s,%s,%s\n' \
    "$1" "$(csv_esc "$2")" "$(csv_esc "$3")" "$(csv_esc "$4")" "$(csv_esc "$(_chk_pre "$5")")" \
    "$(csv_esc "$6")" "$(csv_esc "$7")" "$8" "$9" "$(csv_esc "${10}")" "${5:-nobody}"
}

_chk_header() { printf '%s,type,route,tags,role\n' "$HEADER"; }

# _chk_list <object> <key> -- the string values of framework.json's
# "<object>": { "<key>": [ ... ] }, one per line. Scoped to the object, so two
# families can each have a "skip" list.
_chk_list() {
  [ -f "$FRAMEWORK" ] || return 0
  tr -d '\r\n' < "$FRAMEWORK" | awk -v o="$1" -v k="$2" '{
    p = index($0, "\"" o "\""); if (!p) exit
    r = substr($0, p + length(o) + 2)
    q = index(r, "\"" k "\""); if (!q) exit
    r = substr(r, q + length(k) + 2); if (r !~ /^[ \t]*:[ \t]*\[/) exit
    sub(/^[ \t]*:[ \t]*\[/, "", r); r = substr(r, 1, index(r, "]") - 1)
    n = split(r, A, ",")
    for (i = 1; i <= n; i++) { v = A[i]; gsub(/^[ \t]*"|"[ \t]*$/, "", v); if (v != "") print v }
  }'
}

# _chk_num <dotted.path> <default> -- a numeric setting, or the default.
_chk_num() { _v="$(json_get "$FRAMEWORK" "$1" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9.]*) echo "$2" ;; *) echo "$_v" ;; esac; }

# audit-cases <family> [routes] [privileged] -- one browser-audit case per page
# for the families judged only by an agent: i18n, resilience, memory. They
# cost nothing to write and one agent call each to run, like `responsive`.
cmd_audit_cases() {
  _fam="${1:-}"; [ $# -gt 0 ] && shift
  case "$_fam" in
    i18n)       _pre=I18N; _mod="Localization"
                _sc="%s works in every language the app offers"
                _st="Open %s in each locale | compare it with the base locale"
                _ex="Nothing clipped or overflowing that fits in the base locale; right-to-left locales mirrored; lang set; dates, numbers and currency in the locale's format; no untranslated strings" ;;
    resilience) _pre=RES; _mod="Resilience"
                _sc="%s fails gracefully when its API does"
                _st="Open %s with its API answering 500, then dropping the connection, then answering slowly"
                _ex="An error the visitor can read and a way to retry; never a spinner that never stops, a blank page or undefined; a loading state while slow" ;;
    memory)     _pre=MEM; _mod="Memory"
                _sc="%s does not leak memory as you move around it"
                _st="Open %s | move between its views ten times | measure the heap after garbage collection"
                _ex="Heap after garbage collection does not keep rising (robustness.leak_mb, 5 MB); DOM nodes do not keep growing" ;;
    *) die "audit-cases: expected i18n, resilience or memory" ;;
  esac
  _chk_header
  _n=0
  _chk_pages "${1:-$CACHE/routes.txt}" "${2:-}" > "$CACHE/.audit-pages.$$"
  while IFS="$(printf '\t')" read -r _r _who; do
    _n=$((_n + 1))
    # shellcheck disable=SC2059
    _chk_row "$(printf '%s-%03d' "$_pre" "$_n")" "$_mod" "$(printf "$_sc" "$_r")" "" "$_who" \
      "$(printf "$_st" "$_r")" "$_ex" page "$_r" "$_fam"
  done < "$CACHE/.audit-pages.$$"
  rm -f "$CACHE/.audit-pages.$$"
  echo "audit-cases: $_n $_fam case(s); one agent call each" >&2
}

# ------------------------------------------------------------------ fetching

# _chk_get <path-or-url> <role> [--follow] [extra curl args...] -- one request.
# Body in $CHK_TMP.body, headers in $CHK_TMP.hdr; sets CHK_CODE, CHK_URL,
# CHK_HOPS, CHK_LOC (the Location of an unfollowed redirect).
_chk_get() {
  _g_path="$1"; _g_role="$2"; shift 2
  _g_follow="--max-redirs 0"
  if [ "${1:-}" = --follow ]; then _g_follow="-L --max-redirs 8"; shift; fi
  _g_jar=""
  _g_r="$(_api_role "$_g_role")"
  [ -n "$_g_r" ] && [ -f "$TESTS_DIR/.auth/$_g_r.cookies" ] && _g_jar="$TESTS_DIR/.auth/$_g_r.cookies"
  case "$_g_path" in http://*|https://*) _g_url="$_g_path" ;; /*) _g_url="$base$_g_path" ;; *) _g_url="$base/$_g_path" ;; esac
  # shellcheck disable=SC2086
  _g_w="$(curl -s -D "$CHK_TMP.hdr" -o "$CHK_TMP.body" --max-time 20 $_g_follow \
          -A 'Mozilla/5.0 (compatible; testwright)' ${_g_jar:+-b "$_g_jar"} "$@" \
          -w '%{http_code} %{num_redirects} %{url_effective} %{redirect_url}' "$_g_url" 2>/dev/null)"
  # shellcheck disable=SC2086
  set -- $_g_w
  CHK_CODE="${1:-000}"; CHK_HOPS="${2:-0}"; CHK_URL="${3:-}"; CHK_LOC="${4:-}"
  [ -f "$CHK_TMP.body" ] || : > "$CHK_TMP.body"
  [ -f "$CHK_TMP.hdr" ] || : > "$CHK_TMP.hdr"
}

# _chk_code <path-or-url> <role> -- status only, following redirects. Cached
# per run, so a link that twenty pages share is fetched once.
_chk_code() {
  _k="$(printf '%s|%s' "$2" "$1")"
  _hit="$(awk -F '\t' -v k="$_k" '$1 == k { print $2; exit }' "$CHK_TMP.codes" 2>/dev/null)"
  if [ -n "$_hit" ]; then printf '%s' "$_hit"; return; fi
  _c_jar=""; _c_r="$(_api_role "$2")"
  [ -n "$_c_r" ] && [ -f "$TESTS_DIR/.auth/$_c_r.cookies" ] && _c_jar="$TESTS_DIR/.auth/$_c_r.cookies"
  case "$1" in http://*|https://*) _c_url="$1" ;; /*) _c_url="$base$1" ;; *) _c_url="$base/$1" ;; esac
  _c="$(curl -s -o /dev/null --max-time 20 -L --max-redirs 8 ${_c_jar:+-b "$_c_jar"} \
         -A 'Mozilla/5.0 (compatible; testwright)' -w '%{http_code}' "$_c_url" 2>/dev/null)"
  _c="${_c:-000}"
  printf '%s\t%s\n' "$_k" "$_c" >> "$CHK_TMP.codes"
  printf '%s' "$_c"
}

# _chk_hdr <name> -- the final response's header value, lowercased.
_chk_hdr() {
  tr -d '\r' < "$CHK_TMP.hdr" | awk -v n="$1" 'BEGIN { n = tolower(n) ":" }
    tolower($0) ~ /^http\// { v = "" }
    tolower(substr($0, 1, length(n))) == n { v = substr($0, length(n) + 1); sub(/^[ \t]+/, "", v); v = tolower(v) }
    END { print v }'
}

# _chk_hdr_all <name> -- every value of a repeated header in the final
# response, as sent (Set-Cookie), one per line.
_chk_hdr_all() {
  tr -d '\r' < "$CHK_TMP.hdr" | awk -v n="$1" 'BEGIN { n = tolower(n) ":" }
    tolower($0) ~ /^http\// { k = 0; delete V }
    tolower(substr($0, 1, length(n))) == n { v = substr($0, length(n) + 1); sub(/^[ \t]+/, "", v); V[++k] = v }
    END { for (i = 1; i <= k; i++) print V[i] }'
}

_chk_find() { printf '%s\n' "$*" >> "$CHK_TMP.find"; }

_chk_is_login() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *login*|*signin*|*sign-in*|*sign_in*|*/auth*|*oauth*|*sso*) return 0 ;;
  esac
  return 1
}

# The body, decoded if the server compressed it anyway.
_chk_body() {
  case "$(_chk_hdr content-encoding)" in
    gzip|deflate) gzip -dc < "$CHK_TMP.body" 2>/dev/null || cat "$CHK_TMP.body" ;;
    *) cat "$CHK_TMP.body" ;;
  esac
}

# ======================================================================= run

# _chk_run <family> <tag> [--only <ids>] -- the loop every family shares.
# Site cases (<PREFIX>-SITE-*) run last, so they can read what the page
# cases collected under $CHK_DIR.
_chk_run() {
  _fam="$1"; _tag="$2"; shift 2
  _only=""; [ "${1:-}" = "--only" ] && _only="${2:-}"
  need_csv
  assert_target_allowed
  have curl || die "$_fam: curl not found"
  base="$(json_get "$CREDS" base_url | sed 's#/*$##')"
  base_host="$(_seo_host "$base")"
  base_scheme="${base%%:*}"
  roles="$(json_keys "$CREDS" roles 2>/dev/null | tr '\n' ' ')"
  mkdir -p "$RESULTS" "$CACHE"
  out="$RESULTS/run-$(date +%Y%m%d-%H%M%S).csv"
  echo 'id,type,role,route,expected,actual,verdict,ms' > "$out"
  CHK_DIR="$CACHE/$_fam"
  [ -n "$_only" ] || rm -rf "$CHK_DIR"
  mkdir -p "$CHK_DIR"
  CHK_TMP="$CACHE/.$_fam.$$"
  : > "$CHK_TMP.codes"
  US="$(printf '\037')"
  [ "$(command -v "_${_fam}_init")" ] && "_${_fam}_init"

  _work="$CACHE/.$_fam-cases.$$"
  cmd_select --tag "$_tag" --cols id,type,route,tags,status,role --format csv 2>/dev/null |
    awk -v us="$US" -v only="$_only" "$AWKLIB"'NR > 1 { csvsplit($0, F)
      if (only != "" && !index("," only ",", "," F[1] ",")) next
      print F[1] us F[2] us F[3] us F[4] us F[5] us F[6] }' | sort -t "$US" -k1,1 > "$_work"
  { grep -v -- '-SITE-' "$_work"; grep -- '-SITE-' "$_work"; } > "$_work.o"; mv "$_work.o" "$_work"

  _t0=$(date +%s%N 2>/dev/null || echo 0)
  _tf_progress_init "$(grep -c . "$_work" 2>/dev/null || echo 0)"
  _skip=0; _unj=0
  while IFS="$US" read -r id typ route tags status who; do
    [ -n "${id:-}" ] || continue
    if [ "$(qa_status "$status")" = "Skipped" ]; then
      _skip=$((_skip + 1)); _tf_progress_tick SKIP "$_fam" "$id"; continue
    fi
    : > "$CHK_TMP.find"; CHK_VERDICT=""; CHK_NOTE=""; CHK_EXPECTED=""
    _c0=$(date +%s%N 2>/dev/null || echo 0)
    "_${_fam}_case" "$id" "${route:-/}" "${who:-nobody}" "$typ" "$tags"
    _c1=$(date +%s%N 2>/dev/null || echo 0)
    _ms=$(( (_c1 - _c0) / 1000000 )); [ "$_ms" -lt 0 ] && _ms=0

    if [ "$CHK_VERDICT" = SKIP ]; then
      _skip=$((_skip + 1)); _tf_progress_tick SKIP "$_fam" "$id"; continue
    fi
    [ -n "$CHK_VERDICT" ] || { [ -s "$CHK_TMP.find" ] && CHK_VERDICT=FAIL || CHK_VERDICT=PASS; }
    [ "$CHK_VERDICT" = UNJUDGED ] && _unj=$((_unj + 1))

    _ev="$TESTS_DIR/evidence/$id/$_fam.txt"
    if [ -s "$CHK_TMP.find" ]; then
      mkdir -p "$TESTS_DIR/evidence/$id"
      { echo "$id $route"; sed 's/^/- /' "$CHK_TMP.find"; } > "$_ev"
      _nf="$(grep -c . "$CHK_TMP.find")"
      _act="$(head -1 "$CHK_TMP.find")"
      [ "$_nf" -gt 1 ] && _act="$_act (and $((_nf - 1)) more in $_ev)"
    else
      rm -f "$_ev"; rmdir "$TESTS_DIR/evidence/$id" 2>/dev/null
      _act="${CHK_NOTE:-ok}"
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$id" "$_fam" "${who:-nobody}" "$(_api_nocomma "$route")" \
      "$(_api_nocomma "${CHK_EXPECTED:-no findings}")" "$(_api_nocomma "$_act" | cut -c1-200)" "$CHK_VERDICT" "$_ms" >> "$out"
    _tf_progress_tick "$CHK_VERDICT" "$_fam" "$id"
  done < "$_work"
  _tf_progress_done
  rm -f "$_work" "$CHK_TMP".*

  now="$(date +%Y-%m-%dT%H:%M:%S)"
  awk -F, -v now="$now" 'NR > 1 {
    st = ($7 == "PASS") ? " status=Pass" : \
         (($7 == "FAIL") ? " status=Fail" : \
         ((($7 == "ERROR") || ($7 == "UNJUDGED")) ? " status=Blocked" : ""))
    act = $6
    if (act != "" && act != "-") { gsub(/ /, "+", act); act = " actual=" act } else act = ""
    print $1 st act " last_result=" $7 " last_run=" now
  }' "$out" | cmd_setmany

  _t1=$(date +%s%N 2>/dev/null || echo 0)
  {
    echo "time=$(date +%H:%M:%S)"
    echo "duration_ms=$(( (_t1 - _t0) / 1000000 ))"
    echo "skipped=$_skip"
    echo "skip_reason=${CHK_SKIP_REASON:-behind a login with no session, or not a page}"
    echo "unjudged=$_unj"
  } > "${out%.csv}.meta"
  cmd_summary "$out"
}
