# shellcheck shell=sh
# lib/notifications.sh -- notifications: the emails a run made the app send
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Email is tested against a sandbox outbox -- Mailpit or MailHog, where the
# app's SMTP settings point in development -- never against real delivery.
# The outbox's API is read by scripts/tf-outbox.py (standard library only).
#
#   notifications mark       record "now"; the run judges only mail sent after
#   NOTIF-SITE-001           every email sent since the mark is clean: its
#                            same-site links resolve; no password, key, token
#                            or card number in it; no {{template}} or
#                            undefined; a subject; a plain-text part
#   NOTIF-NNN                written by `outbox-checker`: after a trigger, an
#                            email to <address> with <subject> arrived, and
#                            is clean. Test Data: `to: <addr> | subject: <text>`
#
# framework.json: "notifications": { "outbox": "http://localhost:8025" }. The
# outbox must be local: a remote one is somebody's real mail.

cmd_notifications() {
  _n_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_n_sub" in
    mark)  mkdir -p "$CACHE"; date +%s > "$CACHE/outbox.since"; echo "notifications: judging mail sent after $(date +%H:%M:%S)" >&2 ;;
    cases) _notif_cases ;;
    run)   _chk_run notifications notifications "$@" ;;
    *) die "notifications: expected 'mark', 'cases' or 'run [--only <ids>]'" ;;
  esac
}

_notif_cases() {
  _chk_header
  _chk_row NOTIF-SITE-001 "Notifications" "Every email the app sends is safe and complete" "" nobody \
    "tf.sh notifications mark | run the suite | read every email the sandbox outbox received" \
    "Each has a subject and a plain-text part; its same-site links resolve; it holds no password, key, token or card number; no unfilled {{template}} or undefined" \
    api /outbox notifications
  echo "notifications: 1 site case; outbox-checker writes one NOTIF case per email-sending flow" >&2
}

_notifications_init() {
  NT_OK=1; NT_WHY=""
  NT_OUT="$(json_get "$FRAMEWORK" notifications.outbox 2>/dev/null || true)"
  [ -n "$NT_OUT" ] || NT_OUT="http://localhost:8025"
  NT_OUT="$(printf '%s' "$NT_OUT" | sed 's#/*$##')"
  case "$(_seo_host "$NT_OUT")" in
    localhost|127.0.0.1|0.0.0.0|::1|*.local|*.localhost|host.docker.internal|mailpit|mailhog) ;;
    *) NT_OK=0; NT_WHY="outbox $NT_OUT is not local: only a sandbox outbox is read" ;;
  esac
  NT_PY="$(tf_python 2>/dev/null || true)"
  NT_SCRIPT="$(dirname "$(tf_xlsx_script)")/tf-outbox.py"
  [ "$NT_OK" = 1 ] && { [ -n "$NT_PY" ] && [ -f "$NT_SCRIPT" ] || { NT_OK=0; NT_WHY="no python: reading the outbox needs python3 (standard library only)"; }; }
  NT_SINCE="$(cat "$CACHE/outbox.since" 2>/dev/null || echo 0)"
  mkdir -p "$CHK_DIR/mail"
  if [ "$NT_OK" = 1 ]; then
    "$NT_PY" "$NT_SCRIPT" list "$NT_OUT" "$NT_SINCE" 2>/dev/null | tr -d '\r' > "$CHK_DIR/messages.tsv"
    _rc=$?
    if [ ! -s "$CHK_DIR/messages.tsv" ] && ! "$NT_PY" "$NT_SCRIPT" list "$NT_OUT" 9999999999 >/dev/null 2>&1; then
      NT_OK=0; NT_WHY="the outbox at $NT_OUT does not answer (is Mailpit or MailHog running?)"
    fi
  fi
  CHK_SKIP_REASON="-"
}

