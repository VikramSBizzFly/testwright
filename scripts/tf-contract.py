#!/usr/bin/env python
"""tf-contract.py -- does a live API response still match its OpenAPI contract?

Called by `tf.sh contract`. Standard library only, like tf-xlsx.py: json and
re, nothing else. A machine without Python gets UNJUDGED contract cases from
the engine, never failures. If this file needs a dependency, it is wrong.

Reads OpenAPI 3.x and Swagger 2.0 documents in JSON. YAML needs a parser the
standard library does not have, so a YAML spec is reported as unreadable with
a hint to point `contract.spec` at a JSON copy.

  ops   <spec>                                   GET operations, one per line:
                                                 path<TAB>secured<TAB>prefix
  check <spec> <method> <route> <status> <body> [--strict]
                                                 findings, one per line

`check` validates the subset of JSON Schema that response contracts actually
use: $ref, type (and nullable, and 3.1 type lists), required, properties,
additionalProperties, items, enum, allOf, anyOf, oneOf. Formats and numeric
bounds are not checked -- drift in shape is the bug worth catching here.
Extra, undocumented fields are reported only with --strict, or where the
schema says additionalProperties: false.

Exit 0 when it ran (findings or not), 2 when the spec cannot be read.
"""

import json
import re
import sys

MAX_FINDINGS = 20


