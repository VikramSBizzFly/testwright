# shellcheck shell=sh
# lib/insight.sh -- trend, release, trace, dupes: what the suite says over time
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# Four read-only reports over what the engine already stores, at zero tokens.
# The agents that sit on them (trend-reporter, release-gate,
# requirements-tracer, suite-gardener) add judgement; the numbers are here.
#
#   trend [N] [--family F] [--tsv]   the last N runs: pass rate per family
#   release [--json]                  GO / NO-GO against framework.json "release"
#   trace [--gaps] [--tsv]            requirements with no, failing or passing cases
#   dupes                             cases that probably test the same thing

# ===================================================================== trend

cmd_trend() {
  _n=10; _fam=""; _tsv=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --family) _fam="$2"; shift 2 ;;
      --tsv) _tsv=1; shift ;;
      [0-9]*) _n="$1"; shift ;;
      *) die "trend: unexpected argument '$1'" ;;
    esac
  done
  ls -1t "$RESULTS"/run-*.csv 2>/dev/null | head -n "$_n" > "$CACHE/.trend.$$" || true
  [ -s "$CACHE/.trend.$$" ] || { rm -f "$CACHE/.trend.$$"; echo "trend: no runs in $RESULTS yet"; return 0; }
  # Oldest first, so the table reads forward in time.
  awk '{ L[NR] = $0 } END { for (i = NR; i >= 1; i--) print L[i] }' "$CACHE/.trend.$$" |
  while IFS= read -r _f; do
    _meta="${_f%.csv}.meta"; _dur=""
    [ -f "$_meta" ] && _dur="$(sed -n 's/^duration_ms=//p' "$_meta")"
    awk -F, -v f="$_f" -v dur="${_dur:-0}" -v fam="$_fam" 'NR > 1 && NF >= 7 {
        t = ($2 == "" ? "page" : $2); T[t]++; V[$7]++; n++ }
      END {
        # A run is named by the family most of its rows belong to.
        best = ""; for (t in T) if (best == "" || T[t] > T[best]) best = t
        if (fam != "" && best != fam) exit
        stamp = f; sub(/.*run-/, "", stamp); sub(/\.csv$/, "", stamp)
        judged = V["PASS"] + V["FAIL"] + V["ERROR"]
        pct = judged > 0 ? int(V["PASS"] * 100 / judged) : 0
        printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", stamp, best, n, V["PASS"], V["FAIL"], V["ERROR"], V["UNJUDGED"], pct, dur }' "$_f"
  done > "$CACHE/.trend-rows.$$"
  rm -f "$CACHE/.trend.$$"
  if [ "$_tsv" = 1 ]; then
    printf 'run\tfamily\tcases\tpass\tfail\terror\tunjudged\tpass_pct\tduration_ms\n'
    cat "$CACHE/.trend-rows.$$"
  else
    awk -F '\t' 'BEGIN {
        printf "%-15s %-9s %6s %5s %5s %5s %5s %6s %9s\n", "RUN", "FAMILY", "CASES", "PASS", "FAIL", "ERR", "UNJ", "PASS%", "TIME"
        split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", BAR, " ") }
      { printf "%-15s %-9s %6d %5d %5d %5d %5d %5d%% %8.1fs\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 / 1000
        S[$2] = S[$2] BAR[int($8 * 7 / 100) + 1]; P[$2] = $8; if (!($2 in F)) F[$2] = $8 }
      END { if (NR == 0) { print "trend: no runs match"; exit }
        print ""; for (k in S) printf "%-9s %s  %d%% -> %d%%\n", k, S[k], F[k], P[k] }' "$CACHE/.trend-rows.$$"
  fi
  rm -f "$CACHE/.trend-rows.$$"
}

# =================================================================== release

