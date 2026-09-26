# shellcheck shell=sh
# lib/seo.sh -- seo: what a search crawler sees, over curl
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# A crawler reads the HTML the server sends, before any JavaScript runs, so
# almost every SEO signal is a curl request away and costs no tokens: the head
# tags, the status code, robots.txt, the sitemap. Two things are not, and those
# go to the `seo-auditor` agent instead of being guessed at here:
#
#   - a page the server sends as an empty shell for JavaScript to fill in. Its
#     raw HTML has no h1 and no description, and failing it for that would be
#     reporting the framework, not the page. It is UNJUDGED `needs-render`.
#   - anything that needs judgement: a title that says "Home" on every page,
#     structured data that parses but describes the wrong thing.
#
# Every case is `type=page`, `tags=seo`, and logged out -- a crawler has no
# session. The ids are fixed so the run knows which check each one is:
#
#   SEO-SITE-001  robots.txt       SEO-SITE-003  unknown paths return 404
#   SEO-SITE-002  the sitemap      SEO-SITE-004  no two pages share a title
#   SEO-NNN       one per public page

cmd_seo() {
  _seo_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_seo_sub" in
    cases) _seo_cases "$@" ;;
    run)   _seo_run "$@" ;;
    *) die "seo: expected 'cases <routes> [privileged]' or 'run'" ;;
  esac
}

# ===================================================================== cases

