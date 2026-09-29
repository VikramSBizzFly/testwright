# shellcheck shell=sh
# lib/links.sh -- links: every link a page offers leads somewhere, over curl
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# A broken link is the cheapest bug to find and one of the most visible to a
# user. Each page's anchors are read from the HTML the server sends and every
# same-site target is requested once per run (a link twenty pages share is
# fetched once). Off-site links are counted, never fetched -- the production
# guard applies to them as much as to anything else.
#
# A link is never followed if following it could change something: sign-out,
# delete, remove, cancel, unsubscribe and the like are listed in the evidence
# as not checked. A GET that logs the run's own session out would turn every
# later case into a logged-out case.
#
#   LINK-NNN       one per page: every same-site link returns 2xx (after
#                  redirects, without a loop), every #anchor on the page
#                  exists, and an https page loads nothing over http
#   LINK-SITE-001  a crawl from / (links.max_pages, default 50) for broken
#                  links on pages the route list never named

cmd_links() {
  _l_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_l_sub" in
    cases) _links_cases "$@" ;;
    run)   _chk_run links links "$@" ;;
    *) die "links: expected 'cases <routes> [privileged]' or 'run [--only <ids>]'" ;;
  esac
}

_links_cases() {
  _chk_header
  _chk_row LINK-SITE-001 "Links" "No page reachable from the home page links to a missing page" \
    "A crawl of same-site links from /, for pages the route list does not name" nobody \
    "Follow same-site links from / up to links.max_pages pages | request every link found" \
    "Every same-site link returns 2xx; no redirect loops" page / links
  _n=0
  _chk_pages "${1:-$CACHE/routes.txt}" "${2:-}" > "$CACHE/.link-pages.$$"
  while IFS="$(printf '\t')" read -r _r _who; do
    _n=$((_n + 1))
    _chk_row "$(printf 'LINK-%03d' "$_n")" "Links" "Every link on $_r leads somewhere" \
      "Links, anchors and mixed content on $_r" "$_who" \
      "Open $_r | request every same-site link on it | look for each #anchor on the page" \
      "Every same-site link returns 2xx without a redirect loop; every #anchor exists; nothing loads over http on an https page" \
      page "$_r" links
  done < "$CACHE/.link-pages.$$"
  rm -f "$CACHE/.link-pages.$$"
  echo "links: $_n page case(s) + 1 site case" >&2
}

_links_init() {
  LINK_MAX_PAGES="$(_chk_num links.max_pages 50)"
  LINK_MAX_PER_PAGE="$(_chk_num links.max_per_page 200)"
  : > "$CHK_DIR/seen.txt"
}

_links_case() {
  case "$1" in
    LINK-SITE-001) _links_crawl ;;
    *) _links_page "$2" "$3" ;;
  esac
}