# release [--json] -- is this build releasable, by the team's own criteria?
#
# The facts come from the store (every case's current status) and the bug
# sheet, not from one results file: runs are per family now, so the latest
# file is one family's view. Criteria live in framework.json:
#
#   "release": { "min_pass_rate": 95, "max_open_critical": 0, "max_open_high": 0,
#                "require_security_clean": true, "require_smoke_pass": true,
#                "max_age_hours": 24 }
#
# Exit 0 GO, 1 NO-GO. Waivers are a person's decision, never this command's.
cmd_release() {
  need_csv
  _json=0; [ "${1:-}" = "--json" ] && _json=1
  _rn() { _chk_num "release.$1" "$2"; }
  _min="$(_rn min_pass_rate 95)"; _crit="$(_rn max_open_critical 0)"; _high="$(_rn max_open_high 0)"
  _age="$(_rn max_age_hours 24)"
  _sec="$(json_get "$FRAMEWORK" release.require_security_clean 2>/dev/null || echo true)"
  _smoke="$(json_get "$FRAMEWORK" release.require_smoke_pass 2>/dev/null || echo true)"

  _latest="$(ls -1t "$RESULTS"/run-*.csv 2>/dev/null | head -1)"
  _hours=-1
  if [ -n "$_latest" ]; then
    _now="$(date +%s)"; _mt="$(date -r "$_latest" +%s 2>/dev/null || stat -c %Y "$_latest" 2>/dev/null || echo "$_now")"
    _hours=$(( (_now - _mt) / 3600 ))
  fi
  _bugs="$BUGS"; [ -f "$_bugs" ] || _bugs=/dev/null

  joined | awk -v min="$_min" -v crit="$_crit" -v high="$_high" -v age="$_age" -v hours="$_hours" \
      -v sec="$_sec" -v smoke="$_smoke" -v json="$_json" -v bugs="$_bugs" "$AWKLIB"'
    BEGIN {
      while ((getline l < bugs) > 0) {
        if (++bn == 1) { nb = csvsplit(l, BH); for (i = 1; i <= nb; i++) BI[BH[i]] = i; continue }
        csvsplit(l, B); st = B[BI["Status(QA)"]]
        if (st == "Open" || st == "In Progress" || st == "Reopened" || st == "Retest") {
          OPEN[B[BI["Severity"]]]++; openall++ }
      }
    }
    NR == 1 { hdrmap($0, H); next }
    { csvsplit($0, F); id = F[idcol(H)]; s = F[H["Status"]]; t = "," F[H["tags"]] ","
      if (s == "" ) s = "Not Run"
      ST[s]++; total++
      if (s == "Pass" || s == "Fail" || s == "Flaky") judged++
      if ((id ~ /^(AUTH|PERM)-/ || index(t, ",security,")) && s == "Fail") { secf++; if (secf <= 3) SEC = SEC " " id }
      if (index(t, ",smoke,")) { sm++; if (s != "Pass") { smf++; if (smf <= 3) SMK = SMK " " id " (" s ")" } }
    }
    function line(ok, text) { if (ok == 1) { mark = "PASS" } else if (ok == 0) { mark = "FAIL"; nogo++ } else mark = "info"
      L[++nl] = sprintf("  %-4s  %s", mark, text); JS = JS (JS == "" ? "" : ",") sprintf("{\"ok\":\"%s\",\"check\":\"%s\"}", mark, text) }
    END {
      pct = judged > 0 ? int(ST["Pass"] * 1000 / judged) / 10 : 0
      line(judged > 0 && pct >= min, sprintf("pass rate %.1f%% of %d judged cases (needs >= %d%%)", pct, judged, min))
      if (sec == "true") line(secf == 0, (secf == 0 ? "no failing security case" : secf " failing security case(s):" SEC))
      if (smoke == "true") line(sm > 0 && smf == 0, (sm == 0 ? "no smoke-tagged cases to prove the basics" : (smf == 0 ? "all " sm " smoke cases pass" : smf " of " sm " smoke cases not passing:" SMK)))
      line(OPEN["Critical"] + 0 <= crit, sprintf("%d open Critical bug(s) (allowed %d)", OPEN["Critical"], crit))
      line(OPEN["High"] + 0 <= high, sprintf("%d open High bug(s) (allowed %d)", OPEN["High"], high))
      line(hours >= 0 && hours <= age, (hours < 0 ? "no run on record" : sprintf("last run %dh ago (allowed %dh)", hours, age)))
      line(2, sprintf("%d case(s) Blocked, %d Not Run, %d Skipped, %d Flaky -- not in the pass rate", ST["Blocked"], ST["Not Run"], ST["Skipped"], ST["Flaky"]))
      line(2, sprintf("%d open bug(s) in all: %d Medium, %d Low", openall, OPEN["Medium"], OPEN["Low"]))
      verdict = (nogo > 0) ? "NO-GO" : "GO"
      if (json) { printf "{\"verdict\":\"%s\",\"pass_rate\":%.1f,\"checks\":[%s]}\n", verdict, pct, JS; exit (nogo > 0) }
      printf "RELEASE %s  (%d case(s), %d judged)\n", verdict, total, judged
      for (i = 1; i <= nl; i++) print L[i]
      if (nogo > 0) print "\nA NO-GO is the criteria speaking. Waiving one is a decision for a person to record, not for this command."
      exit (nogo > 0)
    }'
}

# ===================================================================== trace

