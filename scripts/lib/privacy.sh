# shellcheck shell=sh
# lib/privacy.sh -- privacy: personal data and secrets the app gives away
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Most privacy leaks are in what the server sends, so they are a curl request
# away: a key left in the page source, a card number in the HTML, a password
# field in a form that submits by GET (so the password lands in every server
# log), an API that returns `password_hash` because it serialises the whole
# row, a page only one user should see that a shared cache is allowed to keep.
#
# What happens in the browser -- trackers loading before anyone consented,
# tokens and personal data left in localStorage -- goes to the
# `privacy-auditor` agent: those cases are UNJUDGED `needs-browser`, listed in
# tests/.cache/privacy/browser.txt.
#
#   PRIV-NNN       one per page: secrets and card/ID numbers in the source,
#                  sensitive values in URLs, GET forms with a password, and
#                  a personal page a shared cache may store
#   PRIV-API-NNN   one per GET endpoint the suite requests: fields such as
#                  password_hash, secret or ssn in the response
#   PRIV-BR-NNN    one per page, `tags=privacy,browser`: trackers before
#                  consent, and what the page leaves in browser storage
#   PRIV-SITE-001  the home page links to a privacy policy that loads
#
# Evidence never contains the value it found -- only what kind it is, where,
# and a masked prefix. A leaked key pasted into tests/evidence/ has just moved.

cmd_privacy() {
  _p_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_p_sub" in
    cases) _privacy_cases "$@" ;;
    run)   _chk_run privacy privacy "$@" ;;
    *) die "privacy: expected 'cases <routes> [privileged]' or 'run [--only <ids>]'" ;;
  esac
}

_privacy_cases() {
  _chk_header
  _chk_row PRIV-SITE-001 "Privacy" "Visitors can find the privacy policy" "" nobody \
    "Open the home page | follow the link whose text mentions privacy" \
    "A privacy policy link exists on the home page and the page it opens returns 200" page / privacy
  _n=0
  _chk_pages "${1:-$CACHE/routes.txt}" "${2:-}" > "$CACHE/.priv-pages.$$"
  while IFS="$(printf '\t')" read -r _r _who; do
    _n=$((_n + 1))
    _chk_row "$(printf 'PRIV-%03d' "$_n")" "Privacy" "$_r gives away no secrets or personal data" \
      "Secrets, card and ID numbers, and sensitive URLs in $_r" "$_who" \
      "Request $_r | scan the source for keys, tokens, card and ID numbers | read its forms, links and Cache-Control" \
      "No key, token or card/ID number in the source; no password or token in a URL; no password form sent by GET; a personal page is Cache-Control private or no-store" \
      page "$_r" privacy
    _chk_row "$(printf 'PRIV-BR-%03d' "$_n")" "Privacy" "$_r tracks nobody before they agree, and leaves nothing sensitive in the browser" \
      "Third-party requests and browser storage on $_r" "$_who" \
      "Open $_r in a fresh browser | list requests to other sites before any consent | read cookie, localStorage and sessionStorage names" \
      "No tracker loads before consent; rejecting consent stops them; no token or personal data in localStorage or sessionStorage" \
      page "$_r" "privacy,browser"
  done < "$CACHE/.priv-pages.$$"
  rm -f "$CACHE/.priv-pages.$$"

  _p=0
  if [ -f "$CSV" ] && [ -f "$STATE" ]; then
    cmd_select --type api --cols route,role,method,tags --format csv 2>/dev/null |
      awk "$AWKLIB"'NR > 1 { csvsplit($0, F)
        m = toupper(F[3]); if (m != "" && m != "GET") next
        t = "," F[4] ","
        if (index(t, ",privacy,") || index(t, ",destructive,") || index(t, ",ends-session,")) next
        if (F[1] == "" || F[1] ~ /[:{<\[*]/ || F[1] ~ /(log|sign)[-_]?(out|off)/) next
        k = F[1] "\t" F[2]; if (k in S) next; S[k] = 1
        print F[1] "\t" (F[2] == "" ? "nobody" : F[2]) }' > "$CACHE/.priv-api.$$"
    while IFS="$(printf '\t')" read -r _r _who; do
      _p=$((_p + 1))
      _chk_row "$(printf 'PRIV-API-%03d' "$_p")" "Privacy" "GET $_r returns no field it should keep to itself" \
        "Over-exposed fields in GET $_r" "$_who" "GET $_r | read every field name in the JSON" \
        "No password, hash, secret, key, token (outside a sign-in endpoint), SSN or card field in the response" \
        api "$_r" privacy
    done < "$CACHE/.priv-api.$$"
    rm -f "$CACHE/.priv-api.$$"
  fi
  echo "privacy: $_n page case(s), $_n browser case(s), $_p endpoint case(s) + 1 site case" >&2
}

_privacy_init() {
  CHK_SKIP_REASON="behind a login with no session, or not a page"
  : > "$CHK_DIR/browser.txt"
}

_privacy_case() { # <id> <route> <role> <type> <tags>
  case ",$5," in
    *,browser,*)
      printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$CHK_DIR/browser.txt"
      CHK_VERDICT=UNJUDGED; CHK_EXPECTED="needs-browser: handed to privacy-auditor"; CHK_NOTE="-"; return ;;
  esac
  case "$1" in
    PRIV-SITE-001) _priv_policy ;;
    *) if [ "$4" = api ]; then _priv_api "$2" "$3"; else _priv_page "$2" "$3"; fi ;;
  esac
}

