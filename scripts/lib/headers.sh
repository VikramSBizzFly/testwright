# shellcheck shell=sh
# lib/headers.sh -- headers: the security a response header carries, over curl
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Half of a web app's defence against injected script, clickjacking and
# downgrade attacks is a handful of response headers, and every one of them
# is visible to curl. So is a CORS policy that hands any site a logged-in
# user's data, a server banner naming the exact version to look up, and a
# session cookie JavaScript can read. None of this needs a browser or a token.
#
#   HDR-NNN       one per page: CSP (and whether it allows inline script),
#                 clickjacking protection, nosniff, a weak Referrer-Policy,
#                 HSTS when served over https
#   HDR-SITE-001  CORS: an arbitrary Origin is not trusted with credentials
#   HDR-SITE-002  no version banners; error pages show no stack trace
#   HDR-SITE-003  session cookies are HttpOnly, SameSite, and Secure on https
#   HDR-SITE-004  plain http redirects to https (skipped on an http target)
#
# A check a project has decided against goes in framework.json as
# "headers": { "skip": ["csp-inline", "referrer"] }. The names are the ones in
# each finding's brackets.

cmd_headers() {
  _h_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_h_sub" in
    cases) _headers_cases "$@" ;;
    run)   _chk_run headers headers "$@" ;;
    *) die "headers: expected 'cases <routes> [privileged]' or 'run [--only <ids>]'" ;;
  esac
}

_headers_cases() {
  _chk_header
  _chk_row HDR-SITE-001 "Security headers" "No other site can read a user's data through CORS" "" nobody \
    "Request the home page and an API route with Origin: https://tf-cors-probe.example and Origin: null" \
    "Neither origin is echoed back together with Access-Control-Allow-Credentials: true" page / headers
  _chk_row HDR-SITE-002 "Security headers" "The server does not name its software version" "" nobody \
    "Read the Server and X-Powered-By headers of a page and of a missing page | read the missing page's body" \
    "No version number in a banner; no stack trace or debug page" page / headers
  _chk_row HDR-SITE-003 "Security headers" "Session cookies cannot be read by script or sent cross-site" "" nobody \
    "Read the Set-Cookie attributes captured at login (tf.sh login) and on the home page" \
    "Every session cookie is HttpOnly and has SameSite; Secure when the site is https" page / headers
  _chk_row HDR-SITE-004 "Security headers" "Plain http always moves to https" "" nobody \
    "Request the site over http://" "A redirect to the https:// URL (skipped when the target itself is http)" page / headers
  _n=0
  _chk_pages "${1:-$CACHE/routes.txt}" "${2:-}" > "$CACHE/.hdr-pages.$$"
  while IFS="$(printf '\t')" read -r _r _who; do
    _n=$((_n + 1))
    _chk_row "$(printf 'HDR-%03d' "$_n")" "Security headers" "$_r sends the headers that stop injected script and framing" \
      "Security response headers of $_r" "$_who" "Request $_r and read its response headers" \
      "Content-Security-Policy without unsafe-inline script; X-Frame-Options or frame-ancestors; X-Content-Type-Options: nosniff; no weak Referrer-Policy; HSTS on https" \
      page "$_r" headers
  done < "$CACHE/.hdr-pages.$$"
  rm -f "$CACHE/.hdr-pages.$$"
  echo "headers: $_n page case(s) + 4 site case(s)" >&2
}

_headers_init() {
  HDR_SKIP=" $(_chk_list headers skip | tr '\n' ' ') "
}

_hdr_on() { case "$HDR_SKIP" in *" $1 "*) return 1 ;; esac; return 0; }

_headers_case() {
  case "$1" in
    HDR-SITE-001) _hdr_cors ;;
    HDR-SITE-002) _hdr_banner ;;
    HDR-SITE-003) _hdr_cookies ;;
    HDR-SITE-004) _hdr_https ;;
    *) _hdr_page "$2" "$3" ;;
  esac
}

