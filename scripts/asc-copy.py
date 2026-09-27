#!/usr/bin/env python3
"""asc-copy.py — the App Store page's text, read back and applied from docs/store-copy.md.

The store page is where every channel ends (docs/growth.md, workstream 2), and the
repo lost track of it twice: store-copy.md said "pending" for four days after a
description went live, and the live subtitle was changed on 2026-09-08 and never
written down. So the first verb READS, and nothing is applied that was not read
first in the same run.

  asc-copy.py read                 live + editable fields, both platforms, every
                                   locale → docs/store-live.json, en-US printed
  asc-copy.py diff                 en-US live/editable vs the drafts in store-copy.md
  asc-copy.py apply --platform IOS --field promotionalText          (dry run)
  asc-copy.py apply --platform IOS --field promotionalText --yes    (PATCH + read back)
  asc-copy.py --self-test          offline: draft parsing, the lint, version picking,
                                   and that nothing is written without --yes

Fields: description, keywords, promotionalText, whatsNew (per version), subtitle
(per app, shared by both platforms). Promotional text is written to the live
version and to any version in review or being prepared; the rest need a version in an editable state, and a
version In Review answers 409 (the `store-metadata-editable-in-review` memory).

Credentials, same as testflight.sh: ASC_KEY_ID and ASC_ISSUER_ID (public
identifiers, defaulted below), and the .p8 at ASC_KEY_PATH (default /tmp/asc.p8,
staged by `scripts/dev-keys.sh get-file asc-p8 /tmp/asc.p8`). A cloud session with
no Keychain passes the key's contents in ASC_KEY_P8 instead; it is written to a
0600 temp file and removed on exit. The key is never printed.
"""
import argparse, difflib, json, os, re, subprocess, sys, tempfile, time
import urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6788637831"
KEY_ID = os.environ.get("ASC_KEY_ID", "TR287WZD72")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "2152ec98-0a7c-477a-9c4a-e1c478a3a106")
STORE_COPY = os.path.join(ROOT, "docs", "store-copy.md")
SNAPSHOT = os.path.join(ROOT, "docs", "store-live.json")
PLATFORMS = ("IOS", "MAC_OS")
LOCALE = "en-US"

CAPS = {"description": 4000, "whatsNew": 4000, "keywords": 100,
        "promotionalText": 170, "subtitle": 30}
VERSION_FIELDS = ("description", "keywords", "promotionalText", "whatsNew")

# `appStoreState` is deprecated for `appVersionState`; read both, older first,
# because the release scripts already match on the older names.
LIVE = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PREORDER_READY_FOR_SALE"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}
IN_REVIEW = {"WAITING_FOR_REVIEW", "IN_REVIEW"}

# Words the store page may not carry. "room" reads as AI (user, 2026-09-27); the
# ask lines sell a surface §697b turned off.
BANNED = [(r"\brooms?\b", "\"room\" reads as AI (user, 2026-09-27)"),
          (r"\bASK IT\b", "the built-in ask is off (§697b)"),
          (r"isn't another chatbot", "the 09-13 closing line, replaced 09-27")]


# ── drafts ───────────────────────────────────────────────────────────────────

def _section(text, heading):
    """Body under the first `### <heading>…` line, up to the next `### `."""
    m = re.search(r"^### " + re.escape(heading) + r".*$", text, re.M)
    if not m:
        return None
    rest = text[m.end():]
    nxt = re.search(r"^#{2,3} ", rest, re.M)
    return (rest[:nxt.start()] if nxt else rest).strip()


def drafts(text):
    """{platform: {field: text}} from store-copy.md. A missing heading is an
    error, never an empty field: an empty PATCH would blank the live page."""
    out = {"IOS": {}, "MAC_OS": {}}
    for platform, heading in (("IOS", "iOS description"), ("MAC_OS", "Mac description")):
        body = _section(text, heading)
        if body is None:
            raise ValueError(f"store-copy.md has no '### {heading}' section")
        out[platform]["description"] = body
    promo = _section(text, "Promotional text")
    if promo is None:
        raise ValueError("store-copy.md has no '### Promotional text' section")
    out["IOS"]["promotionalText"] = out["MAC_OS"]["promotionalText"] = promo
    kw = re.search(r"^- keywords: `([^`]+)`", text, re.M)
    if kw:
        # Pending on iOS, already applied on Mac (store-copy.md says so).
        out["IOS"]["keywords"] = kw.group(1)
    return out


