#!/usr/bin/env python
"""tf-outbox.py -- read a sandbox mail outbox (Mailpit or MailHog).

Called by `tf.sh notifications`. Standard library only, like tf-xlsx.py and
tf-contract.py. A machine without Python gets UNJUDGED notification cases,
never failures.

  list <base_url> [since_epoch]     messages, newest last:
                                    id<TAB>epoch<TAB>to<TAB>subject<TAB>from
  get  <base_url> <id> <out_prefix> writes <out_prefix>.txt (text part),
                                    <out_prefix>.html and <out_prefix>.hdr

Only ever talks to the outbox the caller names; the engine refuses a
non-local one before calling this. Exit 0 on success, 2 when the outbox
cannot be reached or is neither Mailpit nor MailHog.
"""

import datetime
import json
import re
import sys
import urllib.request


def fetch(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


STAMP = re.compile(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?")


def epoch(stamp):
    """Seconds since the epoch for an RFC 3339 stamp. Mailpit sends
    nanosecond fractions, which datetime.fromisoformat rejects on older
    Pythons, so the fraction is dropped rather than parsed."""
    m = STAMP.match(stamp or "")
    if not m:
        return 0
    t = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
    tz = m.group(2) or "Z"
    off = 0
    if tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        hh, mm = tz[1:3], tz[-2:]
        off = sign * (int(hh) * 3600 + int(mm) * 60)
    return int(t.replace(tzinfo=datetime.timezone.utc).timestamp()) - off


def addrs(v):
    out = []
    for a in v or []:
        if isinstance(a, dict):
            out.append(a.get("Address") or "%s@%s" % (a.get("Mailbox", ""), a.get("Domain", "")))
        else:
            out.append(str(a))
    return ",".join(x for x in out if x and x != "@")


def kind(base):
    for probe, name in (("/api/v1/messages?limit=1", "mailpit"), ("/api/v2/messages?limit=1", "mailhog")):
        try:
            fetch(base + probe)
            return name
        except Exception:
            continue
    return None


def clean(s):
    return (s or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")


def list_messages(base, since):
    k = kind(base)
    if k is None:
        print("outbox %s answers neither the Mailpit nor the MailHog API" % base)
        return 2
    rows = []
    if k == "mailpit":
        data = fetch(base + "/api/v1/messages?limit=500")
        for m in data.get("messages", []):
            rows.append((m.get("ID"), epoch(m.get("Created")), addrs(m.get("To")),
                         m.get("Subject", ""), addrs([m.get("From")] if m.get("From") else [])))
    else:
        data = fetch(base + "/api/v2/messages?limit=500")
        for m in data.get("items", []):
            h = (m.get("Content") or {}).get("Headers") or {}
            rows.append((m.get("ID"), epoch(m.get("Created")), ",".join(h.get("To", [])),
                         (h.get("Subject") or [""])[0], ",".join(h.get("From", []))))
    for r in sorted(rows, key=lambda r: r[1]):
        if r[1] >= since:
            print("\t".join(clean(str(x)) for x in r))
    return 0


def get_message(base, mid, prefix):
    k = kind(base)
    if k is None:
        print("outbox %s answers neither the Mailpit nor the MailHog API" % base)
        return 2
    text = html = ""
    hdr = {}
    if k == "mailpit":
        m = fetch(base + "/api/v1/message/" + mid)
        text, html = m.get("Text", ""), m.get("HTML", "")
        try:
            hdr = fetch(base + "/api/v1/message/" + mid + "/headers")
        except Exception:
            hdr = {}
    else:
        m = fetch(base + "/api/v1/messages/" + mid)
        content = m.get("Content") or {}
        hdr = content.get("Headers") or {}
        parts = (m.get("MIME") or {}).get("Parts") or []
        for p in parts:
            ph = (p.get("Headers") or {}).get("Content-Type", [""])[0]
            if "text/html" in ph:
                html = p.get("Body", "")
            elif "text/plain" in ph:
                text = p.get("Body", "")
        if not parts:
            body = content.get("Body", "")
            if "text/html" in (hdr.get("Content-Type", [""])[0]):
                html = body
            else:
                text = body
    with open(prefix + ".txt", "w", encoding="utf-8") as f:
        f.write(text or "")
    with open(prefix + ".html", "w", encoding="utf-8") as f:
        f.write(html or "")
    with open(prefix + ".hdr", "w", encoding="utf-8") as f:
        for k2, v in sorted(hdr.items()):
            for one in (v if isinstance(v, list) else [v]):
                f.write("%s: %s\n" % (k2, clean(str(one))))
    return 0


def main(argv):
    try:
        if len(argv) >= 3 and argv[1] == "list":
            return list_messages(argv[2].rstrip("/"), int(argv[3]) if len(argv) > 3 else 0)
        if len(argv) >= 5 and argv[1] == "get":
            return get_message(argv[2].rstrip("/"), argv[3], argv[4])
    except Exception as e:  # unreachable outbox, bad JSON
        print("outbox error: %s" % e)
        return 2
    print(__doc__.strip().splitlines()[0])
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