_hdr_page() {
  _chk_get "$1" "$2" --follow
  case "$CHK_CODE" in 000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;; esac
  if [ "$CHK_HOPS" -gt 0 ] && _chk_is_login "$CHK_URL"; then CHK_VERDICT=SKIP; return; fi
  _csp="$(_chk_hdr content-security-policy)"
  _xfo="$(_chk_hdr x-frame-options)"
  if _hdr_on csp && [ -z "$_csp" ]; then
    _chk_find "[csp] no Content-Security-Policy; an injected <script> runs with the page's full rights"
  fi
  if _hdr_on csp-inline && [ -n "$_csp" ]; then
    # The directive that governs <script>: script-src, else default-src.
    _ss="$(printf '%s' "$_csp" | tr ';' '\n' | awk '{ sub(/^[ \t]+/, "") } $1 == "script-src" { print; f = 1; exit }
                                                  $1 == "default-src" { d = $0 } END { if (!f && d != "") print d }')"
    case "$_ss" in
      *"'unsafe-inline'"*)
        case "$_ss" in *"'nonce-"*|*"'sha256-"*|*"'sha384-"*|*"'sha512-"*|*"'strict-dynamic'"*) ;;
          *) _chk_find "[csp-inline] the CSP allows 'unsafe-inline' script, so it does not stop an injected <script>" ;; esac ;;
    esac
    [ -z "$_ss" ] && _chk_find "[csp-inline] the CSP sets neither script-src nor default-src, so scripts are unrestricted"
  fi
  if _hdr_on frame; then
    case "$_xfo" in
      deny|sameorigin) ;;
      *) case "$_csp" in *frame-ancestors*) ;;
           *) _chk_find "[frame] neither X-Frame-Options nor CSP frame-ancestors; any site can frame this page (clickjacking)" ;; esac ;;
    esac
  fi
  if _hdr_on nosniff && [ "$(_chk_hdr x-content-type-options)" != nosniff ]; then
    _chk_find "[nosniff] no X-Content-Type-Options: nosniff; a browser may run an upload as script"
  fi
  if _hdr_on referrer; then
    case "$(_chk_hdr referrer-policy)" in
      *unsafe-url*|*no-referrer-when-downgrade*) _chk_find "[referrer] Referrer-Policy $(_chk_hdr referrer-policy) sends full URLs, query strings included, to other sites" ;;
    esac
  fi
  case "$CHK_URL" in
    https://*)
      if _hdr_on hsts; then
        _hsts="$(_chk_hdr strict-transport-security)"
        _age="$(printf '%s' "$_hsts" | sed -n 's/.*max-age=\([0-9]*\).*/\1/p')"
        if [ -z "$_hsts" ]; then _chk_find "[hsts] no Strict-Transport-Security; the first visit can be downgraded to http"
        elif [ "${_age:-0}" -lt 15552000 ]; then _chk_find "[hsts] HSTS max-age is ${_age:-0}s; use at least 15552000 (180 days)"
        fi
      fi ;;
  esac
  CHK_NOTE="headers present"
  return 0
}

# HDR-SITE-001 -- a CORS policy that trusts any origin with credentials lets
# any website read a logged-in user's responses.
_hdr_cors() {
  _targets="/"
  # Up to ten GET endpoints the suite already requests: CORS is usually set
  # per route or per router, so one endpoint is not a sample of the rest.
  _api="$(cmd_select --type api --cols route,method --format plain 2>/dev/null |
          awk -F '\t' '($2 == "" || toupper($2) == "GET") && $1 !~ /[{:<\[*]/ && $1 !~ /(log|sign)[-_]?(out|off)/ && !S[$1]++ { print $1; if (++n == 10) exit }')"
  [ -n "$_api" ] && _targets="$_targets $(echo $_api)"
  _first="$(printf '%s' "$roles" | awk '{ print $1 }')"
  for _t in $_targets; do
    for _o in https://tf-cors-probe.example null; do
      _chk_get "$_t" "${_first:-nobody}" -H "Origin: $_o"
      [ "$CHK_CODE" = 000 ] && { CHK_VERDICT=ERROR; CHK_NOTE="no response"; return; }
      _acao="$(_chk_hdr access-control-allow-origin)"; _acac="$(_chk_hdr access-control-allow-credentials)"
      if [ "$_acac" = true ]; then
        case "$_acao" in
          "$_o") _chk_find "$_t trusts Origin: $_o with credentials; any site can read a logged-in user's responses" ;;
          '*')   _chk_find "$_t sends Access-Control-Allow-Origin: * with credentials (browsers refuse it; the intent is unsafe)" ;;
        esac
      fi
    done
  done
  CHK_NOTE="checked: $(echo $_targets)"
  return 0
}

