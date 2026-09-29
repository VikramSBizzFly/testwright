"""A tiny broken web app, for trying the test framework on.

It has a login, two users with different permissions, and TWO DELIBERATE BUGS
for the test framework to find on its own:

  /payroll   no permission check at all - anybody can read the salaries
  /reports   refuses you correctly, but says so with HTTP 200

Both pages return HTTP 200 to a logged-out visitor. One is a serious leak and
the other is working exactly as intended. A test that only reads status codes
cannot tell them apart, so it must get one of them wrong. Reading the actual
page is the only way to know which is which -- that is why this framework
opens a real browser.

Run it with:   python example/demo-app.py
Then open:     http://127.0.0.1:8731

Logins:  a@x.com / pw1   (admin)
         u@x.com / pw2   (normal user)

For `/testwright:run --seo` it also has one page a search engine would
mark down on purpose -- /about has no meta description and two h1s -- and
one page, /app, that only fills itself in with JavaScript, so its raw HTML
cannot be judged without a browser.

For `/testwright:run --perf` it has four slow spots, one per kind of check:

  /slow             takes 1.5 s before the first byte
  /heavy            1.5 MB uncompressed image with no size (layout shift), a
                    render-blocking script, a long task, no cache headers
  /api/catalog      5,000 rows, no paging, one lookup per row (an N+1)
  /api/flaky-load   fine alone, fails once more than three requests overlap
                    (`--perf --load` finds it)

For `--headers`, `--links` and `--contract`:

  /                 the one page with every security header, done right
  every other page  no CSP, no framing protection; and the Server header
                    names the Python version on every response
  the login cookie  sid is neither HttpOnly nor SameSite
  /api/profile      trusts any Origin with credentials (CORS), and drops the
                    `created` field its contract in /openapi.json requires
  /about            links to /team, which does not exist, and to #contact,
                    which is not on the page

For `--privacy`, `--data` and `--seed`:

  /api/users        (admin) serialises the whole user row, password_hash included
  /account          (signed in) a change-password form that submits by GET,
                    and no Cache-Control on a personal page
  /about            an email address in an HTML comment, and a tracker script
                    that loads before anyone has consented
  /api/orders/<id>  orders move pending -> paid -> shipped -> delivered, but
                    POST /api/orders/<id>/cancel cancels a shipped order too
  /api/notes        POST saves a note, and silently keeps only the first 20
                    characters of its text

For `--content`, `--i18n`, `--notifications`, `--resilience` and `--memory`:

  /welcome          "Hello, {{ user.name }}", "undefined new messages", lorem
                    ipsum, a raw i18n key and garbled "CafÃ©"; ?lang=de has a
                    missing translation and a German label clipped by a
                    fixed-width button
  /app              loads /api/feed with no error handling: when the API
                    fails, the spinner spins forever; and every route change
                    (#/a, #/b) starts a timer and keeps 1 MB it never frees
  password reset    POST /api/password-reset "emails" a reset link that 404s,
                    with the new password in clear and no plain-text part.
                    The demo serves a Mailpit-compatible outbox at /mailpit, so
                    set "notifications": { "outbox": "http://127.0.0.1:8731/mailpit" }

You only need Python for THIS demo app. The test framework itself does not
need Python, or Node, or anything else.
"""

import hashlib
import hmac
import http.server
import json
import threading
import time
import urllib.parse
import uuid

SESSIONS = {}
WEBHOOK_SECRET = b"whsec_demo"        # credentials.json "secrets": {"webhook": ...}
POST_ONLY = {"/api/items", "/api/logout", "/api/webhook", "/api/2fa"}

# Orders and the moves between their states. `ship` checks this table;
# `cancel` forgets to -- the illegal transition state-machine-mapper finds.
ORDERS = {1: "pending", 2: "paid", 3: "shipped", 4: "delivered"}
TRANSITIONS = {
    "pending": {"paid", "cancelled"},
    "paid": {"shipped", "cancelled"},
    "shipped": {"delivered"},
    "delivered": set(),
    "cancelled": set(),
}
NOTES = []                            # {"id", "title", "text"}
NOTE_TEXT_LIMIT = 20                  # THE DATA BUG: the column is too short
OUTBOX = []                           # what the demo "emails", read at /mailpit
FEED_FAILS = [False]                  # flip with POST /api/feed/fail to test resilience