def load(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
    except OSError as e:
        print("cannot read spec %s: %s" % (path, e))
        sys.exit(2)
    try:
        return json.loads(text)
    except ValueError:
        if re.match(r"\s*(openapi|swagger)\s*:", text):
            print("spec %s is YAML; set contract.spec in tests/framework.json to a JSON copy" % path)
        else:
            print("spec %s is not valid JSON" % path)
        sys.exit(2)


def prefix_of(spec):
    """The path every operation sits under: OpenAPI 3 servers[0], Swagger basePath."""
    if "servers" in spec and spec["servers"]:
        url = spec["servers"][0].get("url", "")
        m = re.match(r"^(?:[a-z]+://[^/]+)?(/[^?#]*)?", url)
        p = (m.group(1) or "") if m else ""
        return p.rstrip("/")
    return (spec.get("basePath") or "").rstrip("/")


def ops(spec):
    glob = bool(spec.get("security"))
    pre = prefix_of(spec)
    for path, item in sorted((spec.get("paths") or {}).items()):
        op = (item or {}).get("get")
        if not isinstance(op, dict):
            continue
        sec = op.get("security", None)
        secured = bool(sec) if sec is not None else glob
        print("%s\t%d\t%s" % (path, 1 if secured else 0, pre))


def match_path(spec, route):
    """The spec path template a concrete route belongs to, or None."""
    pre = prefix_of(spec)
    r = route.split("?", 1)[0]
    if pre and r.startswith(pre):
        r = r[len(pre):] or "/"
    best = None
    for tpl in (spec.get("paths") or {}):
        rx = "^" + re.sub(r"\\\{[^/]+?\\\}", "[^/]+", re.escape(tpl)) + "/?$"
        if re.match(rx, r):
            # A literal segment beats a parameter: /users/me over /users/{id}.
            score = tpl.count("{")
            if best is None or score < best[0]:
                best = (score, tpl)
    return best[1] if best else None


class Checker:
    def __init__(self, spec, strict):
        self.spec = spec
        self.strict = strict
        self.found = []

    def ref(self, s, depth=0):
        while isinstance(s, dict) and "$ref" in s and depth < 30:
            ptr = s["$ref"]
            if not ptr.startswith("#/"):
                return {}
            node = self.spec
            for part in ptr[2:].split("/"):
                part = part.replace("~1", "/").replace("~0", "~")
                node = node.get(part, {}) if isinstance(node, dict) else {}
            s = node
            depth += 1
        return s if isinstance(s, dict) else {}

    def add(self, where, msg):
        if len(self.found) < MAX_FINDINGS:
            self.found.append("%s: %s" % (where or "$", msg))

    @staticmethod
    def type_of(v):
        if v is None:
            return "null"
        if isinstance(v, bool):
            return "boolean"
        if isinstance(v, int):
            return "integer"
        if isinstance(v, float):
            return "number"
        if isinstance(v, str):
            return "string"
        if isinstance(v, list):
            return "array"
        return "object"

    def ok(self, s, v, where):
        """Validate quietly; True when v satisfies s."""
        saved = self.found
        self.found = []
        self.validate(s, v, where)
        good = not self.found
        self.found = saved
        return good

    def validate(self, s, v, where):
        s = self.ref(s)
        if not s:
            return
        for sub in s.get("allOf", []):
            self.validate(sub, v, where)
        for key in ("anyOf", "oneOf"):
            if key in s:
                if not any(self.ok(sub, v, where) for sub in s[key]):
                    self.add(where, "matches none of the %s alternatives" % key)
                return
        want = s.get("type")
        kinds = want if isinstance(want, list) else ([want] if want else [])
        got = self.type_of(v)
        if got == "null":
            if s.get("nullable") or s.get("x-nullable") or "null" in kinds or not kinds:
                return
            self.add(where, "is null, but the contract does not allow null")
            return
        if kinds:
            fits = got in kinds or (got == "integer" and "number" in kinds)
            if not fits:
                self.add(where, "is %s, contract says %s" % (got, "/".join(kinds)))
                return
        if "enum" in s and v not in s["enum"]:
            self.add(where, "is %r, not one of %s" % (v, s["enum"][:10]))
        if got == "object":
            props = s.get("properties", {}) or {}
            for req in s.get("required", []) or []:
                if req not in v:
                    self.add(where, "is missing required field '%s'" % req)
            for k, val in v.items():
                if k in props:
                    self.validate(props[k], val, "%s.%s" % (where or "$", k))
                else:
                    ap = s.get("additionalProperties", True)
                    if ap is False:
                        self.add(where, "has field '%s', which the contract forbids" % k)
                    elif isinstance(ap, dict):
                        self.validate(ap, val, "%s.%s" % (where or "$", k))
                    elif self.strict and props:
                        self.add(where, "has undocumented field '%s'" % k)
        if got == "array" and "items" in s:
            for i, item in enumerate(v[:200]):
                self.validate(s["items"], item, "%s[%d]" % (where or "$", i))
                if len(self.found) >= MAX_FINDINGS:
                    break


def response_schema(spec, op, status):
    responses = op.get("responses") or {}
    resp = responses.get(str(status)) or responses.get("%sXX" % str(status)[0]) \
        or responses.get("%sxx" % str(status)[0]) or responses.get("default")
    if resp is None:
        return None, "HTTP %s is not a documented response (documented: %s)" % (
            status, ", ".join(sorted(responses)) or "none")
    if "$ref" in resp:
        resp = Checker(spec, False).ref(resp)
    if "schema" in resp:                       # Swagger 2
        return resp["schema"], None
    content = resp.get("content") or {}
    for ctype, media in content.items():
        if "json" in ctype:
            return (media or {}).get("schema"), None
    return None, None                          # documented, no JSON body to check


def check(spec, method, route, status, body_path, strict):
    tpl = match_path(spec, route)
    if tpl is None:
        print("%s is not in the contract at all" % route)
        return
    op = (spec["paths"][tpl] or {}).get(method.lower())
    if not isinstance(op, dict):
        print("%s %s is not in the contract (the path exists without that method)" % (method.upper(), tpl))
        return
    schema, err = response_schema(spec, op, status)
    if err:
        print(err)
        return
    if schema is None:
        return
    try:
        with open(body_path, encoding="utf-8-sig") as f:
            raw = f.read()
    except OSError:
        raw = ""
    try:
        body = json.loads(raw) if raw.strip() else None
    except ValueError:
        print("the response is not JSON, but the contract describes a JSON body")
        return
    c = Checker(spec, strict)
    c.validate(schema, body, "$")
    for line in c.found:
        print(line)
    if len(c.found) >= MAX_FINDINGS:
        print("... stopped after %d differences" % MAX_FINDINGS)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("ops", "check"):
        print(__doc__.strip().splitlines()[0])
        return 1
    spec = load(argv[2])
    if not isinstance(spec, dict) or "paths" not in spec:
        print("spec %s has no paths" % argv[2])
        return 2
    if argv[1] == "ops":
        ops(spec)
        return 0
    if len(argv) < 7:
        print("usage: check <spec> <method> <route> <status> <body> [--strict]")
        return 1
    # `@<file>`: read the route from a file. Git Bash rewrites a /path in argv
    # or the environment into a Windows path on its way to a native program.
    route = argv[4]
    if route.startswith("@"):
        with open(route[1:], encoding="utf-8") as f:
            route = f.read().strip()
    check(spec, argv[3], route, argv[5], argv[6], "--strict" in argv[7:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