# _notif_judge <message-id> -- the clean-email checks on one message. Findings
# are prefixed with the message's subject so a site case stays readable.
_notif_judge() {
  _mid="$1"; _pre="$CHK_DIR/mail/$_mid"
  "$NT_PY" "$NT_SCRIPT" get "$NT_OUT" "$_mid" "$_pre" >/dev/null 2>&1 || { _chk_find "message $_mid could not be read from the outbox"; return; }
  _subj="$(awk -F '\t' -v m="$_mid" '$1 == m { print $4; exit }' "$CHK_DIR/messages.tsv")"
  _who="\"${_subj:-(no subject)}\""
  [ -n "$_subj" ] || _chk_find "an email to $(awk -F '\t' -v m="$_mid" '$1 == m { print $3 }' "$CHK_DIR/messages.tsv") has no subject"
  [ -s "$_pre.txt" ] || _chk_find "$_who has no plain-text part; text-only clients and spam filters see nothing"
  # Secrets and personal data: the page scanner, run on the message.
  cat "$_pre.html" "$_pre.txt" > "$CHK_TMP.body"; : > "$CHK_TMP.hdr"
  : > "$CHK_TMP.pf"; mv "$CHK_TMP.find" "$CHK_TMP.keep"; : > "$CHK_TMP.find"
  _priv_scan mail
  grep -qiE '(your|new|temporary) password( is)?[: ]+[^ <]{4,}|password: [^ <]{4,}' "$CHK_TMP.body" &&
    _chk_find "the email contains a password in clear text"
  grep -qE '\{\{[^}]*\}\}|\{%[^%]*%\}|(^|[^A-Za-z])undefined([^A-Za-z]|$)|\[object Object\]' "$CHK_TMP.body" &&
    _chk_find "the email has an unfilled template or 'undefined' in it"
  sed "s#^#$_who: #" "$CHK_TMP.find" >> "$CHK_TMP.keep"; mv "$CHK_TMP.keep" "$CHK_TMP.find"
  # Same-site links must lead somewhere; others are counted, never fetched.
  tr '\r\n' '  ' < "$_pre.html" | grep -oiE 'href=["'"'"']?[^"'"'"' >]+' | sed -E 's/^href=["'"'"']?//' | sort -u |
  while IFS= read -r _u; do
    case "$_u" in mailto:*|tel:*|'#'*) continue ;; esac
    _h="$(_seo_host "$_u")"
    case "$_u" in http://*|https://*) [ "$_h" = "$base_host" ] || continue; _u="$(_seo_path "$_u")" ;; esac
    _c="$(_chk_code "$_u" nobody)"
    case "$_c" in 2*) ;; *) _chk_find "$_who links to $_u, which returns HTTP $_c" ;; esac
  done
}

_notifications_case() { # <id> <route> <role> <type> <tags>
  [ "$NT_OK" = 1 ] || { CHK_VERDICT=UNJUDGED; CHK_EXPECTED="$NT_WHY"; CHK_NOTE="-"; return; }
  _n="$(grep -c . "$CHK_DIR/messages.tsv" 2>/dev/null || echo 0)"
  case "$1" in
    NOTIF-SITE-*)
      [ "$_n" -gt 0 ] || { CHK_NOTE="no email was sent since the mark"; return 0; }
      cut -f1 "$CHK_DIR/messages.tsv" | head -50 | while IFS= read -r _m; do _notif_judge "$_m"; done
      CHK_NOTE="$_n email(s) checked"
      [ "$NT_SINCE" = 0 ] && CHK_NOTE="$CHK_NOTE (no mark: every message in the outbox)"
      return 0 ;;
  esac
  # NOTIF-NNN: find the expected message, then judge it.
  _data="$(cmd_select --id "$1" --cols data --format plain 2>/dev/null | head -1)"
  _to="$(printf '%s' "$_data" | sed -n 's/.*to:[[:space:]]*\([^ |]*\).*/\1/p')"
  _sub="$(printf '%s' "$_data" | sed -n 's/.*subject:[[:space:]]*\([^|]*\).*/\1/p' | sed 's/[[:space:]]*$//')"
  [ -n "$_to$_sub" ] || { CHK_VERDICT=UNJUDGED; CHK_EXPECTED="Test Data must say 'to: <address> | subject: <text>'"; CHK_NOTE="-"; return; }
  _m="$(awk -F '\t' -v to="$(printf '%s' "$_to" | tr 'A-Z' 'a-z')" -v s="$(printf '%s' "$_sub" | tr 'A-Z' 'a-z')" '
        (to == "" || index(tolower($3), to)) && (s == "" || index(tolower($4), s)) { m = $1 } END { print m }' "$CHK_DIR/messages.tsv")"
  if [ -z "$_m" ]; then
    _chk_find "no email${_to:+ to $_to}${_sub:+ with a subject containing \"$_sub\"} arrived after the mark ($_n other email(s) did)"
    return 0
  fi
  _notif_judge "$_m"
  CHK_NOTE="the email arrived and is clean"
  return 0
}