# seo cases [routes_file] [privileged_file] -- case rows for `merge`.
#
# Only pages a crawler could reach: no API routes, no parameterised routes (a
# made-up id proves nothing about the real page's head), and nothing behind a
# guard. A page that turns out to need a login at run time is skipped then.
_seo_cases() {
  routes_file="${1:-$CACHE/routes.txt}"; priv_file="${2:-}"
  [ -f "$routes_file" ] || die "seo cases: no route list at $routes_file"
  if [ -n "$priv_file" ] && [ -f "$priv_file" ]; then
    priv="$(cat "$priv_file")"
  else
    priv="$(grep -iE '/(admin|settings|manage|internal|config|users|roles|permissions|billing|audit|reports?|payroll|employees|dashboard|account)' "$routes_file" || true)"
  fi

  printf '%s,type,route,tags,role\n' "$HEADER"
  _seo_site_case 1 /robots.txt "robots.txt lets crawlers in and names the sitemap" \
    "Fetch /robots.txt" "Returns 200 as plain text; does not block the whole site for every crawler; has a Sitemap: line"
  _seo_site_case 2 /sitemap.xml "The sitemap lists every public page and only live ones" \
    "Fetch the sitemap named in robots.txt (or /sitemap.xml) and every URL in it" \
    "Parses; every URL returns 200 and is indexable; every public page is listed"
  _seo_site_case 3 /tf-seo-probe-missing "A page that does not exist says so" \
    "Fetch a path that cannot exist" "Returns 404 (a 200 or a redirect is a soft 404)"
  _seo_site_case 4 / "No two pages share a title or a description" \
    "Compare the title and meta description of every public page" \
    "Each title and each description is unique"

  n=0
  while IFS= read -r route; do
    route="$(printf '%s' "$route" | tr -d '\r')"
    case "$route" in
      ''|*/api/*|/api/*|*:*|*'['*|*'<'*|*'{'*|*'*'*) continue ;;
    esac
    printf '%s\n' "$priv" | grep -qxF -- "$route" && continue
    n=$((n + 1))
    printf 'SEO-%03d,SEO,%s,%s,Not logged in,%s,,%s,,Not Run,page,%s,seo,nobody\n' \
      "$n" \
      "$(csv_esc "Search engines can index $route")" \
      "$(csv_esc "What a crawler sees on $route before any JavaScript runs")" \
      "$(csv_esc "Fetch $route without a session and read its head")" \
      "$(csv_esc "200; title 10-60 chars; description 50-160 chars; one h1; absolute canonical that resolves; html lang; viewport; og:title/description/image; not noindex; hreflang alternates resolve; every image has alt")" \
      "$route"
  done < "$routes_file"
  echo "seo: $n page case(s) + 4 site case(s)" >&2
}

_seo_site_case() { # <n> <route> <scenario> <steps> <expected>
  printf 'SEO-SITE-%03d,SEO,%s,,Not logged in,%s,,%s,,Not Run,page,%s,seo,nobody\n' \
    "$1" "$(csv_esc "$3")" "$(csv_esc "$4")" "$(csv_esc "$5")" "$2"
}

# ======================================================================= run

# seo run -- run every `tags=seo` case. Page cases first: the site cases read
# what the page cases found (which pages are public, their titles).
_seo_run() {
  need_csv
  assert_target_allowed
  have curl || die "seo: curl not found"
  base="$(json_get "$CREDS" base_url | sed 's#/*$##')"
  base_host="$(_seo_host "$base")"
  mkdir -p "$RESULTS" "$CACHE"
  ts="$(date +%Y%m%d-%H%M%S)"
  out="$RESULTS/run-$ts.csv"
  echo 'id,type,role,route,expected,actual,verdict,ms' > "$out"

  SEO_DIR="$CACHE/seo"
  rm -rf "$SEO_DIR"; mkdir -p "$SEO_DIR/jsonld"
  : > "$SEO_DIR/render.txt"
  printf 'id\troute\ttitle\tdescription\th1\tsource\n' > "$SEO_DIR/heads.tsv"
  : > "$SEO_DIR/public.txt"
  SEO_TMP="$CACHE/.seo.$$"
  SEO_CANON_HOST=""

  max_urls="$(json_get "$FRAMEWORK" seo.max_sitemap_urls 2>/dev/null || true)"
  case "$max_urls" in ''|*[!0-9]*) max_urls=200 ;; esac
  noindex_allow="$(_seo_json_list "$FRAMEWORK" noindex_allow)"

  US="$(printf '\037')"
  work="$CACHE/.seo-cases.$$"
  cmd_select --tag seo --cols id,route,status --format csv 2>/dev/null |
    awk -v us="$US" "$AWKLIB"'NR > 1 { csvsplit($0, F); print F[1] us F[2] us F[3] }' |
    sort -t "$US" -k1,1 > "$work"
  # Page cases before site cases, whatever order the store keeps them in.
  { grep -v '^SEO-SITE-' "$work"; grep '^SEO-SITE-' "$work"; } > "$work.o"
  mv "$work.o" "$work"

  run_t0=$(date +%s%N 2>/dev/null || echo 0)
  _tf_progress_init "$(grep -c . "$work" 2>/dev/null || echo 0)"
  skip=0; unjudged=0
  while IFS="$US" read -r id route status; do
    [ -n "${id:-}" ] || continue
    if [ "$(qa_status "$status")" = "Skipped" ]; then
      skip=$((skip + 1)); _tf_progress_tick SKIP seo "$id"; continue
    fi
    t0=$(date +%s%N 2>/dev/null || echo 0)
    : > "$SEO_TMP.find"; SEO_VERDICT=""; SEO_NOTE=""
    case "$id" in
      SEO-SITE-001) _seo_robots ;;
      SEO-SITE-002) _seo_sitemap ;;
      SEO-SITE-003) _seo_soft404 ;;
      SEO-SITE-004) _seo_duplicates ;;
      *)            _seo_page "$id" "${route:-/}" ;;
    esac
    t1=$(date +%s%N 2>/dev/null || echo 0)
    ms=$(( (t1 - t0) / 1000000 )); [ "$ms" -lt 0 ] && ms=0

    # A page that needs a login is not a page a crawler sees. It is neither a
    # pass nor a failure, so it leaves no result row at all.
    if [ "$SEO_VERDICT" = SKIP ]; then
      skip=$((skip + 1)); _tf_progress_tick SKIP seo "$id"; continue
    fi
    [ -n "$SEO_VERDICT" ] || { [ -s "$SEO_TMP.find" ] && SEO_VERDICT=FAIL || SEO_VERDICT=PASS; }
    [ "$SEO_VERDICT" = UNJUDGED ] && unjudged=$((unjudged + 1))

    ev="$TESTS_DIR/evidence/$id/seo.txt"
    if [ -s "$SEO_TMP.find" ]; then
      mkdir -p "$TESTS_DIR/evidence/$id"
      { echo "$id $route"; sed 's/^/- /' "$SEO_TMP.find"; } > "$ev"
      nf="$(grep -c . "$SEO_TMP.find")"
      actual="$(head -1 "$SEO_TMP.find")"
      [ "$nf" -gt 1 ] && actual="$actual (and $((nf - 1)) more in $ev)"
    else
      rm -f "$ev"; rmdir "$TESTS_DIR/evidence/$id" 2>/dev/null
      actual="${SEO_NOTE:-ok}"
    fi
    expected="indexable"
    [ "$SEO_VERDICT" = UNJUDGED ] && expected="needs-render: handed to seo-auditor"

    printf '%s,seo,nobody,%s,%s,%s,%s,%s\n' "$id" "$(_api_nocomma "$route")" \
      "$(_api_nocomma "$expected")" "$(_api_nocomma "$actual" | cut -c1-200)" "$SEO_VERDICT" "$ms" >> "$out"
    _tf_progress_tick "$SEO_VERDICT" seo "$id"
  done < "$work"
  _tf_progress_done
  rm -f "$work" "$SEO_TMP".*

  now="$(date +%Y-%m-%dT%H:%M:%S)"
  awk -F, -v now="$now" 'NR > 1 {
    st = ($7 == "PASS") ? " status=Pass" : \
         (($7 == "FAIL") ? " status=Fail" : \
         ((($7 == "ERROR") || ($7 == "UNJUDGED")) ? " status=Blocked" : ""))
    act = $6; gsub(/ /, "+", act)
    print $1 st (act != "" ? " actual=" act : "") " last_result=" $7 " last_run=" now
  }' "$out" | cmd_setmany

  run_t1=$(date +%s%N 2>/dev/null || echo 0)
  {
    echo "time=$(date +%H:%M:%S)"
    echo "duration_ms=$(( (run_t1 - run_t0) / 1000000 ))"
    echo "skipped=$skip"
    echo "skip_reason=behind a login or not a page - a crawler never sees it"
    echo "unjudged=$unjudged"
  } > "${out%.csv}.meta"

  [ -s "$SEO_DIR/render.txt" ] &&
    echo "seo: $(grep -c . "$SEO_DIR/render.txt") page(s) render in the browser -- hand $SEO_DIR/render.txt to seo-auditor" >&2
  cmd_summary "$out"
}

# ------------------------------------------------------------------ fetching

# _seo_get <path-or-url> -- one request, no redirects followed. Leaves the body
# in $SEO_TMP.body and the headers in $SEO_TMP.hdr; sets SEO_CODE, SEO_LOC.
_seo_get() {
  _g_url="$(_seo_abs "$1")"
  _g_w="$(curl -s -D "$SEO_TMP.hdr" -o "$SEO_TMP.body" -w '%{http_code} %{redirect_url}' \
          --max-time 20 --max-redirs 0 -A 'Mozilla/5.0 (compatible; testwright-seo)' "$_g_url" 2>/dev/null)"
  SEO_CODE="${_g_w%% *}"; SEO_LOC="${_g_w#* }"
  [ -n "$SEO_CODE" ] || SEO_CODE=000
  [ "$SEO_LOC" = "$_g_w" ] && SEO_LOC=""
  [ -f "$SEO_TMP.body" ] || : > "$SEO_TMP.body"
  [ -f "$SEO_TMP.hdr" ] || : > "$SEO_TMP.hdr"
}

# _seo_code <path-or-url> -- status code only, for a linked resource.
_seo_code() {
  _c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 --max-redirs 0 \
        -A 'Mozilla/5.0 (compatible; testwright-seo)' "$(_seo_abs "$1")" 2>/dev/null)"
  printf '%s' "${_c:-000}"
}

# A URL on this site, made absolute against base_url. Only ever called with a
# path, or with a URL whose host _seo_ours has already accepted -- which is the
# production guard's job, done once, in one place.
_seo_abs() {
  case "$1" in
    http://*|https://*) printf '%s%s' "$base" "$(_seo_path "$1")" ;;
    /*) printf '%s%s' "$base" "$1" ;;
    *)  printf '%s/%s' "$base" "$1" ;;
  esac
}

_seo_host() { printf '%s' "$1" | sed -e 's#^[a-zA-Z]*:##' -e 's#^//##' -e 's#[/?\#].*$##' -e 's#:.*$##' | tr 'A-Z' 'a-z'; }
_seo_path() {
  _p="$(printf '%s' "$1" | sed -e 's#^[a-zA-Z]*://[^/]*##' -e 's#^//[^/]*##' -e 's#\#.*$##')"
  printf '%s' "${_p:-/}"
}

# _seo_ours <url> <route> -- may this URL be fetched, and as which path?
# Prints the path to fetch on base_url, or nothing.
#
# A canonical or og:image almost always names the production host while the
# suite runs against localhost. Fetching production is exactly what the
# production guard forbids, so a URL on the page's own canonical host is
# checked by its path on base_url instead. Any other host (a CDN, a partner
# site) is not fetched at all.
_seo_ours() {
  case "$1" in
    http://*|https://*|//*)
      _h="$(_seo_host "$1")"
      if [ "$_h" = "$base_host" ] || [ "$_h" = "${SEO_SITE_HOST:-}" ] || [ "$_h" = "${SEO_CANON_HOST:-}" ]; then _seo_path "$1"; fi ;;
    /*) printf '%s' "$1" ;;
    '') ;;
    *)  printf '%s/%s' "$(printf '%s' "$2" | sed 's#/[^/]*$##')" "$1" ;;
  esac
}

_seo_find() { printf '%s\n' "$*" >> "$SEO_TMP.find"; }

_seo_hdr() { # <name> -- a response header's value, lowercased
  tr -d '\r' < "$SEO_TMP.hdr" | awk -v n="$1" 'BEGIN { n = tolower(n) ":" }
    tolower(substr($0, 1, length(n))) == n { v = substr($0, length(n) + 1); sub(/^[ \t]+/, "", v); print tolower(v) }' | tail -1
}

# The value list of "noindex_allow" in framework.json's "seo" block. json_get
# only reads scalars; this is the one array the engine needs.
_seo_json_list() {
  [ -f "$1" ] || return 0
  tr -d '\r\n' < "$1" | awk -v k="$2" '{
    p = index($0, "\"" k "\""); if (!p) exit
    r = substr($0, p + length(k) + 2); sub(/^[ \t]*:[ \t]*\[/, "", r)
    r = substr(r, 1, index(r, "]") - 1)
    n = split(r, A, ",")
    for (i = 1; i <= n; i++) { v = A[i]; gsub(/^[ \t]*"|"[ \t]*$/, "", v); if (v != "") print v }
  }'
}

# ------------------------------------------------------------------- parsing

# Reads one HTML page and prints what a crawler reads from its head, one
# `key<TAB>value` per line. Not an HTML parser: a tag scanner, which is all a
# head needs and all awk can honestly promise. JSON-LD blocks are copied out
# raw to `jl` (a file prefix) for the agent -- awk cannot judge JSON.
SEO_AWK='
function attr(tag, name,   l, s, c, r, e) {
  l = tolower(tag)
  if (!match(l, "[ \t\n/]" name "[ \t]*=[ \t]*")) return ""
  s = RSTART + RLENGTH; c = substr(tag, s, 1)
  if (c == "\"" || c == "\047") { r = substr(tag, s + 1); e = index(r, c); return (e ? substr(r, 1, e - 1) : r) }
  r = substr(tag, s); if (match(r, /[ \t\n>]/)) r = substr(r, 1, RSTART - 1)
  sub(/\/$/, "", r); return r
}
function hasattr(tag, name) { return match(tolower(tag), "[ \t\n]" name "([ \t\n]*=|[ \t\n/>])") }
function tags(name, T,   n, pos, i, s, c, e) {
  n = 0; pos = 1
  while ((i = index(substr(L, pos), "<" name)) > 0) {
    s = pos + i - 1; c = substr(L, s + length(name) + 1, 1)
    if (c ~ /[ \t\n\/>]/) {
      e = index(substr(L, s), ">"); if (!e) break
      T[++n] = substr(D, s, e); TS[name, n] = s + e; pos = s + e
    } else pos = s + 1
  }
  return n
}
function inner(start, name,   e) {       # text from start to </name>
  e = index(substr(L, start), "</" name)
  return e ? substr(D, start, e - 1) : ""
}
function clean(s) {
  gsub(/<[^>]*>/, " ", s)
  gsub(/&amp;/, "\\&", s); gsub(/&quot;/, "\"", s); gsub(/&#0?39;|&apos;/, "\047", s)
  gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&nbsp;/, " ", s)
  gsub(/[ \t\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
function out(k, v) { gsub(/\t/, " ", v); printf "%s\t%s\n", k, v }
function strip(s, name,   ls, o, i, e) {  # drop every <name>...</name> block
  o = ""; ls = tolower(s)
  while ((i = index(ls, "<" name)) > 0) {
    o = o substr(s, 1, i - 1)
    e = index(substr(ls, i), "</" name ">")
    if (!e) { s = ""; ls = ""; break }
    s = substr(s, i + e + length(name) + 2); ls = substr(ls, i + e + length(name) + 2)
  }
  return o s
}
{ sub(/\r$/, ""); D = D (NR > 1 ? "\n" : "") $0 }
END {
  L = tolower(D)

  n = tags("title", T)
  if (n) { t = clean(inner(TS["title", 1], "title")); out("title", t); out("title_len", length(t)) }

  n = tags("html", T); if (n) out("lang", attr(T[1], "lang"))

  n = tags("meta", T)
  for (i = 1; i <= n; i++) {
    nm = tolower(attr(T[i], "name")); pr = tolower(attr(T[i], "property")); ct = attr(T[i], "content")
    if (nm == "description") { d = clean(ct); out("description", d); out("description_len", length(d)) }
    else if (nm == "robots" || nm == "googlebot") out("robots", tolower(ct))
    else if (nm == "viewport") out("viewport", ct)
    k = (pr != "") ? pr : nm
    if (k == "og:title" || k == "og:description" || k == "og:image") out(k, clean(ct))
  }

  n = tags("link", T); nc = 0
  for (i = 1; i <= n; i++) {
    rel = " " tolower(attr(T[i], "rel")) " "
    if (rel ~ / canonical /) { nc++; if (nc == 1) out("canonical", attr(T[i], "href")) }
    hl = attr(T[i], "hreflang")
    if (hl != "" && rel ~ / alternate /) out("hreflang", tolower(hl) " " attr(T[i], "href"))
  }
  out("canonical_count", nc)

  n = tags("h1", T); out("h1_count", n)
  if (n) out("h1", clean(inner(TS["h1", 1], "h1")))

  n = tags("img", T); na = 0
  for (i = 1; i <= n; i++) if (!hasattr(T[i], "alt")) { na++; if (na <= 5) out("img_noalt", attr(T[i], "src")) }
  out("img_count", n); out("img_noalt_count", na)

  n = tags("script", T); ns = 0; nj = 0
  for (i = 1; i <= n; i++) {
    ty = tolower(attr(T[i], "type"))
    if (hasattr(T[i], "src")) ns++
    if (ty == "application/ld+json" && jl != "") { nj++; print inner(TS["script", i], "script") > (jl "-" nj ".json"); close(jl "-" nj ".json") }
  }
  out("script_src_count", ns); out("jsonld_count", nj)

  # How much a reader would see with JavaScript off. A shell page for a
  # client-side app has a mount node, a bundle, and next to no text.
  b = D; p = index(L, "<body"); if (p) b = substr(D, p)
  b = strip(strip(strip(b, "script"), "style"), "noscript")
  out("text_len", length(clean(b)))
  out("mount", (L ~ /id=["\047]?(root|app|__next|__nuxt|svelte|q-app)["\047 >]/ || index(L, "<app-root")) ? 1 : 0)
}'

# _seo_parse <jsonld-prefix> -- parse $SEO_TMP.body into $SEO_TMP.kv.
_seo_parse() { awk -v jl="$1" "$SEO_AWK" "$SEO_TMP.body" > "$SEO_TMP.kv"; }
_seo_kv() { awk -F '\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' "$SEO_TMP.kv"; }
_seo_all() { awk -F '\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$SEO_TMP.kv"; }
_seo_has() { awk -F '\t' -v k="$1" '$1 == k { f = 1 } END { exit !f }' "$SEO_TMP.kv"; }

# ----------------------------------------------------------------- the checks

# _seo_page <id> <route> -- the per-page checks. Sets SEO_VERDICT only for the
# verdicts a finding list cannot express (SKIP, UNJUDGED, ERROR).
_seo_page() {
  _id="$1"; _route="$2"; _hops=0; _at="$_route"
  while :; do
    _seo_get "$_at"
    case "$SEO_CODE" in
      30[12378])
        _hops=$((_hops + 1))
        # Sent to a login page: a crawler never sees what is behind it.
        case "$(printf '%s' "$SEO_LOC" | tr 'A-Z' 'a-z')" in
          *login*|*signin*|*sign-in*|*sign_in*|*/auth*|*oauth*|*sso*) SEO_VERDICT=SKIP; return ;;
        esac
        _h="$(_seo_host "$SEO_LOC")"
        if [ -n "$_h" ] && [ "$_h" != "$base_host" ]; then
          _seo_find "redirects off-site to $SEO_LOC"; return
        fi
        [ "$_hops" -ge 2 ] && { _seo_find "redirect chain: $_route -> ... -> $(_seo_path "$SEO_LOC") (crawlers give up; link the final URL)"; return; }
        _at="$(_seo_path "$SEO_LOC")" ;;
      *) break ;;
    esac
  done
  case "$SEO_CODE" in
    000) SEO_VERDICT=ERROR; SEO_NOTE="no response"; return ;;
    401|403) SEO_VERDICT=SKIP; return ;;
    200) ;;
    *) _seo_find "returns HTTP $SEO_CODE"; return ;;
  esac
  case "$(_seo_hdr content-type)" in
    ''|*html*) ;;
    *) SEO_VERDICT=SKIP; return ;;       # not a page: a file, a feed, JSON
  esac

  _seo_parse "$SEO_DIR/jsonld/$_id"
  title="$(_seo_kv title)"; desc="$(_seo_kv description)"; h1n="$(_seo_kv h1_count)"
  canon="$(_seo_kv canonical)"
  SEO_SITE_HOST="$(_seo_host "$canon")"
  [ -n "$SEO_CANON_HOST" ] || SEO_CANON_HOST="$SEO_SITE_HOST"

  # A shell page for a client-rendered app: judge it in a browser, not here.
  if [ "${h1n:-0}" = 0 ] && [ "$(_seo_kv mount)" = 1 ] && [ "$(_seo_kv script_src_count)" -gt 0 ] &&
     [ "$(_seo_kv text_len)" -lt 200 ]; then
    printf '%s\t%s\n' "$_id" "$_at" >> "$SEO_DIR/render.txt"
    SEO_VERDICT=UNJUDGED; SEO_NOTE="client-rendered: no h1 or text until JavaScript runs"
    return
  fi

  # Not accidentally hidden from search -- checked first, because a page meant
  # to be hidden (listed under seo.noindex_allow) owes a crawler nothing else.
  _noidx=""
  case " $(_seo_kv robots) " in *noindex*|*" none "*) _noidx="meta robots" ;; esac
  case "$(_seo_hdr x-robots-tag)" in *noindex*|*none*) _noidx="${_noidx:+$_noidx and }X-Robots-Tag header" ;; esac
  if [ -n "$_noidx" ]; then
    if printf '%s\n' "$noindex_allow" | grep -qxF -- "$_route"; then
      SEO_NOTE="noindex on purpose (seo.noindex_allow)"; return 0
    fi
    _seo_find "noindex set by $_noidx; search engines drop this page (list it under seo.noindex_allow if intended)"
  else
    printf '%s\n' "$_at" >> "$SEO_DIR/public.txt"
    printf '%s\t%s\t%s\t%s\t%s\tengine\n' "$_id" "$_at" "$title" "$desc" "$(_seo_kv h1)" >> "$SEO_DIR/heads.tsv"
  fi

  # 1-2. Title and description.
  if [ -z "$title" ]; then _seo_find "no <title>"
  else
    tl="$(_seo_kv title_len)"
    [ "$tl" -lt 10 ] && _seo_find "title is $tl characters (\"$title\"); aim for 10-60"
    [ "$tl" -gt 60 ] && _seo_find "title is $tl characters; search results cut it off after about 60"
  fi
  if [ -z "$desc" ]; then _seo_find "no meta description"
  else
    dl="$(_seo_kv description_len)"
    [ "$dl" -lt 50 ] && _seo_find "meta description is $dl characters; aim for 50-160"
    [ "$dl" -gt 160 ] && _seo_find "meta description is $dl characters; search results cut it off after about 160"
  fi

  # 3. Exactly one h1.
  [ "$h1n" = 0 ] && _seo_find "no <h1>"
  [ "${h1n:-0}" -gt 1 ] && _seo_find "$h1n <h1> elements; a page should have one"

  # 4. Canonical: present, absolute, alone, and pointing at a live page.
  if [ -z "$canon" ]; then _seo_find "no <link rel=canonical>"
  else
    [ "$(_seo_kv canonical_count)" -gt 1 ] && _seo_find "$(_seo_kv canonical_count) canonical links; crawlers ignore all of them"
    case "$canon" in
      http://*|https://*) ;;
      *) _seo_find "canonical is relative ($canon); it must be an absolute URL" ;;
    esac
    _p="$(_seo_ours "$canon" "$_at")"
    if [ -n "$_p" ]; then
      _c="$(_seo_code "$_p")"
      [ "$_c" = 200 ] || _seo_find "canonical $canon returns HTTP $_c"
    fi
  fi

  # 6. The basics every page needs.
  [ -n "$(_seo_kv lang)" ] || _seo_find "<html> has no lang attribute"
  _seo_has viewport || _seo_find "no <meta name=viewport>; mobile-first indexing treats the page as desktop-only"

  # 7. Open Graph, for the preview a shared link gets.
  for _k in og:title og:description og:image; do
    [ -n "$(_seo_kv "$_k")" ] || _seo_find "no $_k"
  done
  _img="$(_seo_kv og:image)"
  if [ -n "$_img" ]; then
    case "$_img" in http://*|https://*) ;; *) _seo_find "og:image is relative ($_img); it must be an absolute URL" ;; esac
    _p="$(_seo_ours "$_img" "$_at")"
    if [ -n "$_p" ]; then
      _c="$(_seo_code "$_p")"
      [ "$_c" = 200 ] || _seo_find "og:image $_img returns HTTP $_c"
    fi
  fi

  # 8. hreflang alternates resolve, with an x-default once there are several.
  _seo_all hreflang > "$SEO_TMP.hl"
  _nh="$(grep -c . "$SEO_TMP.hl")"
  if [ "$_nh" -gt 0 ]; then
    [ "$_nh" -gt 1 ] && ! grep -q '^x-default ' "$SEO_TMP.hl" &&
      _seo_find "$_nh hreflang alternates but no x-default"
    while IFS=' ' read -r _lang _href; do
      _p="$(_seo_ours "$_href" "$_at")"; [ -n "$_p" ] || continue
      _c="$(_seo_code "$_p")"
      [ "$_c" = 200 ] || _seo_find "hreflang $_lang -> $_href returns HTTP $_c"
    done < "$SEO_TMP.hl"
  fi

  # 9. Images a crawler can describe.
  _na="$(_seo_kv img_noalt_count)"
  [ "${_na:-0}" -gt 0 ] &&
    _seo_find "$_na <img> without an alt attribute (first: $(_seo_all img_noalt | head -1))"
  return 0
}

