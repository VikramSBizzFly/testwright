# shellcheck shell=sh
# lib/files.sh -- export-check: is a downloaded export what it claims to be?
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# A report or export case used to stop at "the download returned 200". That
# is how an empty CSV, a file of HTML error page saved as .xlsx, or a
# spreadsheet that runs a formula when someone opens it ships. This opens the
# file and reads it -- for free -- so export-verifier only has to compare.
#
# export-check <file> [--rows N] [--columns a,b,c]
#   prints `kind=... rows=... columns=...` and one `finding: ...` per problem;
#   exit 0 when clean, 1 when there is a finding.
#
#   csv / tsv  parses; header present; rows == --rows when given; expected
#              columns present; every row has the header's field count;
#              valid UTF-8; no cell that starts =, +, - or @ followed by a
#              letter or ( -- a formula a spreadsheet will run (CSV injection)
#   xlsx       a real zip with a workbook (python3, standard library); rows;
#              cells whose stored value is a formula built from user text
#   json       parses (python3); a top-level array's length is the row count
#   pdf        starts %PDF and ends %%EOF; page count
#   anything   an HTML page saved under an export's name is a finding

cmd_export_check() {
  _f="${1:-}"; [ -f "$_f" ] || die "export-check: no file '$_f'"; shift
  _want_rows=""; _want_cols=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rows) _want_rows="$2"; shift 2 ;;
      --columns) _want_cols="$2"; shift 2 ;;
      *) die "export-check: unexpected argument '$1'" ;;
    esac
  done
  _fx="$CACHE/.export.$$"; mkdir -p "$CACHE"; : > "$_fx"
  _find() { printf 'finding: %s\n' "$*" >> "$_fx"; }

  _size="$(wc -c < "$_f" | tr -d ' ')"
  [ "$_size" -gt 0 ] || _find "the file is empty (0 bytes)"
  if head -c 512 "$_f" | tr 'A-Z' 'a-z' | grep -qE '<!doctype html|<html'; then
    _find "the file is an HTML page, not an export (an error or login page saved under the export's name)"
    _kind=html
  else
    case "$(printf '%s' "$_f" | tr 'A-Z' 'a-z')" in
      *.csv) _kind=csv ;; *.tsv) _kind=tsv ;; *.xlsx) _kind=xlsx ;; *.json) _kind=json ;; *.pdf) _kind=pdf ;;
      *) case "$(head -c 4 "$_f")" in %PDF) _kind=pdf ;; PK*) _kind=xlsx ;; *) _kind=csv ;; esac ;;
    esac
  fi
  _rows=""; _cols=""

  case "$_kind" in
    csv|tsv)
      _sep=','; [ "$_kind" = tsv ] && _sep="$(printf '\t')"
      # Valid UTF-8, with or without a BOM (iconv when present).
      if have iconv && ! iconv -f UTF-8 -t UTF-8 "$_f" >/dev/null 2>&1; then
        _find "the file is not valid UTF-8; accented names will be garbled in Excel and elsewhere"
      fi
      tr -d '\r' < "$_f" | awk -v sep="$_sep" -v want="$_want_cols" "$AWKLIB"'
        function split_row(line, A) { if (sep == ",") return csvsplit(line, A); return split(line, A, sep) }
        NR == 1 { sub(/^\357\273\277/, "")                      # a UTF-8 byte-order mark
                  nh = split_row($0, H); for (i = 1; i <= nh; i++) HD[tolower(H[i])] = 1; cols = $0; next }
        $0 == "" { next }
        { n = split_row($0, F); rows++
          if (n != nh && bad < 3) { bad++; printf "finding: row %d has %d fields, the header has %d\n", NR, n, nh }
          for (i = 1; i <= n; i++) if (F[i] ~ /^[=+@-]/ && F[i] ~ /^[=+@-][ ]*[A-Za-z(]/ && inj < 3) {
            inj++; printf "finding: row %d column %d starts with %s -- a spreadsheet will run it as a formula (CSV injection); prefix it with a quote\n", NR, i, substr(F[i], 1, 1) } }
        END {
          if (NR == 0) print "finding: no header row"
          m = split(want, W, ","); for (i = 1; i <= m; i++) if (W[i] != "" && !(tolower(W[i]) in HD)) printf "finding: expected column \"%s\" is missing\n", W[i]
          printf "rows=%d\ncolumns=%s\n", rows, cols }' > "$_fx.o"
      grep '^finding:' "$_fx.o" >> "$_fx"
      _rows="$(sed -n 's/^rows=//p' "$_fx.o")"; _cols="$(sed -n 's/^columns=//p' "$_fx.o")"
      rm -f "$_fx.o" ;;
    xlsx|json)
      _py="$(tf_python 2>/dev/null || true)"
      if [ -z "$_py" ]; then
        _find "cannot open a $_kind without python3 (standard library only): unjudged"
      else
        "$_py" - "$_f" "$_kind" > "$_fx.o" 2>/dev/null <<'PY'