# The page's links, one per line as `kind<TAB>value`:
#   int <path>    same site, fragment removed
#   frag <id>     an anchor on this same page
#   ext <url>     another site -- counted, never fetched
#   risky <path>  a same-site link whose GET might change state
#   mixed <url>   an http:// resource on an https page
_links_extract() { # <route> -- reads the last fetched body
  _chk_body | tr '\r\n' '  ' |
    grep -oiE '<(a|area)[^>]*[[:space:]]href=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)|<(script|img|iframe|source)[^>]*[[:space:]]src=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)|<link[^>]*[[:space:]]href=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)' |
    awk -v route="$1" -v host="$base_host" -v scheme="$base_scheme" '
      { tag = tolower(substr($0, 2, index($0 " ", " ") - 2))
        match($0, /[[:space:]](href|src)=/); u = substr($0, RSTART + RLENGTH)
        gsub(/^["'"'"']|["'"'"'].*$/, "", u); gsub(/&amp;/, "\\&", u) }
      tag != "a" && tag != "area" {
        if (scheme == "https" && u ~ /^http:\/\//) print "mixed\t" u
        next }
      u == "" || u ~ /^(mailto|tel|javascript|data|sms|ftp):/ { next }
      u ~ /^#/ { f = substr(u, 2); if (f != "" && f != "top") print "frag\t" f; next }
      { if (u ~ /^(https?:)?\/\//) { h = u; sub(/^(https?:)?\/\//, "", h); p = h; sub(/[\/?#].*$/, "", h); sub(/:.*$/, "", h)
          if (tolower(h) != host) { print "ext\t" u; next }
          sub(/^[^\/?#]*/, "", p); u = (p == "" ? "/" : p) }
        else if (u !~ /^\//) { d = route; sub(/[^\/]*$/, "", d); u = d u }
        fr = ""; if (index(u, "#")) { fr = substr(u, index(u, "#") + 1); u = substr(u, 1, index(u, "#") - 1) }
        if (u == route && fr != "") { print "frag\t" fr; next }
        if (u == "") next
        lu = tolower(u)
        if (lu ~ /(log|sign)[-_]?(out|off)|delete|destroy|remove|unsubscribe|cancel|revoke|deactivate|\/reset/) { print "risky\t" u; next }
        print "int\t" u }' | sort -u
}

# LINK-NNN
_links_page() {
  _chk_get "$1" "$2" --follow
  case "$CHK_CODE" in 000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;; esac
  if [ "$CHK_HOPS" -gt 0 ] && _chk_is_login "$CHK_URL"; then CHK_VERDICT=SKIP; return; fi
  case "$CHK_CODE" in 2*) ;; *) _chk_find "the page itself returns HTTP $CHK_CODE"; return 0 ;; esac
  case "$(_chk_hdr content-type)" in ''|*html*) ;; *) CHK_VERDICT=SKIP; return ;; esac
  _links_judge "$1" "$2"
  printf '%s\n' "$1" >> "$CHK_DIR/seen.txt"
}

# _links_judge <route> <role> -- judge the links in the last fetched page.
_links_judge() {
  _body_ids="$(_chk_body | grep -oiE '[[:space:]](id|name)=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)' |
               awk '{ sub(/^[ \t]*[^=]*=/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print }')"
  _links_extract "$1" > "$CHK_TMP.links"
  _ni=0; _ne=0; _nr=0
  while IFS="$(printf '\t')" read -r _k _v; do
    case "$_k" in
      int)
        _ni=$((_ni + 1)); [ "$_ni" -gt "$LINK_MAX_PER_PAGE" ] && continue
        _c="$(_chk_code "$_v" "$2")"
        case "$_c" in
          2*) ;;
          000) _chk_find "links to $_v, which does not answer" ;;
          30*) _chk_find "links to $_v, which redirects in a loop or more than 8 times" ;;
          *) _chk_find "links to $_v, which returns HTTP $_c" ;;
        esac ;;
      frag)
        printf '%s\n' "$_body_ids" | grep -qxF -- "$_v" ||
          _chk_find "links to #$_v, but no element on the page has that id" ;;
      mixed) _chk_find "loads $_v over plain http on an https page (blocked or flagged by browsers)" ;;
      ext) _ne=$((_ne + 1)) ;;
      risky) _nr=$((_nr + 1)); printf '%s\n' "$_v" >> "$CHK_TMP.risky" ;;
    esac
  done < "$CHK_TMP.links"
  if [ "$_ni" -gt "$LINK_MAX_PER_PAGE" ]; then
    _chk_find "the page has $_ni same-site links; only the first $LINK_MAX_PER_PAGE were checked (links.max_per_page)"
  fi
  CHK_NOTE="$_ni same-site link(s) checked; $_ne off-site not fetched; $_nr not followed (could change state)"
  return 0
}

# LINK-SITE-001 -- breadth-first from /, over pages the page cases did not
# already judge, as a logged-out visitor.
_links_crawl() {
  printf '/\n' > "$CHK_TMP.queue"; : > "$CHK_TMP.done"; _pages=0; _new=0
  while [ -s "$CHK_TMP.queue" ] && [ "$_pages" -lt "$LINK_MAX_PAGES" ]; do
    _p="$(head -1 "$CHK_TMP.queue")"
    tail -n +2 "$CHK_TMP.queue" > "$CHK_TMP.q2"; mv "$CHK_TMP.q2" "$CHK_TMP.queue"
    grep -qxF -- "$_p" "$CHK_TMP.done" && continue
    printf '%s\n' "$_p" >> "$CHK_TMP.done"
    _chk_get "$_p" nobody --follow
    case "$CHK_CODE" in 2*) ;; *) continue ;; esac
    case "$(_chk_hdr content-type)" in ''|*html*) ;; *) continue ;; esac
    [ "$CHK_HOPS" -gt 0 ] && _chk_is_login "$CHK_URL" && continue
    _pages=$((_pages + 1))
    _links_extract "$_p" > "$CHK_TMP.links"
    # Queue what this page links to.
    awk -F '\t' '$1 == "int" { print $2 }' "$CHK_TMP.links" | sed 's/?.*$//' >> "$CHK_TMP.queue"
    # Judge only pages no page case covers; their links were judged already.
    grep -qxF -- "$_p" "$CHK_DIR/seen.txt" && continue
    _new=$((_new + 1))
    : > "$CHK_TMP.pf"
    mv "$CHK_TMP.find" "$CHK_TMP.keep"; : > "$CHK_TMP.find"
    _links_judge "$_p" nobody
    sed "s#^#on $_p: #" "$CHK_TMP.find" >> "$CHK_TMP.keep"; mv "$CHK_TMP.keep" "$CHK_TMP.find"
  done
  CHK_NOTE="crawled $_pages page(s); $_new not covered by a page case"
  [ "$_pages" -ge "$LINK_MAX_PAGES" ] && CHK_NOTE="$CHK_NOTE (stopped at links.max_pages)"
  return 0
}