# HDR-SITE-002 -- version banners and debug pages.
_hdr_banner() {
  for _t in / "/tf-hdr-probe-$$-missing"; do
    _chk_get "$_t" nobody
    [ "$CHK_CODE" = 000 ] && { CHK_VERDICT=ERROR; CHK_NOTE="no response"; return; }
    _srv="$(_chk_hdr server)"
    printf '%s' "$_srv" | grep -qE '[0-9]+\.[0-9]+' &&
      _chk_find "Server: $_srv names an exact version to look up in a CVE list"
    for _h in x-powered-by x-aspnet-version x-aspnetmvc-version x-generator; do
      _v="$(_chk_hdr "$_h")"; [ -n "$_v" ] && _chk_find "$_h: $_v advertises the stack"
    done
    if [ "$_t" != / ] && _chk_body | grep -qE 'Traceback \(most recent call last\)|Werkzeug Debugger|Whoops, looks like|Exception in thread|at [a-z]+\.[a-zA-Z.]+\([A-Za-z]+\.java:[0-9]+\)|Stack trace:|DEBUG = True|RoutingError|ActionController::|django\.core|Symfony\\Component'; then
      _chk_find "the missing-page response shows a stack trace or debug page"
    fi
  done
  sort -u "$CHK_TMP.find" -o "$CHK_TMP.find"
  return 0
}

# HDR-SITE-003 -- session cookie attributes. `tf.sh login` keeps the
# attributes (never the values) of every cookie the login set.
_hdr_cookies() {
  : > "$CHK_TMP.ck"
  for _f in "$TESTS_DIR"/.auth/*.setcookie; do [ -f "$_f" ] && cat "$_f" >> "$CHK_TMP.ck"; done
  _chk_get / nobody
  _chk_hdr_all set-cookie | sed 's/=[^;]*//' >> "$CHK_TMP.ck"
  if [ ! -s "$CHK_TMP.ck" ]; then
    if ls "$TESTS_DIR"/.auth/*.cookies >/dev/null 2>&1; then
      CHK_VERDICT=UNJUDGED; CHK_EXPECTED="log in again (tf.sh login <role>) so the cookie attributes are captured"
    else
      CHK_NOTE="the app sets no cookies"
    fi
    return 0
  fi
  sort -u "$CHK_TMP.ck" | while IFS= read -r _c; do
    _name="$(printf '%s' "$_c" | awk -F';' '{ gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1 }')"
    _lc="$(printf '%s' "$_c" | tr 'A-Z' 'a-z')"
    # A CSRF cookie is meant to be read by the page's script.
    case "$(printf '%s' "$_name" | tr 'A-Z' 'a-z')" in *csrf*|*xsrf*) _csrf=1 ;; *) _csrf=0 ;; esac
    case "$_lc" in *httponly*) ;; *) [ "$_csrf" = 1 ] || _chk_find "cookie $_name is not HttpOnly; any injected script can read it" ;; esac
    case "$_lc" in *samesite=none*) case "$_lc" in *secure*) ;; *) _chk_find "cookie $_name is SameSite=None without Secure; browsers drop it" ;; esac ;;
                   *samesite*) ;; *) _chk_find "cookie $_name has no SameSite attribute; set Lax or Strict against cross-site requests" ;; esac
    if [ "$base_scheme" = https ]; then
      case "$_lc" in *secure*) ;; *) _chk_find "cookie $_name is not Secure; it is sent over plain http" ;; esac
    fi
  done
  CHK_NOTE="$(sort -u "$CHK_TMP.ck" | grep -c .) cookie(s) checked"
  return 0
}

# HDR-SITE-004 -- http moves to https.
_hdr_https() {
  if [ "$base_scheme" != https ]; then
    CHK_VERDICT=SKIP; return
  fi
  _chk_get "http://${base#https://}/" nobody
  case "$CHK_CODE" in
    000) CHK_VERDICT=ERROR; CHK_NOTE="plain http did not answer" ;;
    30[1278]) case "$CHK_LOC" in https://*) ;; *) _chk_find "http redirects to $CHK_LOC, not to https" ;; esac ;;
    *) _chk_find "http answers HTTP $CHK_CODE instead of redirecting to https" ;;
  esac
  return 0
}