import json, re, sys, zipfile
path, kind = sys.argv[1], sys.argv[2]
if kind == "json":
    try:
        data = json.load(open(path, encoding="utf-8-sig"))
    except Exception as e:
        print("finding: not valid JSON (%s)" % str(e)[:80]); sys.exit()
    print("rows=%d" % (len(data) if isinstance(data, list) else 1))
    if isinstance(data, list) and data and isinstance(data[0], dict):
        print("columns=%s" % ",".join(data[0].keys()))
    sys.exit()
try:
    z = zipfile.ZipFile(path)
except zipfile.BadZipFile:
    print("finding: not a real .xlsx (not a zip)"); sys.exit()
sheets = sorted(n for n in z.namelist() if re.match(r"xl/worksheets/sheet\d+\.xml$", n))
if not sheets:
    print("finding: the workbook has no worksheet"); sys.exit()
x = z.read(sheets[0]).decode("utf-8", "replace")
rows = len(re.findall(r"<row\b", x))
print("rows=%d" % max(rows - 1, 0))
shared = z.read("xl/sharedStrings.xml").decode("utf-8", "replace") if "xl/sharedStrings.xml" in z.namelist() else ""
for s in re.findall(r"<t[^>]*>([^<]*)</t>", shared)[:5000]:
    if re.match(r"^[=+@-]\s*[A-Za-z(]", s):
        print("finding: a text cell starts with %s -- Excel can run it as a formula when edited (CSV/formula injection)" % s[0]); break
for f in re.findall(r"<f>([^<]*)</f>", x)[:3]:
    if re.search(r"HYPERLINK|WEBSERVICE|cmd|DDE", f, re.I):
        print("finding: the sheet contains a formula calling %s" % re.search(r"HYPERLINK|WEBSERVICE|cmd|DDE", f, re.I).group(0)); break
PY
        tr -d '\r' < "$_fx.o" | grep '^finding:' >> "$_fx"
        _rows="$(tr -d '\r' < "$_fx.o" | sed -n 's/^rows=//p')"; _cols="$(tr -d '\r' < "$_fx.o" | sed -n 's/^columns=//p')"
        rm -f "$_fx.o"
      fi ;;
    pdf)
      [ "$(head -c 4 "$_f")" = "%PDF" ] || _find "the file does not start with %PDF: not a PDF"
      tail -c 1024 "$_f" | grep -q '%%EOF' || _find "the PDF has no %%EOF marker: it was cut off while being written"
      _rows="$(grep -a -c '/Type[[:space:]]*/Page[^s]' "$_f" 2>/dev/null || echo 0)" ;;
  esac

  if [ -n "$_want_rows" ] && [ -n "$_rows" ] && [ "$_rows" != "$_want_rows" ]; then
    _find "the export has $_rows row(s); the screen showed $_want_rows"
  fi
  echo "kind=$_kind rows=${_rows:-?} size=$_size"
  [ -n "$_cols" ] && echo "columns=$_cols"
  cat "$_fx"
  if [ -s "$_fx" ]; then rm -f "$_fx"; return 1; fi
  rm -f "$_fx"; return 0
}