# Every content bug at once, and a German version with i18n bugs of its own.
WELCOME_EN = """<!doctype html><html lang=en><head><meta charset=utf-8><title>Welcome</title></head>
<body><h1>Hello, {{ user.name }}</h1>
<p>You have undefined new messages.</p>
<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>
<p>See today's CafÃ© menu.</p>
<button>welcome.cta.label</button></body></html>"""
WELCOME_DE = """<!doctype html><html lang=de><head><meta charset=utf-8><title>Willkommen</title></head>
<body><h1>Willkommen zurück</h1>
<p>[missing: de.welcome.footer]</p>
<button style="width:90px;white-space:nowrap;overflow:hidden">Benachrichtigungseinstellungen</button>
</body></html>"""

# A tiny single-page app. The feed has no error handling and each route
# change leaks: the two faults resilience-prober and leak-hunter find.
APP_JS = r"""
document.getElementById('root').innerHTML = '<h1>App</h1><nav><a href="#/a">A</a> <a href="#/b">B</a></nav><div id=feed>Loading...</div>';
fetch('/api/feed').then(function (r) { return r.json(); }).then(function (items) {
  document.getElementById('feed').textContent = items.length + ' items';
});
window.__cache = window.__cache || [];
window.addEventListener('hashchange', function () {
  window.__cache.push(new Array(131072).fill(location.hash));      // ~1 MB, never freed
  setInterval(function () { return location.hash; }, 1000);          // never cleared
});
"""
TWOFA_FAILS = {}                      # session id -> wrong codes so far
USERS = {"a@x.com": ("pw1", "admin"), "u@x.com": ("pw2", "user")}

LOGIN_PAGE = """<!doctype html><title>Login</title>
<h1>Demo app</h1>
<form method=post action=/login>
  <input type=hidden name=_csrf value=tok123>
  <p><input name=email placeholder="email"></p>
  <p><input name=password type=password placeholder="password"></p>
  <button type=submit>Sign in</button>
</form>
<p>Try a@x.com / pw1 (admin) or u@x.com / pw2 (user)</p>"""

# The canonical and og:image name the production host, as a real site's do. The
# SEO checks fetch them by path on the host under test instead.
SITE = "https://demo.example.com"
HEAD = f"""<meta charset=utf-8>
<meta name=viewport content="width=device-width, initial-scale=1">
<meta property="og:title" content="{{title}}">
<meta property="og:description" content="{{desc}}">
<meta property="og:image" content="{SITE}/og.png">
<link rel=canonical href="{SITE}{{path}}">"""

HOME_PAGE = """<!doctype html><html lang=en><head>
<title>Demo app - a small app for trying testwright</title>
<meta name=description content="A tiny web app with a login, two roles and a couple of deliberate bugs, for trying the testwright test framework.">
""" + HEAD.format(title="Demo app", desc="A tiny web app for trying testwright.", path="/") + """
<script type="application/ld+json">{"@context": "https://schema.org", "@type": "Organization", "name": "Demo app", "url": "https://demo.example.com/"}</script>
</head><body><h1>Demo app</h1><a href=/login>Log in</a> <a href=/about>About</a>
<a href=/privacy>Privacy policy</a></body></html>"""

PRIVACY_PAGE = """<!doctype html><html lang=en><title>Privacy policy</title>
<h1>Privacy policy</h1><p>We keep only what we need to run the demo.</p></html>"""

# A signed-in page with two privacy faults: the password form submits by GET,
# so the new password lands in the URL, and nothing stops a shared cache.
ACCOUNT_PAGE = """<!doctype html><html lang=en><title>Your account</title>
<h1>Your account</h1>
<form action=/account method=get>
  <p><input name=current type=password placeholder="current password"></p>
  <p><input name=new type=password placeholder="new password"></p>
  <button>Change password</button>
</form></html>"""

# Deliberately flawed for the SEO pass: no meta description, two h1s.
ABOUT_PAGE = """<!doctype html><html lang=en><head>
<title>About the demo app and its bugs</title>
""" + HEAD.format(title="About", desc="About the demo app.", path="/about") + """
</head><body><h1>About</h1><h1>Why it is broken</h1>
<p>This app exists to be tested.</p>
<p><a href=/>Home</a> <a href=/team>Meet the team</a> <a href=#contact>Contact us</a></p>
<!-- questions about this page: dev-team@demo.example -->
<script async src="https://tracker.example/pixel.js"></script></body></html>"""