# SEO-SITE-001 -- robots.txt
_seo_robots() {
  _seo_get /robots.txt
  [ "$SEO_CODE" = 000 ] && { SEO_VERDICT=ERROR; SEO_NOTE="no response"; return; }
  [ "$SEO_CODE" = 200 ] || { _seo_find "/robots.txt returns HTTP $SEO_CODE"; return; }
  case "$(_seo_hdr content-type)" in
    *html*) _seo_find "/robots.txt serves an HTML page (a catch-all route answered it)"; return ;;
  esac
  # Does the group that applies to every crawler disallow everything?
  if tr -d '\r' < "$SEO_TMP.body" | awk '
      { l = tolower($0); sub(/#.*/, "", l); gsub(/[ \t]+/, "", l) }
      l ~ /^user-agent:/ { if (!ing) star = 0; ing = 1; if (l == "user-agent:*") star = 1; next }
      l ~ /^(disallow|allow):/ { ing = 0; if (star && l == "disallow:/") hit = 1 }
      END { exit !hit }'; then
    _seo_find "robots.txt disallows / for every crawler; the whole site is hidden from search"
  fi
  grep -qi '^[[:space:]]*sitemap:' "$SEO_TMP.body" || _seo_find "robots.txt has no Sitemap: line"
  return 0
}

# SEO-SITE-002 -- the sitemap: parses, lists live pages only, misses none.
_seo_sitemap() {
  _sm=""
  _seo_get /robots.txt
  [ "$SEO_CODE" = 200 ] &&
    _sm="$(tr -d '\r' < "$SEO_TMP.body" | awk 'tolower($1) == "sitemap:" { print $2; exit }')"
  _sm_path=/sitemap.xml
  if [ -n "$_sm" ]; then
    _sm_path="$(_seo_ours "$_sm" /)"
    # The sitemap robots.txt names lives somewhere this suite may not fetch.
    [ -n "$_sm_path" ] || _sm_path="$(_seo_path "$_sm")"
  fi
  _seo_get "$_sm_path"
  [ "$SEO_CODE" = 000 ] && { SEO_VERDICT=ERROR; SEO_NOTE="no response"; return; }
  [ "$SEO_CODE" = 200 ] || { _seo_find "sitemap $_sm_path returns HTTP $SEO_CODE"; return; }

  : > "$SEO_TMP.locs"
  if grep -qi '<sitemapindex' "$SEO_TMP.body"; then
    _seo_locs < "$SEO_TMP.body" | head -20 > "$SEO_TMP.idx"
    while IFS= read -r _child; do
      _p="$(_seo_ours "$_child" /)"; [ -n "$_p" ] || _p="$(_seo_path "$_child")"
      _seo_get "$_p"
      if [ "$SEO_CODE" = 200 ]; then _seo_locs < "$SEO_TMP.body" >> "$SEO_TMP.locs"
      else _seo_find "child sitemap $_child returns HTTP $SEO_CODE"; fi
    done < "$SEO_TMP.idx"
  elif grep -qi '<urlset' "$SEO_TMP.body"; then
    _seo_locs < "$SEO_TMP.body" > "$SEO_TMP.locs"
  else
    _seo_find "sitemap $_sm_path is not a <urlset> or <sitemapindex>"; return
  fi
  _total="$(grep -c . "$SEO_TMP.locs")"
  [ "$_total" -gt 0 ] || { _seo_find "sitemap lists no URLs"; return; }
  [ "$_total" -gt "$max_urls" ] && SEO_NOTE="checked $max_urls of $_total URLs (seo.max_sitemap_urls)"

  head -n "$max_urls" "$SEO_TMP.locs" > "$SEO_TMP.chk"
  while IFS= read -r _loc; do
    _p="$(_seo_ours "$_loc" /)"; [ -n "$_p" ] || _p="$(_seo_path "$_loc")"
    _seo_get "$_p"
    if [ "$SEO_CODE" != 200 ]; then _seo_find "sitemap lists $_loc, which returns HTTP $SEO_CODE"; continue; fi
    _seo_parse ""
    _r="$(_seo_kv robots) $(_seo_hdr x-robots-tag)"
    case "$_r" in *noindex*) _seo_find "sitemap lists $_loc, which is noindex" ;; esac
  done < "$SEO_TMP.chk"

  # Every public page this run judged should be in it.
  sed -e 's#^[a-zA-Z]*://[^/]*##' -e 's#^$#/#' -e 's#\(.\)/$#\1#' "$SEO_TMP.locs" | sort -u > "$SEO_TMP.paths"
  sed -e 's#\(.\)/$#\1#' "$SEO_DIR/public.txt" | sort -u | while IFS= read -r _pub; do
    grep -qxF -- "$_pub" "$SEO_TMP.paths" || echo "$_pub"
  done > "$SEO_TMP.miss"
  if [ -s "$SEO_TMP.miss" ]; then
    _seo_find "$(grep -c . "$SEO_TMP.miss") public page(s) missing from the sitemap: $(head -5 "$SEO_TMP.miss" | tr '\n' ' ')"
  fi
  return 0
}