# _priv_mask <value> -- enough to find it again, not enough to use it.
_priv_mask() { printf '%s' "$1" | awk '{ n = length($0); printf "%s... (%d chars)", substr($0, 1, (n > 12 ? 4 : 2)), n }'; }

# _priv_scan <role> -- secrets and PII in the last fetched body. One line per
# kind, masked.
_priv_scan() {
  _chk_body | tr '\r\n' '  ' > "$CHK_TMP.flat"
  # Secrets with a recognisable shape.
  grep -oE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$CHK_TMP.flat" | head -1 | while read -r _v; do
    _chk_find "a private key block ($_v) is in the page source"; done
  for _pat in 'AKIA[0-9A-Z]{16}:an AWS access key id' '(sk|rk)_live_[0-9A-Za-z]{16,}:a live Stripe secret key' \
              'gh[pousr]_[A-Za-z0-9]{30,}:a GitHub token' 'xox[abprs]-[A-Za-z0-9-]{10,}:a Slack token' \
              'glpat-[A-Za-z0-9_-]{20,}:a GitLab token'; do
    _rx="${_pat%%:*}"; _what="${_pat#*:}"
    _v="$(grep -oE -- "$_rx" "$CHK_TMP.flat" | head -1)"
    [ -n "$_v" ] && _chk_find "$_what is in the page source: $(_priv_mask "$_v")"
  done
  # A named credential assigned a literal: api_key = "...", "client_secret": "...".
  _v="$(grep -oiE -- '["'"'"']?(api[_-]?key|secret[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|private[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_./+=-]{16,}["'"'"']' "$CHK_TMP.flat" | head -1)"
  if [ -n "$_v" ]; then
    _name="$(printf '%s' "$_v" | sed -E 's/^["'"'"']?([A-Za-z_-]+).*/\1/')"
    _val="$(printf '%s' "$_v" | sed -E 's/.*[:=][[:space:]]*["'"'"']([^"'"'"']*)["'"'"']$/\1/')"
    _chk_find "$_name is assigned a literal in the page source: $(_priv_mask "$_val")"
  fi
  # A filled-in password field.
  grep -qiE '<input[^>]*type=["'"'"']?password[^>]*value=["'"'"'][^"'"'"']+' "$CHK_TMP.flat" &&
    _chk_find "a password field is pre-filled with a value in the HTML"
  # A signed token in a page anyone can load.
  if [ "$1" = nobody ]; then
    _v="$(grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' "$CHK_TMP.flat" | head -1)"
    [ -n "$_v" ] && _chk_find "a signed token (JWT) is embedded in a page served without a session: $(_priv_mask "$_v")"
  fi
  # Card numbers: 13-19 digits, spaces or dashes allowed, passing the Luhn check.
  grep -oE '(^|[^0-9])[0-9]([ -]?[0-9]){12,18}([^0-9]|$)' "$CHK_TMP.flat" | tr -cd '0-9\n' |
    awk 'length($0) >= 13 && length($0) <= 19 && $0 !~ /^(.)\1+$/ {
      s = 0; alt = 0
      for (i = length($0); i >= 1; i--) { d = substr($0, i, 1) + 0; if (alt) { d *= 2; if (d > 9) d -= 9 } s += d; alt = !alt }
      if (s % 10 == 0 && $0 ~ /^[3456]/) { print; exit } }' > "$CHK_TMP.card"
  [ -s "$CHK_TMP.card" ] && _chk_find "a number that passes the card checksum is in the page: $(_priv_mask "$(cat "$CHK_TMP.card")")"
  # US social security numbers (ddd-dd-dddd, not 000/666/9xx).
  _v="$(grep -oE '(^|[^0-9-])[0-8][0-9]{2}-[0-9]{2}-[0-9]{4}([^0-9-]|$)' "$CHK_TMP.flat" | grep -vE '(^|[^0-9])(000|666)-' | head -1 | tr -cd '0-9-')"
  [ -n "$_v" ] && _chk_find "a US social security number pattern is in the page: $(_priv_mask "$_v")"
  # An email address left in an HTML comment.
  grep -oE '<!--([^-]|-[^-])*-->' "$CHK_TMP.flat" | grep -qE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' &&
    _chk_find "an HTML comment contains an email address"
  return 0
}