def lint(field, value):
    """Problems with a value before it may be sent. Empty list = sendable."""
    problems = []
    if not value or not value.strip():
        problems.append("empty")
    if field in CAPS and len(value) > CAPS[field]:
        problems.append(f"{len(value)} chars, cap {CAPS[field]}")
    if field == "keywords" and ", " in value:
        problems.append("a space after a comma spends the keyword budget")
    for pattern, why in BANNED:
        if re.search(pattern, value, re.I):
            problems.append(why)
    return problems


# ── the API ──────────────────────────────────────────────────────────────────

class ASC:
    def __init__(self, key_path):
        self.key_path = key_path
        self._token, self._minted = None, 0

    def token(self):
        # A token lives 1190s (asc-jwt.py); mint again well before that.
        if not self._token or time.time() - self._minted > 900:
            jwt = os.path.join(ROOT, "scripts", "asc-jwt.py")
            self._token = subprocess.run(
                [sys.executable, jwt, KEY_ID, ISSUER_ID, self.key_path],
                check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
            self._minted = time.time()
        return self._token

    def call(self, method, path, body=None):
        req = urllib.request.Request(
            API + path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + self.token(),
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            try:
                detail = "; ".join(x.get("detail", "") for x in json.loads(detail)["errors"])
            except Exception:
                pass
            raise SystemExit(f"✗ {method} {path} → HTTP {e.code}: {detail}")

    def get(self, path):
        return self.call("GET", path)

    def patch(self, path, body):
        return self.call("PATCH", path, body)


def state(attrs):
    return attrs.get("appStoreState") or attrs.get("appVersionState") or attrs.get("state") or "?"


def pick(records):
    """(live, editable, in_review) from appStoreVersions or appInfos, newest
    first as the API lists them; each is the first match or None."""
    live = next((r for r in records if state(r["attributes"]) in LIVE), None)
    editable = next((r for r in records if state(r["attributes"]) in EDITABLE), None)
    review = next((r for r in records if state(r["attributes"]) in IN_REVIEW), None)
    return live, editable, review


def read_all(api):
    snap = {"readAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "appId": APP_ID,
            "versions": {}, "appInfo": {}}
    for platform in PLATFORMS:
        versions = api.get(f"/apps/{APP_ID}/appStoreVersions?filter%5Bplatform%5D={platform}"
                           f"&limit=10")["data"]
        live, editable, review = pick(versions)
        snap["versions"][platform] = {}
        for role, v in (("live", live), ("editable", editable), ("inReview", review)):
            if not v:
                continue
            locs = api.get(f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")["data"]
            snap["versions"][platform][role] = {
                "id": v["id"], "version": v["attributes"].get("versionString"),
                "state": state(v["attributes"]),
                "locales": {l["attributes"]["locale"]: {
                    "id": l["id"], **{f: l["attributes"].get(f) for f in VERSION_FIELDS}}
                    for l in locs}}
    infos = api.get(f"/apps/{APP_ID}/appInfos")["data"]
    live, editable, review = pick(infos)
    for role, info in (("live", live), ("editable", editable), ("inReview", review)):
        if not info:
            continue
        locs = api.get(f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]
        snap["appInfo"][role] = {
            "id": info["id"], "state": state(info["attributes"]),
            "locales": {l["attributes"]["locale"]: {
                "id": l["id"], "name": l["attributes"].get("name"),
                "subtitle": l["attributes"].get("subtitle")} for l in locs}}
    return snap


# ── verbs ────────────────────────────────────────────────────────────────────

def show(snap):
    print(f"read {snap['readAt']}")
    for role, info in snap["appInfo"].items():
        loc = info["locales"].get(LOCALE, {})
        print(f"\nappInfo {role} ({info['state']})  name: {loc.get('name')!r}  "
              f"subtitle: {loc.get('subtitle')!r}")
    for platform, roles in snap["versions"].items():
        for role, v in roles.items():
            loc = v["locales"].get(LOCALE, {})
            print(f"\n{platform} {role} {v['version']} ({v['state']}), "
                  f"{len(v['locales'])} locale(s)")
            for f in VERSION_FIELDS:
                val = loc.get(f) or ""
                first = val.splitlines()[0] if val else "—"
                print(f"  {f:16} {len(val):5}  {first[:90]}")


def diff(snap, want):
    same = True
    for platform in PLATFORMS:
        roles = snap["versions"].get(platform, {})
        for field, text in want.get(platform, {}).items():
            role = "editable" if "editable" in roles else "live"
            if role not in roles:
                print(f"{platform} {field}: no live or editable version")
                continue
            have = roles[role]["locales"].get(LOCALE, {}).get(field) or ""
            if have.strip() == text.strip():
                print(f"= {platform} {field} ({role}) matches the draft")
                continue
            same = False
            print(f"≠ {platform} {field} ({role} {roles[role]['version']}):")
            sys.stdout.writelines(difflib.unified_diff(
                have.splitlines(True), (text + "\n").splitlines(True),
                "live", "store-copy.md", n=1))
            print()
    return same


def targets(snap, platform, field):
    """[(localization id, what it is, kind)] the field is written to, or exit.
    Promotional text goes to EVERY version that has one — the live version is
    what the store shows today, and a version in review or being prepared would
    carry the old text onto the page at its release."""
    if field == "subtitle":
        info = snap["appInfo"].get("editable")
        if not info or LOCALE not in info["locales"]:
            raise SystemExit("✗ subtitle: no editable appInfo — it opens with a new version")
        return [(info["locales"][LOCALE]["id"], f"appInfo {info['state']}", "appInfoLocalizations")]
    roles = snap["versions"].get(platform, {})
    wanted = ("live", "inReview", "editable") if field == "promotionalText" else ("editable",)
    out = [(roles[r]["locales"][LOCALE]["id"],
            f"{platform} {roles[r]['version']} ({roles[r]['state']})",
            "appStoreVersionLocalizations")
           for r in wanted if r in roles and LOCALE in roles[r]["locales"]]
    if not out:
        raise SystemExit(f"✗ {platform} {field}: no version accepts it — "
                         "open one with appstore-release.sh first")
    return out


def apply(api, snap, platform, field, text, yes):
    problems = lint(field, text)
    if problems:
        raise SystemExit(f"✗ {field} not sent: " + "; ".join(problems))
    dests = targets(snap, platform, field)
    for _, what, _ in dests:
        print(f"{field} → {what}, {len(text)} chars")
    if not yes:
        print("— dry run: pass --yes to write it —")
        return False
    for loc_id, what, kind in dests:
        api.patch(f"/{kind}/{loc_id}", {"data": {"type": kind, "id": loc_id,
                                                 "attributes": {field: text}}})
        back = api.get(f"/{kind}/{loc_id}")["data"]["attributes"].get(field) or ""
        if back != text:
            raise SystemExit(f"✗ {field} did not persist on {what} (read-back differs)")
        print(f"✓ {field} written to {what} and read back")
    return True


def key_path():
    if os.environ.get("ASC_KEY_P8"):
        fd, path = tempfile.mkstemp(suffix=".p8")
        with os.fdopen(fd, "w") as f:
            f.write(os.environ["ASC_KEY_P8"])
        os.chmod(path, 0o600)
        import atexit
        atexit.register(lambda: os.path.exists(path) and os.remove(path))
        return path
    path = os.environ.get("ASC_KEY_PATH", "/tmp/asc.p8")
    if not os.path.exists(path):
        raise SystemExit(f"✗ no key at {path} — run: scripts/dev-keys.sh get-file asc-p8 {path}")
    return path


# ── self-test ────────────────────────────────────────────────────────────────

class FakeASC:
    """Answers the paths read_all/apply use, and records every write."""
    def __init__(self, versions, infos, locs):
        self.versions, self.infos, self.locs, self.writes = versions, infos, locs, []

    def get(self, path):
        if "/appStoreVersions?" in path:
            plat = re.search(r"platform%5D=(\w+)", path).group(1)
            return {"data": [v for v in self.versions if v["p"] == plat]}
        if path.endswith("/appInfos"):
            return {"data": self.infos}
        m = re.match(r"/(appStoreVersions|appInfos)/([^/]+)/", path)
        if m:
            return {"data": self.locs[m.group(2)]}
        m = re.match(r"/(appStoreVersionLocalizations|appInfoLocalizations)/(.+)$", path)
        for ls in self.locs.values():
            for l in ls:
                if l["id"] == m.group(2):
                    return {"data": l}
        raise AssertionError("unexpected GET " + path)

    def patch(self, path, body):
        self.writes.append((path, body))
        lid = path.rsplit("/", 1)[1]
        for ls in self.locs.values():
            for l in ls:
                if l["id"] == lid:
                    l["attributes"].update(body["data"]["attributes"])
        return {}


def self_test():
    ok = True

    def check(cond, label):
        nonlocal ok
        print(("  ok   " if cond else "  FAIL ") + label)
        ok = ok and cond

    text = open(STORE_COPY).read()
    d = drafts(text)
    for platform in PLATFORMS:
        for field, value in d[platform].items():
            check(lint(field, value) == [], f"draft {platform} {field} passes the lint "
                  f"({len(value)} chars) {lint(field, value) or ''}")
    check("keywords" in d["IOS"] and "keywords" not in d["MAC_OS"],
          "keywords are an iOS draft only")

    # Mutations: each must be caught, or the lint certifies nothing.
    check(lint("description", "Every app opens as a room.") != [], "catches \"room\"")
    check(lint("description", "ASK IT anything") != [], "catches the ask")
    check(lint("promotionalText", "x" * 171) != [], "catches a promo over 170")
    check(lint("keywords", "feed, rss") != [], "catches a spaced keyword list")
    check(lint("subtitle", "  ") != [], "catches an empty value")
    try:
        drafts(text.replace("### Mac description", "### Mac blurb"))
        check(False, "a missing section raises")
    except ValueError:
        check(True, "a missing section raises")

    def v(i, p, st):
        return {"id": i, "p": p, "attributes": {"appStoreState": st, "versionString": i}}

    def loc(i, **a):
        return {"id": i, "attributes": {"locale": LOCALE, **a}}

    fake = FakeASC(
        versions=[v("i2", "IOS", "IN_REVIEW"), v("i1", "IOS", "READY_FOR_SALE"),
                  v("m2", "MAC_OS", "PREPARE_FOR_SUBMISSION"), v("m1", "MAC_OS", "READY_FOR_SALE")],
        infos=[{"id": "a2", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}},
               {"id": "a1", "attributes": {"state": "READY_FOR_DISTRIBUTION"}}],
        locs={"i2": [loc("li2", promotionalText="old")], "i1": [loc("li1", promotionalText="old")],
              "m2": [loc("lm2", description="old")], "m1": [loc("lm1", description="old")],
              "a2": [loc("la2", name="Casberi", subtitle="old")],
              "a1": [loc("la1", name="Casberi", subtitle="old")]})
    snap = read_all(fake)
    check(set(snap["versions"]["IOS"]) == {"live", "inReview"}, "iOS: live and in review found")
    check(snap["versions"]["MAC_OS"]["editable"]["id"] == "m2", "Mac: the editable version found")
    check(snap["appInfo"]["editable"]["id"] == "a2", "appInfo: the editable record found")

    apply(fake, snap, "IOS", "promotionalText", d["IOS"]["promotionalText"], yes=False)
    check(fake.writes == [], "a dry run writes nothing")
    apply(fake, snap, "IOS", "promotionalText", d["IOS"]["promotionalText"], yes=True)
    check(sorted(w[0] for w in fake.writes) == ["/appStoreVersionLocalizations/li1",
                                                "/appStoreVersionLocalizations/li2"],
          "promo goes to the live version AND the one in review")
    try:
        apply(fake, snap, "IOS", "description", d["IOS"]["description"], yes=True)
        check(False, "a description with no editable iOS version is refused")
    except SystemExit:
        check(True, "a description with no editable iOS version is refused")
    check(len(fake.writes) == 2, "the refusal wrote nothing")
    try:
        apply(fake, snap, "MAC_OS", "description", "Every app opens as a room.", yes=True)
        check(False, "a linted value is refused")
    except SystemExit:
        check(True, "a linted value is refused before any write")
    check(len(fake.writes) == 2, "the lint refusal wrote nothing")

    print("✓ asc-copy self-test" if ok else "✗ asc-copy self-test")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("verb", nargs="?", choices=("read", "diff", "apply"))
    ap.add_argument("--platform", choices=PLATFORMS)
    ap.add_argument("--field", choices=sorted(CAPS))
    ap.add_argument("--text-file", help="send this file's contents instead of the draft")
    ap.add_argument("--yes", action="store_true", help="write; without it apply is a dry run")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.verb:
        ap.error("a verb or --self-test is required")

    api = ASC(key_path())
    snap = read_all(api)
    with open(SNAPSHOT, "w") as f:
        json.dump(snap, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if a.verb == "read":
        show(snap)
        print(f"\n→ {os.path.relpath(SNAPSHOT, ROOT)}")
        return 0
    want = drafts(open(STORE_COPY).read())
    if a.verb == "diff":
        return 0 if diff(snap, want) else 1
    if not a.platform or not a.field:
        ap.error("apply needs --platform and --field")
    if a.text_file:
        text = open(a.text_file).read().strip()
    elif a.field in want[a.platform]:
        text = want[a.platform][a.field]
    else:
        ap.error(f"store-copy.md has no {a.platform} {a.field} draft; pass --text-file")
    apply(api, snap, a.platform, a.field, text, a.yes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