# Pull every <loc> out of a sitemap, CDATA and whitespace removed.
_seo_locs() {
  tr -d '\r\n' | awk '{ n = split($0, P, /<[lL][oO][cC]>/)
    for (i = 2; i <= n; i++) { v = P[i]; e = index(v, "<"); if (substr(v, e, 9) == "<![CDATA[") { v = substr(v, e + 9); e = index(v, "]]>") }
      v = substr(v, 1, e - 1); gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/&amp;/, "\\&", v); if (v != "") print v } }'
}

# SEO-SITE-003 -- a missing page must say so. A 200 (or a redirect to the home
# page) for a path that does not exist is a soft 404: every typo'd link becomes
# a duplicate of some real page in the index.
_seo_soft404() {
  _seo_get "/tf-seo-probe-$$-does-not-exist"
  case "$SEO_CODE" in
    404|410) ;;
    000) SEO_VERDICT=ERROR; SEO_NOTE="no response" ;;
    30*) _seo_find "a path that does not exist redirects to $SEO_LOC instead of returning 404 (soft 404)" ;;
    *) _seo_find "a path that does not exist returns HTTP $SEO_CODE instead of 404 (soft 404)" ;;
  esac
}

# SEO-SITE-004 -- no two public pages share a title or a description.
_seo_duplicates() {
  for _col in 3:title 4:description; do
    _n="${_col%%:*}"; _what="${_col#*:}"
    awk -F '\t' -v c="$_n" -v what="$_what" 'NR > 1 && $c != "" {
        k = tolower($c); R[k] = R[k] (R[k] == "" ? "" : " ") $2; N[k]++; V[k] = $c }
      END { for (k in N) if (N[k] > 1) printf "%d pages share the %s \"%s\": %s\n", N[k], what, V[k], R[k] }' \
      "$SEO_DIR/heads.tsv" >> "$SEO_TMP.find"
  done
  [ "$(grep -c . "$SEO_DIR/heads.tsv")" -gt 1 ] || SEO_NOTE="no pages judged yet"
}
