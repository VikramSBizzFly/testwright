# shellcheck shell=sh
# lib/seed.sh -- preconditions: the data the suite assumes exists
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# A case's Preconditions say two things: who is logged in, which the engine
# already reads, and what data must exist -- "at least one invoice exists",
# "an order in status shipped". Test Data adds volumes: "at least 1,000
# orders". Nothing checked those, so a case whose data was missing failed
# as if the app were broken. This lists every data need once, with the cases
# that depend on it, for the `test-data-seeder` agent to plan from.
#
# preconditions [--status <list>] [--format plain|tsv]
#   tsv columns: need, cases (count), ids (up to 8), source (pre|data)

cmd_preconditions() {
  need_csv
  _st=""; _fmt=plain
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) _st="$2"; shift 2 ;;
      --format) _fmt="$2"; shift 2 ;;
      *) die "preconditions: unexpected argument '$1'" ;;
    esac
  done
  cmd_select --cols id,preconditions,data,status --format csv 2>/dev/null |
    awk -v st="$_st" -v fmt="$_fmt" "$AWKLIB"'
      function norm(s) { gsub(/^[ \t.;,]+|[ \t.;,]+$/, "", s); gsub(/[ \t]+/, " ", s); return s }
      function add(need, id, src,   k) {
        need = norm(need); if (need == "") return
        k = tolower(need)
        if (!(k in N)) { ORD[++n] = k; TXT[k] = need; SRC[k] = src }
        N[k]++; if (N[k] <= 8) IDS[k] = IDS[k] (IDS[k] == "" ? "" : " ") id
      }
      NR == 1 { next }
      { csvsplit($0, F)
        if (st != "" && index("," st ",", "," F[4] ",") == 0) next
        m = split(F[2], P, /;/)
        for (i = 1; i <= m; i++) {
          p = norm(P[i]); lp = tolower(p)
          # Who is logged in is the engine'"'"'s job, not data.
          if (lp ~ /^(not logged in|logged out|anonymous|logged in as [a-z0-9 _-]+|signed in as [a-z0-9 _-]+)$/) continue
          if (p != "") add(p, F[1], "pre")
        }
        # Test Data that states a volume or a state the app must already hold.
        if (tolower(F[3]) ~ /(at least|more than|over|[0-9][0-9,]* (rows|records|items|orders|users|invoices|products|entries))/) add(F[3], F[1], "data")
      }
      END {
        for (i = 1; i <= n; i++) { k = ORD[i]
          if (fmt == "tsv") printf "%s\t%d\t%s\t%s\n", TXT[k], N[k], IDS[k], SRC[k]
          else printf "%3d  %-60s %s\n", N[k], substr(TXT[k], 1, 60), IDS[k] (N[k] > 8 ? " ..." : "")
        }
        if (n == 0 && fmt != "tsv") print "no data preconditions: every case needs only a login (or nothing)"
      }'
}