# The one page that sends every security header, so the checks have a pass.
GOOD_HEADERS = [
    ("Content-Security-Policy", "default-src 'self'; script-src 'self'; frame-ancestors 'none'"),
    ("X-Frame-Options", "DENY"),
    ("X-Content-Type-Options", "nosniff"),
    ("Referrer-Policy", "strict-origin-when-cross-origin"),
]

# The contract for two endpoints. /api/profile breaks it: no `created`.
OPENAPI = {
    "openapi": "3.0.3",
    "info": {"title": "Demo app", "version": "1.0.0"},
    "paths": {
        "/api/catalog": {"get": {"responses": {"200": {"description": "Every item",
            "content": {"application/json": {"schema": {
                "type": "array", "items": {"$ref": "#/components/schemas/Item"}}}}}}}},
        "/api/profile": {"get": {"security": [{"session": []}], "responses": {
            "200": {"description": "The signed-in user", "content": {"application/json": {
                "schema": {"$ref": "#/components/schemas/Profile"}}}},
            "401": {"description": "Not signed in"}}}},
    },
    "components": {
        "securitySchemes": {"session": {"type": "apiKey", "in": "cookie", "name": "sid"}},
        "schemas": {
            "Item": {"type": "object", "required": ["id", "name", "price"], "properties": {
                "id": {"type": "integer"}, "name": {"type": "string"},
                "price": {"type": "number"}, "description": {"type": "string"}}},
            "Profile": {"type": "object", "required": ["email", "role", "created"], "properties": {
                "email": {"type": "string"}, "role": {"type": "string", "enum": ["admin", "user"]},
                "created": {"type": "string"}}},
        },
    },
}

# A client-rendered shell: nothing to judge until JavaScript runs.
APP_SHELL = """<!doctype html><html lang=en><head><title>Demo app</title></head>
<body><div id=root></div><script src=/app.js></script></body></html>"""

ROBOTS = f"""User-agent: *
Disallow: /admin

Sitemap: {SITE}/sitemap.xml
"""
# Deliberately slow for the perf pass. The script in the head blocks rendering,
# the inline loop is a long task, and the image has no width or height, so the
# text below it jumps down when it arrives.
HEAVY_PAGE = """<!doctype html><html lang=en><head><title>A heavy page</title>
<meta name=viewport content="width=device-width, initial-scale=1">
<link rel=stylesheet href=/heavy.css>
<script src=/blocking.js></script>
</head><body><h1>A heavy page</h1>
<img src=/heavy.svg alt="A very large picture">
<p>This paragraph moves when the picture above it finally loads.</p>
<div style="height:900px;background:#eee">And so does everything below it.</div>
<script>addEventListener("load", function () { var t = Date.now(); while (Date.now() - t < 300) {} });</script>
</body></html>"""
HEAVY_SVG = ('<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800">'
             + "".join(f'<rect x="{i % 1200}" y="{i % 800}" width="3" height="3" fill="#{i % 4096:03x}"/>'
                       for i in range(30000))
             + "</svg>")
CATALOG = [{"id": i, "name": f"Item {i}", "price": i % 97,
            "description": f"A plain demo item, number {i}, with a little text to it"}
           for i in range(5000)]
IN_FLIGHT = [0]
IN_FLIGHT_LOCK = threading.Lock()

SITEMAP = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>{SITE}/</loc></url>
  <url><loc>{SITE}/about</loc></url>
