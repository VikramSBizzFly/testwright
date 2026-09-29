# shellcheck shell=sh
# lib/contract.sh -- contract: live API responses against their OpenAPI spec
#
# Sourced by scripts/tf.sh; defines functions only. See tf.sh for the paths
# and schema variables these rely on.
#
# An `api` case asks "did it answer 200?". This asks "is what it answered
# still what the contract promises?" -- a renamed field, a number turned into
# a string, a required field that went missing, a status code nobody
# documented. That drift breaks every client of the API while every status
# check stays green.
#
# The schema check itself is scripts/tf-contract.py, standard library only.
# Without an interpreter the cases are UNJUDGED, never failed.
#
#   CONTRACT-NNN  one per GET operation in the spec: the live response's
#                 status is documented, and its JSON body matches the schema
#
# The spec: `contract.spec` in framework.json (a path in the project), else
# the first openapi.json / swagger.json found in the project, else one the app
# serves at a well-known URL -- saved to tests/.cache/contract.spec.json.

cmd_contract() {
  _k_sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$_k_sub" in
    cases) _contract_cases "$@" ;;
    run)   _chk_run contract contract "$@" ;;
    *) die "contract: expected 'cases' or 'run [--only <ids>]'" ;;
  esac
}

_contract_py() {
  CT_PY="$(tf_python 2>/dev/null || true)"
  CT_SCRIPT="$(dirname "$(tf_xlsx_script)")/tf-contract.py"
  [ -n "$CT_PY" ] && [ -f "$CT_SCRIPT" ]
}

# Find the spec and copy it into the cache. Prints its cached path.
_contract_spec() {
  _dst="$CACHE/contract.spec.json"; mkdir -p "$CACHE"
  _s="$(json_get "$FRAMEWORK" contract.spec 2>/dev/null || true)"
  if [ -z "$_s" ]; then
    _s="$(find . -path ./node_modules -prune -o -path "./$TESTS_DIR" -prune -o -path ./.git -prune -o \
            -type f \( -name openapi.json -o -name swagger.json -o -name 'openapi.*.json' -o -name api-docs.json \) -print 2>/dev/null |
          head -1)"
  fi
  if [ -n "$_s" ] && [ -f "$_s" ]; then
    cp "$_s" "$_dst"; echo "$_dst"; return 0
  fi
  # Served by the app: FastAPI, springdoc, Swashbuckle, express-openapi.
  assert_target_allowed
  base="$(json_get "$CREDS" base_url | sed 's#/*$##')"
  for _u in /openapi.json /swagger.json /v3/api-docs /api-docs /swagger/v1/swagger.json /api/openapi.json /docs/openapi.json; do
    _c="$(curl -s -o "$_dst" -w '%{http_code}' --max-time 20 "$base$_u" 2>/dev/null)"
    if [ "$_c" = 200 ] && grep -qE '"(openapi|swagger)"[[:space:]]*:' "$_dst"; then
      echo "$_dst"; return 0
    fi
  done
  rm -f "$_dst"
  return 1
}