# PRIV-NNN
_priv_page() {
  _chk_get "$1" "$2" --follow
  case "$CHK_CODE" in 000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;; esac
  if [ "$CHK_HOPS" -gt 0 ] && _chk_is_login "$CHK_URL"; then CHK_VERDICT=SKIP; return; fi
  case "$(_chk_hdr content-type)" in ''|*html*) ;; *) CHK_VERDICT=SKIP; return ;; esac
  _priv_scan "$2"

  # Sensitive values in a URL end up in server logs, proxies, history and the
  # Referer header sent to every third party the page loads.
  _chk_body | tr '\r\n' '  ' | grep -oiE 'href=["'"'"']?[^"'"'"' >]*[?&](password|passwd|pwd|token|access_token|auth|api_key|apikey|secret|session|sessionid|sid|ssn|email)=[^"'"'"' >&]+' |
    sed -E 's/.*[?&]([A-Za-z_]+)=.*/\1/' | sort -u | while read -r _q; do
      _chk_find "a link puts $_q= in the URL, where server logs, history and Referer headers keep it"; done
  # A form carrying a password must not submit by GET.
  _chk_body | tr '\r\n' '  ' | awk '{ ls = tolower($0)
      while ((p = index(ls, "<form")) > 0) {
        ls = substr(ls, p + 5); e = index(ls, "</form"); f = (e ? substr(ls, 1, e) : ls)
        head = substr(f, 1, index(f, ">"))
        if (head !~ /method[ \t]*=[ \t]*["'"'"']?post/ && f ~ /type[ \t]*=[ \t]*["'"'"']?password/) { print "x"; exit } } }' | grep -q x &&
    _chk_find "a form with a password field submits by GET, so the password goes into the URL"
  # A page only a signed-in user sees must not sit in a shared cache.
  case "$2" in
    ''|nobody|anonymous) ;;
    *) _cc="$(_chk_hdr cache-control)"
       case "$_cc" in *no-store*|*private*) ;;
         *) _chk_find "a page shown only to $2 has Cache-Control '${_cc:-none}'; a shared cache may keep it and hand it to someone else" ;; esac ;;
  esac
  CHK_NOTE="source, links, forms and caching checked"
  return 0
}

# PRIV-API-NNN -- the field names of a JSON response, never their values.
_priv_api() {
  _r="$(_api_role "$2")"
  if [ -n "$_r" ] && [ ! -f "$TESTS_DIR/.auth/$_r.cookies" ]; then
    CHK_VERDICT=UNJUDGED; CHK_EXPECTED="no session for $_r: run /testwright:setup"; CHK_NOTE="-"; return
  fi
  _chk_get "$1" "$2" -H 'Accept: application/json'
  case "$CHK_CODE" in
    000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;;
    401|403) CHK_VERDICT=UNJUDGED; CHK_EXPECTED="refused (HTTP $CHK_CODE): nothing to read"; CHK_NOTE="-"; return ;;
  esac
  _auth=0
  printf '%s' "$1" | grep -qiE '(log|sign)[-_]?in|/token|/oauth|/auth|/session' && _auth=1
  _chk_body | grep -oiE '"(password|passwd|pwd|password_?hash|hashed_?password|pass_?hash|salt|secret|client_?secret|api_?key|private_?key|ssn|social_?security(_number)?|card_?number|cc_?number|cvv|cvc|pin_?code|otp_?secret|totp_?secret|mfa_?secret|reset_?token|refresh_?token|session_?token|access_?token)"[[:space:]]*:' |
    tr -d '": \t' | tr 'A-Z' 'a-z' | sort | uniq -c | while read -r _cnt _k; do
      case "$_k" in
        refresh_token|refreshtoken|access_token|accesstoken|session_token|sessiontoken) [ "$_auth" = 1 ] && continue ;;
      esac
      _chk_find "the response exposes a '$_k' field ($_cnt occurrence(s)); serialise only what the client needs"
    done
  _priv_scan "$2"
  CHK_NOTE="HTTP $CHK_CODE; field names checked"
  return 0
}

# PRIV-SITE-001
_priv_policy() {
  _chk_get / nobody --follow
  case "$CHK_CODE" in 000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;; esac
  _href="$(_chk_body | tr '\r\n' '  ' | grep -oiE '<a[^>]*href=["'"'"']?[^"'"'"' >]+[^>]*>[^<]*(privacy|datenschutz|confidentialit|privacidad)[^<]*</a>|<a[^>]*href=["'"'"']?[^"'"'"' >]*privacy[^"'"'"' >]*' |
           head -1 | sed -E 's/.*href=["'"'"']?([^"'"'"' >]+).*/\1/')"
  if [ -z "$_href" ]; then
    _chk_find "the home page has no link to a privacy policy"; return 0
  fi
  case "$_href" in
    http://*|https://*) _h="$(_seo_host "$_href")"
      if [ "$_h" != "$base_host" ]; then CHK_NOTE="links to a privacy policy on $_h (not fetched)"; return 0; fi
      _href="$(_seo_path "$_href")" ;;
  esac
  _c="$(_chk_code "$_href" nobody)"
  case "$_c" in 2*) CHK_NOTE="privacy policy at $_href" ;; *) _chk_find "the privacy policy link $_href returns HTTP $_c" ;; esac
  return 0
}