</urlset>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep the terminal quiet

    def who(self):
        """Return the role of the logged-in user, or None."""
        cookies = self.headers.get("Cookie", "")
        for part in cookies.split(";"):
            part = part.strip()
            if part.startswith("sid="):
                return SESSIONS.get(part[4:])
        return None

    def reply(self, code, body="", headers=(), ctype="text/html"):
        self.send_response(code)
        for key, value in headers:
            self.send_header(key, value)
        data = body.encode("utf-8")          # the length is in bytes, not characters
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype.startswith("text/") else ""))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        role = self.who()

        if path == "/":
            return self.reply(200, HOME_PAGE, GOOD_HEADERS)

        if path == "/openapi.json":
            return self.reply(200, json.dumps(OPENAPI), ctype="application/json")

        if path == "/api/profile":
            # THE CORS BUG. Echoes whatever Origin asked, with credentials, so
            # any website can read a signed-in user's profile.
            origin = self.headers.get("Origin")
            cors = [("Access-Control-Allow-Origin", origin),
                    ("Access-Control-Allow-Credentials", "true")] if origin else []
            if not role:
                return self.reply(401, '{"error": "not signed in"}', cors, ctype="application/json")
            email = "a@x.com" if role == "admin" else "u@x.com"
            # THE CONTRACT BUG. The spec promises `created`; it was dropped.
            return self.reply(200, json.dumps({"email": email, "role": role}), cors,
                              ctype="application/json")

        if path == "/about":
            return self.reply(200, ABOUT_PAGE)

        if path == "/app":
            return self.reply(200, APP_SHELL)

        if path == "/app.js":
            return self.reply(200, APP_JS, ctype="text/javascript")

        if path == "/api/feed":
            if FEED_FAILS[0]:
                return self.reply(500, '{"error": "feed unavailable"}', ctype="application/json")
            return self.reply(200, json.dumps([{"id": i} for i in range(3)]), ctype="application/json")

        if path == "/welcome":
            lang = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("lang", ["en"])[0]
            return self.reply(200, WELCOME_DE if lang == "de" else WELCOME_EN)

        # A Mailpit-compatible outbox, so --notifications has something to read.
        if path == "/mailpit/api/v1/messages":
            msgs = [{"ID": m["ID"], "Created": m["Created"], "Subject": m["Subject"],
                     "From": {"Address": "noreply@demo.example"}, "To": [{"Address": m["To"]}]}
                    for m in reversed(OUTBOX)]
            return self.reply(200, json.dumps({"messages": msgs, "total": len(msgs)}), ctype="application/json")
        if path.startswith("/mailpit/api/v1/message/"):
            rest = path[len("/mailpit/api/v1/message/"):]
            mid, _, tail = rest.partition("/")
            msg = next((m for m in OUTBOX if m["ID"] == mid), None)
            if not msg:
                return self.reply(404, '{"error": "no such message"}', ctype="application/json")
            if tail == "headers":
                return self.reply(200, json.dumps({"Subject": [msg["Subject"]], "To": [msg["To"]]}),
                                  ctype="application/json")
            return self.reply(200, json.dumps({"ID": mid, "Subject": msg["Subject"], "Text": msg["Text"],
                                               "HTML": msg["HTML"]}), ctype="application/json")

        if path == "/robots.txt":
            return self.reply(200, ROBOTS, ctype="text/plain")

        if path == "/sitemap.xml":
            return self.reply(200, SITEMAP, ctype="application/xml")

        if path == "/og.png":
            return self.reply(200, "png", ctype="image/png")

        if path == "/login":
            return self.reply(200, LOGIN_PAGE)

        if path == "/slow":
            time.sleep(1.5)  # a slow query on every request
            return self.reply(200, "<!doctype html><html lang=en><title>Slow</title><h1>Slow page</h1></html>")

        if path == "/heavy":
            return self.reply(200, HEAVY_PAGE)

        if path == "/heavy.svg":
            time.sleep(2.8)  # arrives long after the text has painted
            return self.reply(200, HEAVY_SVG, ctype="image/svg+xml")

        if path == "/heavy.css":
            return self.reply(200, "body { font-family: sans-serif; }\n" * 200, ctype="text/css")

        if path == "/blocking.js":
            time.sleep(0.6)
            return self.reply(200, "window.ready = true;\n", ctype="text/javascript")

        if path == "/api/catalog":
            # THE PERF BUG. No paging, and one lookup per row -- an N+1.
            rows = []
            for item in CATALOG:
                time.sleep(0.0001)  # stands in for a query per row
                rows.append(item)
            return self.reply(200, json.dumps(rows), ctype="application/json")

        if path == "/api/flaky-load":
            # Fine alone. Runs out of workers once four requests overlap.
            with IN_FLIGHT_LOCK:
                IN_FLIGHT[0] += 1
                busy = IN_FLIGHT[0] > 3
            try:
                time.sleep(0.05)
                if busy:
                    return self.reply(503, '{"error": "no worker free"}', ctype="application/json")
                return self.reply(200, '{"ok": true}', ctype="application/json")
            finally:
                with IN_FLIGHT_LOCK:
                    IN_FLIGHT[0] -= 1

        if path == "/dashboard":
            if role:
                return self.reply(200, f"<h1>Dashboard</h1><p>You are: {role}</p><a href=/logout>Sign out</a>")
            return self.reply(302, "", [("Location", "/login")])

        if path == "/admin":
            # Correct: only admins get in.
            if role == "admin":
                return self.reply(200, "<h1>Admin panel</h1>")
            if role:
                return self.reply(403, "<h1>Forbidden</h1>")
            return self.reply(302, "", [("Location", "/login")])

        if path == "/payroll":
            # THE BUG. No permission check at all. Anyone can read this,
            # including someone who is not logged in.
            return self.reply(200, "<h1>Salaries</h1><p>alice 120k, bob 95k</p>")

        if path == "/reports":
            # The tricky one, and the reason tests run in a real browser.
            #
            # This page refuses you CORRECTLY -- it just says so with HTTP 200
            # instead of 403. /payroll below also returns 200, and it leaks
            # every salary. Same status code, opposite meanings.
            #
            # So a test that only reads the status code has to guess, and it
            # guesses wrong here: it reports a bug on a page that is fine.
            # Only reading the rendered page tells the two apart.
            if role == "admin":
                return self.reply(200, "<h1>Reports</h1><p>Q3 revenue: 4.2M</p>")
            return self.reply(200, "<h1>Access denied</h1><p>Ask an admin.</p>")

        if path in POST_ONLY:
            return self.reply(405, "method not allowed", [("Allow", "POST")])

        if path == "/privacy":
            return self.reply(200, PRIVACY_PAGE)

        if path == "/account":
            if not role:
                return self.reply(302, "", [("Location", "/login")])
            return self.reply(200, ACCOUNT_PAGE)

        if path == "/api/users":
            # THE OVER-EXPOSURE BUG. The whole row is serialised, hash and all.
            if role != "admin":
                return self.reply(403 if role else 401, '{"error": "forbidden"}', ctype="application/json")
            users = [{"id": i, "email": email, "role": r,
                      "password_hash": hashlib.sha256(pw.encode()).hexdigest()}
                     for i, (email, (pw, r)) in enumerate(USERS.items(), 1)]
            return self.reply(200, json.dumps(users), ctype="application/json")

        if path.startswith("/api/orders/"):
            if not role:
                return self.reply(401, '{"error": "not signed in"}', ctype="application/json")
            try:
                oid = int(path.rsplit("/", 1)[1])
            except ValueError:
                return self.reply(404, '{"error": "no such order"}', ctype="application/json")
            if oid not in ORDERS:
                return self.reply(404, '{"error": "no such order"}', ctype="application/json")
            return self.reply(200, json.dumps({"id": oid, "status": ORDERS[oid]}), ctype="application/json")

        if path == "/api/notes":
            if not role:
                return self.reply(401, '{"error": "not signed in"}', ctype="application/json")
            return self.reply(200, json.dumps(NOTES), ctype="application/json")

        if path.startswith("/api/"):
            if role:
                return self.reply(200, '{"ok": true}')
            return self.reply(401, "unauthorized")

        return self.reply(404, "<h1>Not found</h1>")

    def session_id(self):
        for part in self.headers.get("Cookie", "").split(";"):
            part = part.strip()
            if part.startswith("sid="):
                return part[4:]
        return None

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)

        if path == "/api/password-reset":
            # THE EMAIL BUGS. The new password is in the mail in clear, the
            # link goes to a page that does not exist, and there is no
            # plain-text part.
            try:
                email = json.loads(raw or b"{}").get("email", "")
            except ValueError:
                email = ""
            if email not in USERS:
                return self.reply(202, '{"ok": true}', ctype="application/json")
            token = uuid.uuid4().hex[:12]
            OUTBOX.append({
                "ID": uuid.uuid4().hex[:10],
                "Created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "To": email, "Subject": "Reset your password", "Text": "",
                "HTML": f"<p>Your temporary password: Temp-{token[:6]}</p>"
                        f"<p><a href=\"http://127.0.0.1:8731/reset?token={token}\">Choose a new one</a></p>",
            })
            return self.reply(202, '{"ok": true}', ctype="application/json")

        if path == "/api/feed/fail":
            FEED_FAILS[0] = not FEED_FAILS[0]
            return self.reply(200, json.dumps({"failing": FEED_FAILS[0]}), ctype="application/json")

        # POST-only JSON endpoints, for run-api's method/body/header cases.
        if path == "/api/items":
            if not self.who():
                return self.reply(401, "unauthorized")
            if b'"name"' not in raw:
                return self.reply(422, '{"error": "name is required"}')
            return self.reply(201, '{"id": 1}')

        if path == "/api/logout":
            SESSIONS.pop(self.session_id(), None)
            return self.reply(204, "")

        if path.startswith("/api/orders/") and path.endswith(("/cancel", "/ship", "/pay", "/deliver")):
            if not self.who():
                return self.reply(401, '{"error": "not signed in"}', ctype="application/json")
            parts = path.split("/")                      # ['', 'api', 'orders', '<id>', '<action>']
            try:
                oid = int(parts[3])
            except ValueError:
                return self.reply(404, '{"error": "no such order"}', ctype="application/json")
            if oid not in ORDERS:
                return self.reply(404, '{"error": "no such order"}', ctype="application/json")
            target = {"cancel": "cancelled", "ship": "shipped", "pay": "paid", "deliver": "delivered"}[parts[4]]
            # THE STATE BUG. Every action checks TRANSITIONS except cancel.
            if parts[4] != "cancel" and target not in TRANSITIONS[ORDERS[oid]]:
                return self.reply(409, json.dumps({"error": f"cannot {parts[4]} an order that is {ORDERS[oid]}"}),
                                  ctype="application/json")
            ORDERS[oid] = target
            return self.reply(200, json.dumps({"id": oid, "status": target}), ctype="application/json")

        if path == "/api/notes":
            if not self.who():
                return self.reply(401, '{"error": "not signed in"}', ctype="application/json")
            try:
                note = json.loads(raw or b"{}")
            except ValueError:
                return self.reply(400, '{"error": "not JSON"}', ctype="application/json")
            if not note.get("title"):
                return self.reply(422, '{"error": "title is required"}', ctype="application/json")
            saved = {"id": len(NOTES) + 1, "title": note["title"],
                     "text": str(note.get("text", ""))[:NOTE_TEXT_LIMIT]}   # silently cut
            NOTES.append(saved)
            return self.reply(201, json.dumps({"id": saved["id"]}), ctype="application/json")

        if path == "/api/webhook":
            sent = self.headers.get("X-Signature", "")
            want = hmac.new(WEBHOOK_SECRET, raw, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(sent, want):
                return self.reply(401, "bad signature")
            return self.reply(200, '{"received": true}')

        if path == "/api/2fa":
            sid = self.session_id()
            if not self.who():
                return self.reply(401, "unauthorized")
            if TWOFA_FAILS.get(sid, 0) >= 5:
                return self.reply(429, "too many attempts")
            if b'"code": "123456"' in raw:
                return self.reply(200, '{"ok": true}')
            TWOFA_FAILS[sid] = TWOFA_FAILS.get(sid, 0) + 1
            return self.reply(401, "wrong code")

        if path != "/login":
            return self.reply(404, "<h1>Not found</h1>")

        form = urllib.parse.parse_qs(raw.decode())
        email = form.get("email", [""])[0]
        password = form.get("password", [""])[0]

        if email in USERS and USERS[email][0] == password:
            session_id = uuid.uuid4().hex
            SESSIONS[session_id] = USERS[email][1]
            return self.reply(302, "", [
                ("Location", "/dashboard"),
                ("Set-Cookie", f"sid={session_id}; Path=/"),
            ])

        return self.reply(401, "<h1>Wrong email or password</h1>")


if __name__ == "__main__":
    print("Demo app running at http://127.0.0.1:8731")
    print("Press Ctrl+C to stop it.")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8731), Handler).serve_forever()