_contract_cases() {
  _contract_py || die "contract cases: needs python3 (standard library only) to read the spec"
  _spec="$(_contract_spec)" || die "contract cases: no OpenAPI/Swagger JSON found -- set \"contract\": { \"spec\": \"path/to/openapi.json\" } in $FRAMEWORK"
  # Python on Windows ends its lines with \r\n; the last field would keep the \r.
  "$CT_PY" "$CT_SCRIPT" ops "$_spec" > "$CACHE/.ct-ops.$$" || { cat "$CACHE/.ct-ops.$$" >&2; rm -f "$CACHE/.ct-ops.$$"; die "contract cases: cannot read $_spec"; }
  tr -d '\r' < "$CACHE/.ct-ops.$$" > "$CACHE/.ct-ops.$$.n" && mv "$CACHE/.ct-ops.$$.n" "$CACHE/.ct-ops.$$"
  _first="$(json_keys "$CREDS" roles 2>/dev/null | head -1)"
  # Concrete routes the suite already requests, to fill a {param} path with.
  cmd_select --type api --cols route --format plain 2>/dev/null | sort -u > "$CACHE/.ct-routes.$$"
  _chk_header
  _n=0; _nparam=0
  while IFS="$(printf '\t')" read -r _tpl _sec _pre; do
    [ -n "$_tpl" ] || continue
    _route="$_pre$_tpl"
    case "$_tpl" in
      *'{'*)
        _rx="^$(printf '%s' "$_pre$_tpl" | sed -e 's/[.[\*^$]/\\&/g' -e 's/{[^}]*}/[^\/]+/g')/?$"
        _route="$(grep -E -- "$_rx" "$CACHE/.ct-routes.$$" | head -1)"
        [ -n "$_route" ] || { _nparam=$((_nparam + 1)); continue; } ;;
    esac
    _who=nobody; [ "$_sec" = 1 ] && [ -n "$_first" ] && _who="$_first"
    _n=$((_n + 1))
    _chk_row "$(printf 'CONTRACT-%03d' "$_n")" "API contract" "GET $_tpl still answers what the contract promises" \
      "Contract: GET $_tpl" "$_who" "GET $_route | validate the status and JSON body against the spec" \
      "The status is documented; the body matches the response schema (types, required fields, enums)" \
      api "$_route" contract
  done < "$CACHE/.ct-ops.$$"
  rm -f "$CACHE/.ct-ops.$$" "$CACHE/.ct-routes.$$"
  echo "contract: $_n case(s) from $_spec; $_nparam parameterised path(s) skipped (no api case gives a real value)" >&2
}

_contract_init() {
  CT_STRICT=""; [ "$(json_get "$FRAMEWORK" contract.strict 2>/dev/null)" = true ] && CT_STRICT=--strict
  CT_OK=1; CT_WHY=""
  if ! _contract_py; then CT_OK=0; CT_WHY="no python: the schema check needs python3 (standard library only)"
  elif [ ! -f "$CACHE/contract.spec.json" ] && ! _contract_spec >/dev/null 2>&1; then
    CT_OK=0; CT_WHY="no OpenAPI/Swagger JSON found (set contract.spec)"
  fi
  CHK_SKIP_REASON="behind a login with no session"
}

_contract_case() { # <id> <route> <role>
  [ "$CT_OK" = 1 ] || { CHK_VERDICT=UNJUDGED; CHK_EXPECTED="$CT_WHY"; CHK_NOTE="-"; return; }
  _r="$(_api_role "$3")"
  if [ -n "$_r" ] && [ ! -f "$TESTS_DIR/.auth/$_r.cookies" ]; then
    CHK_VERDICT=UNJUDGED; CHK_EXPECTED="no session for $_r: run /testwright:setup"; CHK_NOTE="-"; return
  fi
  _chk_get "$2" "$3" -H 'Accept: application/json'
  case "$CHK_CODE" in
    000) CHK_VERDICT=ERROR; CHK_NOTE="no response"; return ;;
    401|403) CHK_VERDICT=UNJUDGED; CHK_EXPECTED="refused (HTTP $CHK_CODE): a refusal says nothing about the contract"; CHK_NOTE="-"; return ;;
  esac
  _chk_body > "$CHK_TMP.json"
  # shellcheck disable=SC2086
  # The route goes in a file, not argv or the environment: Git Bash rewrites
  # anything that looks like a POSIX path (/api/items) into a Windows one
  # before a native program sees it -- right for the file paths, wrong for a
  # route.
  printf '%s' "$2" > "$CHK_TMP.route"
  "$CT_PY" "$CT_SCRIPT" check "$CACHE/contract.spec.json" GET "@$CHK_TMP.route" "$CHK_CODE" "$CHK_TMP.json" $CT_STRICT > "$CHK_TMP.ct" 2>/dev/null
  _rc=$?
  tr -d '\r' < "$CHK_TMP.ct" >> "$CHK_TMP.find"
  case $_rc in 0) ;; *) CHK_VERDICT=ERROR; CHK_NOTE="the spec could not be read"; : > "$CHK_TMP.find"; return ;; esac
  CHK_NOTE="HTTP $CHK_CODE matches the contract"
  return 0
}