# trace [--gaps] [--tsv] -- requirements against cases.
#
# tests/requirements.txt, one requirement per line, tab-separated:
#   REQ-ID <TAB> title <TAB> source (file:line or ticket) <TAB> case ids (comma)
# The fourth column is what requirements-tracer mapped. A case also covers a
# requirement when its Test Scenario or Test Description names the id.
cmd_trace() {
  need_csv
  _req="$TESTS_DIR/requirements.txt"
  [ -f "$_req" ] || die "trace: no $_req -- the requirements-tracer agent writes it"
  _gaps=0; _tsv=0
  for _a in "$@"; do case "$_a" in --gaps) _gaps=1 ;; --tsv) _tsv=1 ;; *) die "trace: unexpected argument '$_a'" ;; esac; done
  joined | awk -v req="$_req" -v gaps="$_gaps" -v tsv="$_tsv" "$AWKLIB"'
    BEGIN { FS_ = "\t"
      while ((getline l < req) > 0) {
        if (l ~ /^[ \t]*(#|$)/) continue
        n = split(l, R, "\t"); id = R[1]; if (id == "") continue
        ORD[++nr] = id; TITLE[id] = R[2]; SRC[id] = R[3]
        m = split(R[4], C, /[ ,]+/); for (j = 1; j <= m; j++) if (C[j] != "") MAP[id, C[j]] = 1
      } }
    NR == 1 { hdrmap($0, H); next }
    { csvsplit($0, F); cid = F[idcol(H)]; s = F[H["Status"]]; if (s == "") s = "Not Run"
      CS[cid] = s; txt = F[H["Test Scenario"]] " " F[H["Test Description"]]
      for (i = 1; i <= nr; i++) { r = ORD[i]
        if (MAP[r, cid] || index(" " txt " ", r) && txt ~ ("(^|[^A-Za-z0-9-])" r "([^0-9]|$)")) { COV[r] = COV[r] " " cid; NC[r]++
          if (s == "Fail") NF_[r]++; else if (s == "Pass") NP[r]++; else NO[r]++ } } }
    END {
      if (nr == 0) { print "trace: no requirements in " req; exit }
      for (i = 1; i <= nr; i++) { r = ORD[i]
        st = (NC[r] == 0) ? "UNCOVERED" : (NF_[r] > 0 ? "FAILING" : (NP[r] > 0 ? "PASSING" : "NOT-RUN"))
        CNT[st]++
        if (gaps && st != "UNCOVERED" && st != "FAILING") continue
        if (tsv) printf "%s\t%s\t%s\t%s\t%s\n", r, st, NC[r] + 0, substr(COV[r], 2), TITLE[r]
        else printf "%-10s %-9s %3d  %-44s %s\n", r, st, NC[r], substr(TITLE[r], 1, 44), substr(COV[r], 2, 60) }
      if (!tsv) printf "\n%d requirement(s): %d passing, %d failing, %d not run, %d uncovered\n", nr, CNT["PASSING"], CNT["FAILING"], CNT["NOT-RUN"], CNT["UNCOVERED"]
    }'
}

# ===================================================================== dupes

# dupes -- cases that probably test the same thing. `prune` removes exact
# repeats automatically; this finds the near ones -- same type, route and
# role, and steps plus expectation sharing most of their words -- for the
# suite-gardener to judge. It changes nothing.
cmd_dupes() {
  need_csv
  _min="${1:-0.7}"
  joined | awk -v min="$_min" "$AWKLIB"'
    function words(s, W,   n, i, A, c) { s = tolower(s); gsub(/[^a-z0-9]+/, " ", s)
      n = split(s, A, " "); c = 0
      for (i = 1; i <= n; i++) if (length(A[i]) > 2 && !(A[i] in W)) { W[A[i]] = 1; c++ }
      return c }
    NR == 1 { hdrmap($0, H); next }
    { csvsplit($0, F)
      if (F[H["Status"]] == "Skipped") next
      k = F[H["type"]] "|" F[H["route"]] "|" F[H["role"]]
      g = ++GN[k]; ID[k, g] = F[idcol(H)]
      TXT[k, g] = F[H["Test Case Steps"]] " " F[H["Expected Result"]] }
    END {
      for (k in GN) for (a = 1; a <= GN[k]; a++) for (b = a + 1; b <= GN[k]; b++) {
        delete WA; delete WB
        na = words(TXT[k, a], WA); nb = words(TXT[k, b], WB)
        if (na == 0 || nb == 0) continue
        inter = 0; for (w in WA) if (w in WB) inter++
        j = inter / (na + nb - inter)
        if (j >= min) { split(k, K, "|"); printf "%.2f\t%s\t%s\t%s %s %s\n", j, ID[k, a], ID[k, b], K[1], K[2], (K[3] == "" ? "nobody" : K[3]); found++ } }
      if (!found) print "dupes: none above " min > "/dev/stderr"
    }' | sort -r
}
