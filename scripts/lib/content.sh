# shellcheck shell=sh
# lib/content.sh -- content: what a visitor reads that should never ship
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Some of the most embarrassing bugs are in plain sight: "Lorem ipsum" on a
# live page, "Hello, {{ user.name }}", "You have undefined messages", a price
# of NaN, "translation missing: de.checkout.title", "CafÃ©" where the
# encoding broke. All of them are in the text the server sends, so curl finds
# them for free. Whether the copy is *good* -- a vague error, an empty state
# with nothing to say, two words for the same thing -- is judgement, and goes
# to the `content-reviewer` agent, which reads the text this pass saves.
#
#   CONTENT-NNN   one per page: placeholder copy, template and JavaScript
#                 leaks, missing translations, raw i18n keys, mojibake,
#                 server warnings in the page, a blank page
#
# A page that is an empty shell until JavaScript runs is UNJUDGED
# `needs-render`, listed in tests/.cache/content/render.txt for the reviewer
# to read in a browser. The visible text of every judged page is saved to
# tests/.cache/content/text/<id>.txt.

cmd_content() {
  _c_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_c_sub" in
    cases) _content_cases "$@" ;;
    run)   _chk_run content content "$@" ;;
    *) die "content: expected 'cases <routes> [privileged]' or 'run [--only <ids>]'" ;;
  esac
}

_content_cases() {
  _chk_header
  _n=0
  _chk_pages "${1:-$CACHE/routes.txt}" "${2:-}" > "$CACHE/.content-pages.$$"
  while IFS="$(printf '\t')" read -r _r _who; do
    _n=$((_n + 1))
    _chk_row "$(printf 'CONTENT-%03d' "$_n")" "Content" "$_r shows no placeholder, leaked code or broken text" \
      "Visible text of $_r" "$_who" "Open $_r | read the text a visitor sees" \
      "No lorem ipsum or TODO; no {{template}}, undefined, NaN or [object Object]; no missing translation or raw i18n key; no garbled characters; no server warning; not blank" \
      page "$_r" content
  done < "$CACHE/.content-pages.$$"
  rm -f "$CACHE/.content-pages.$$"
  echo "content: $_n page case(s)" >&2
}

_content_init() {
  CONTENT_SKIP=" $(_chk_list content skip | tr '\n' ' ') "
  mkdir -p "$CHK_DIR/text"; : > "$CHK_DIR/render.txt"
  CHK_SKIP_REASON="behind a login with no session, or not a page"
}

# The text a visitor reads: script, style and comments removed, tags turned
# into line breaks, entities decoded. One text node per line.
_content_text() {
  _chk_body | tr '\r\n\t' '   ' | awk '
    function strip(s, op, cl,   ls, out, p, q) {
      out = ""; ls = tolower(s)
      while ((p = index(ls, op)) > 0) {
        q = index(substr(ls, p), cl)
        out = out substr(s, 1, p - 1)
        if (q == 0) { s = ""; ls = ""; break }
        s = substr(s, p + q + length(cl) - 1); ls = substr(ls, p + q + length(cl) - 1)
      }
      return out s }
    { s = strip($0, "<script", "</script>"); s = strip(s, "<style", "</style>"); s = strip(s, "<!--", "-->")
      s = strip(s, "<noscript", "</noscript>")
      gsub(/<[^>]*>/, "\n", s)
      gsub(/&nbsp;/, " ", s); gsub(/&amp;/, "\\&", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s)
      gsub(/&quot;/, "\"", s); gsub(/&#39;|&apos;/, "'"'"'", s)
      print s }' | awk '{ gsub(/^[ ]+|[ ]+$/, ""); gsub(/[ ]+/, " ") } $0 != ""'
}

_content_case() { # <id> <route> <role>
  _chk_get "$2" "$3" --follow
  case "$CHK_CODE" in 000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;; esac
  if [ "$CHK_HOPS" -gt 0 ] && _chk_is_login "$CHK_URL"; then CHK_VERDICT=SKIP; return; fi
  case "$CHK_CODE" in 2*) ;; *) CHK_VERDICT=SKIP; return ;; esac
  case "$(_chk_hdr content-type)" in ''|*html*) ;; *) CHK_VERDICT=SKIP; return ;; esac

  _txt="$CHK_DIR/text/$1.txt"
  _content_text | head -c 20000 > "$_txt"
  _len="$(tr -d '\n ' < "$_txt" | wc -c | tr -d ' ')"
  # An empty shell for a client-rendered app: read it in a browser instead.
  if [ "$_len" -lt 40 ] && _chk_body | grep -qiE '<div[^>]*id=["'"'"']?(root|app|__next|__nuxt|main)' &&
     _chk_body | grep -qiE '<script[^>]*src='; then
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$CHK_DIR/render.txt"
    CHK_VERDICT=UNJUDGED; CHK_EXPECTED="needs-render: handed to content-reviewer"; CHK_NOTE="-"; return
  fi
  [ "$_len" -lt 20 ] && _chk_find "the page is blank: $_len visible character(s)"

  # _content_hit <name> <label> <ERE> -- one finding per kind, quoting the
  # line. <name> is what `content.skip` in framework.json switches off.
  _content_hit() {
    case "$CONTENT_SKIP" in *" $1 "*) return 0 ;; esac
    _h="$(grep -m1 -E -- "$3" "$_txt" | cut -c1-80)"
    [ -n "$_h" ] && _chk_find "[$1] $2: \"$_h\""
    return 0
  }
  _content_hit placeholder "placeholder copy" '[Ll]orem ipsum|dolor sit amet|consectetur adipiscing'
  _content_hit marker "an unfinished marker" '(^|[^A-Za-z])(TODO|FIXME|TBD|XXX)([^A-Za-z]|$)|placeholder text|sample text|insert (text|copy) here'
  _content_hit template "a template that was never filled in" '\{\{[^}]*\}\}|\{%[^%]*%\}|\$\{[A-Za-z_][^}]*\}|<%=?|%\([a-z_]+\)s|(^|[^%0-9])%[sd]([^A-Za-z]|$)'
  _content_hit js "a JavaScript value leaked into the text" '(^|[^A-Za-z])(undefined|NaN)([^A-Za-z]|$)|\[object Object\]|Invalid Date'
  _content_hit translation "a missing translation" '[Tt]ranslation missing|missing translation|\[missing[: ]|__MISSING__|MISSING_TRANSLATION'
  _content_hit encoding "garbled characters (a text-encoding bug)" 'Ã[©¨ª«¡¢£¤¥¦§±³¶¹º¼½¾¿]|â€[™œ”˜“¦]|�'
  _content_hit server "a server warning or trace in the page" 'Traceback \(most recent|(Warning|Notice|Fatal error): .* (in|on line)|Uncaught [A-Z][a-z]+Error|NullReferenceException|at [a-z]+\.[A-Za-z.]+\([A-Za-z]+\.java:'
  # A whole text node that is a dotted lowercase key is an i18n key shown raw.
  case "$CONTENT_SKIP" in *" i18n-key "*) ;; *)
    _k="$(grep -m1 -xE '[a-z][a-z0-9_]*(\.[a-z0-9_]+){2,}' "$_txt")"
    [ -n "$_k" ] && _chk_find "[i18n-key] an i18n key shown instead of its text: \"$_k\"" ;; esac
  CHK_NOTE="$_len characters of text checked"
  return 0
}
