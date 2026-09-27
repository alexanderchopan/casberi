#!/usr/bin/env python3
"""asc-report.py — the store funnel, read from App Store Connect's Analytics Reports.

The app has no telemetry, by rule, so App Store Connect is the only place installs,
their sources and their campaigns come from (docs/growth.md, workstream 1). Nothing
here reads the app; everything is Apple's aggregate, privacy-thresholded counts.

  asc-report.py status                what report requests exist, and which reports
                                      and instances they have produced so far
  asc-report.py request               ask Apple to start generating reports (ONGOING):
                                      a dry run until --yes; refused if one is active.
                                      The first instances appear in 1–2 days
  asc-report.py funnel [--detailed]   impressions → page views → downloads, per week,
                                      by source, territory and device; --detailed adds
                                      the campaign (`ct=`) and referrer breakdowns
  asc-report.py links --pt <token>    one App Store link per channel in CHANNELS
  asc-report.py --self-test           offline: the overwrite rule, parsing, the
                                      checksum, the request guard, the links

Reports read (names matched by pattern, because Apple's own docs spell them two ways):
"App Store Discovery and Engagement" and "App Store Downloads", Standard by default,
Detailed with --detailed (it carries Campaign, Source Info and Page Title, and drops
small rows for privacy). DAILY instances: they exist for both reports at both levels,
and live 35 days, so a funnel covers about five weeks.

Instances OVERLAP: a daily instance restates the last few days, and "Instances from a
more recent processingDate overwrite instances with an earlier processingDate … Don't
merge records for a Date across two report instances" (Apple, Data Completeness and
Corrections). So each Date is taken from the newest instance that carries it, and
never summed across two.

Segments are cached by id under ~/Library/Caches/casberi/asc-reports (an instance never
changes once made) and verified against their MD5 checksum and size.

Credentials exactly as asc-copy.py: ASC_KEY_ID / ASC_ISSUER_ID defaulted, the .p8 at
ASC_KEY_PATH (default /tmp/asc.p8, staged by `scripts/dev-keys.sh get-file asc-p8`) or
its contents in ASC_KEY_P8. `request` needs the Admin role; reading needs Admin, Sales
and Reports, or Finance. The key is never printed.
"""
import argparse, collections, csv, datetime, gzip, hashlib, io, json, os, re, subprocess
import sys, tempfile, time, urllib.error, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6788637831"
KEY_ID = os.environ.get("ASC_KEY_ID", "TR287WZD72")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "2152ec98-0a7c-477a-9c4a-e1c478a3a106")
CACHE = os.path.expanduser("~/Library/Caches/casberi/asc-reports")

# (key, pattern over the report's lowercased name). "Pre-order" must never match
# downloads: it is its own report with its own counts.
REPORTS = (("discovery", r"discovery and engagement"),
           ("downloads", r"^app (store )?downloads\b"))

# One App Store link per channel; the token is what the Campaign column reports.
# growth.md, workstream 1 and 7. Apple caps a campaign token at 40 characters.
CHANNELS = ("x", "instagram", "website", "farcaster", "bluesky", "hn", "producthunt",
            "reddit", "newsletter", "github", "email")
STORE_URL = f"https://apps.apple.com/app/id{APP_ID}"

FIRST = "first-time download"
REDOWNLOAD = "redownload"


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
        url = path if path.startswith("https://") else API + path
        req = urllib.request.Request(
            url, method=method,
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
            hint = " (reading reports needs Admin, Sales and Reports or Finance; " \
                   "requesting them needs Admin)" if e.code == 403 else ""
            raise SystemExit(f"✗ {method} {path.split('?')[0]} → HTTP {e.code}: {detail}{hint}")

    def get(self, path):
        return self.call("GET", path)

    def get_all(self, path):
        out, nxt = [], path
        while nxt:
            page = self.get(nxt)
            out += page.get("data", [])
            nxt = (page.get("links") or {}).get("next")
        return out

    def post(self, path, body):
        return self.call("POST", path, body)

    def fetch(self, url):
        # A presigned S3 URL: no Authorization header, and it expires in 5 minutes.
        with urllib.request.urlopen(url, timeout=120) as r:
            return r.read()


def requests_for_app(api):
    return api.get_all(f"/apps/{APP_ID}/analyticsReportRequests?limit=200")


def active_ongoing(reqs):
    return next((r for r in reqs if r["attributes"].get("accessType") == "ONGOING"
                 and not r["attributes"].get("stoppedDueToInactivity")), None)


def match_report(name, level):
    """The REPORTS key a report name belongs to at this level, or None."""
    low = name.lower().strip()
    if not low.endswith(" " + level):
        return None
    for key, pattern in REPORTS:
        if re.search(pattern, low) and "pre-order" not in low:
            return key
    return None


def reports_by_key(api, request_id, level):
    out = {}
    for r in api.get_all(f"/analyticsReportRequests/{request_id}/reports?limit=200"):
        key = match_report(r["attributes"].get("name", ""), level)
        if key:
            out[key] = r
    return out


def instances(api, report_id, granularity="DAILY"):
    q = urllib.parse.urlencode({"filter[granularity]": granularity, "limit": 200})
    return api.get_all(f"/analyticsReports/{report_id}/instances?{q}")


# ── segments and rows ────────────────────────────────────────────────────────

def segment_bytes(api, seg):
    """The segment's file, from the cache or downloaded, verified. A mismatch is
    never cached and never read."""
    a = seg["attributes"]
    path = os.path.join(CACHE, seg["id"] + ".gz")
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
        if verify(data, a):
            return data
        os.remove(path)
    data = api.fetch(a["url"])
    if not verify(data, a):
        raise SystemExit(f"✗ segment {seg['id']}: checksum or size does not match — not read")
    os.makedirs(CACHE, exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)
    return data


def verify(data, attrs):
    if attrs.get("sizeInBytes") is not None and len(data) != attrs["sizeInBytes"]:
        return False
    want = (attrs.get("checksum") or "").lower()
    return not want or hashlib.md5(data).hexdigest() == want


def parse(data):
    """Rows (dicts keyed by the header, names lowercased) from a segment. Apple says
    to rely on column NAMES, not positions; the files are gzipped and named .csv but
    have been tab-separated, so the delimiter is read off the header."""
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    text = data.decode("utf-8-sig")
    header = text.split("\n", 1)[0]
    delim = "\t" if header.count("\t") >= header.count(",") else ","
    reader = csv.DictReader(io.StringIO(text), delimiter=delim)
    return [{(k or "").strip().lower(): (v or "").strip() for k, v in row.items()}
            for row in reader]


def latest_rows(batches):
    """[(processingDate, rows)] → rows, each Date taken ONLY from the newest
    instance that carries it (Apple's overwrite rule)."""
    owner = {}
    for pdate, rows in batches:
        for row in rows:
            d = row.get("date")
            if d and (d not in owner or pdate > owner[d]):
                owner[d] = pdate
    return [row for pdate, rows in batches for row in rows
            if row.get("date") and owner[row["date"]] == pdate]


def report_rows(api, report, granularity="DAILY"):
    batches = []
    for inst in instances(api, report["id"], granularity):
        pdate = inst["attributes"].get("processingDate") or ""
        rows = []
        for seg in api.get_all(f"/analyticsReportInstances/{inst['id']}/segments?limit=200"):
            rows += parse(segment_bytes(api, seg))
        batches.append((pdate, rows))
    return latest_rows(batches)


# ── the funnel ───────────────────────────────────────────────────────────────

def count(row):
    try:
        return int(float(row.get("counts") or 0))
    except ValueError:
        return 0


def week_of(date):
    d = datetime.date.fromisoformat(date[:10])
    return (d - datetime.timedelta(days=d.weekday())).isoformat()


def funnel(disc_rows, dl_rows, by=None):
    """{group: [impressions, page views, first-time downloads, redownloads]}.
    `by` is a column name, or None for per-week. Event and type values are case
    insensitive (Apple)."""
    out = collections.defaultdict(lambda: [0, 0, 0, 0])

    def group(row):
        if by is None:
            return week_of(row["date"])
        return row.get(by) or "(none)"

    for row in disc_rows:
        ev = (row.get("event") or "").lower()
        if ev == "impression":
            out[group(row)][0] += count(row)
        elif ev == "page view":
            out[group(row)][1] += count(row)
    for row in dl_rows:
        t = (row.get("download type") or "").lower()
        if t == FIRST:
            out[group(row)][2] += count(row)
        elif t == REDOWNLOAD:
            out[group(row)][3] += count(row)
    return dict(out)


def table(title, data, limit=None, sort_by_downloads=True):
    rows = sorted(data.items(), key=(lambda kv: (-kv[1][2], -kv[1][1], kv[0]))
                  if sort_by_downloads else (lambda kv: kv[0]))
    if limit:
        rows = rows[:limit]
    print(f"\n{title}")
    print(f"  {'':28} {'impr.':>8} {'views':>8} {'first dl':>9} {'redl':>6} {'view→dl':>8}")
    for k, (imp, views, first, redl) in rows:
        rate = f"{100 * first / views:.1f}%" if views else "—"
        print(f"  {k[:28]:28} {imp:>8} {views:>8} {first:>9} {redl:>6} {rate:>8}")


def show_funnel(disc, dl, detailed):
    if not disc and not dl:
        print("no rows yet — reports appear 1–2 days after the request")
        return
    dates = sorted({r["date"] for r in disc + dl if r.get("date")})
    print(f"{dates[0]} … {dates[-1]}, {len(disc)} discovery rows, {len(dl)} download rows"
          f" ({'detailed: small rows are dropped for privacy' if detailed else 'standard'})")
    print("counts are EVENTS (Counts), never summed unique users")
    table("by week (Monday)", funnel(disc, dl), sort_by_downloads=False)
    table("by source", funnel(disc, dl, "source type"))
    table("by device", funnel(disc, dl, "device"))
    table("by territory (top 12)", funnel(disc, dl, "territory"), limit=12)
    if detailed:
        table("by campaign (ct=)", funnel(disc, dl, "campaign"))
        table("by referrer (top 12)", funnel(disc, dl, "source info"), limit=12)
        table("by page (custom product pages)", funnel(disc, dl, "page title"))


# ── links ────────────────────────────────────────────────────────────────────

def campaign_link(pt, ct):
    if not re.fullmatch(r"[0-9]+", pt or ""):
        raise ValueError("the provider token (pt) is digits — App Store Connect → "
                         "Analytics → Acquisition → Campaigns → Generate Link")
    if not re.fullmatch(r"[a-z0-9_-]{1,40}", ct):
        raise ValueError(f"campaign token {ct!r}: 1–40 of a-z 0-9 _ -")
    return f"{STORE_URL}?pt={pt}&ct={ct}&mt=8"


# ── verbs ────────────────────────────────────────────────────────────────────

def status(api):
    reqs = requests_for_app(api)
    if not reqs:
        print("no report requests — run: asc-report.py request (dry run), then --yes")
        return
    for r in reqs:
        a = r["attributes"]
        print(f"request {r['id']}  {a.get('accessType')}"
              f"{'  STOPPED (inactivity) — make a new one' if a.get('stoppedDueToInactivity') else ''}")
        for level in ("standard", "detailed"):
            for key, rep in sorted(reports_by_key(api, r["id"], level).items()):
                insts = instances(api, rep["id"])
                dates = sorted(i["attributes"].get("processingDate", "") for i in insts)
                span = f"{dates[0]} … {dates[-1]}" if dates else "none yet"
                print(f"  {rep['attributes']['name']:48} daily instances: {len(insts):3}  {span}")


def request(api, yes):
    reqs = requests_for_app(api)
    live = active_ongoing(reqs)
    if live:
        print(f"= an ONGOING request is already active ({live['id']}); nothing to do")
        return False
    body = {"data": {"type": "analyticsReportRequests",
                     "attributes": {"accessType": "ONGOING"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}
    print(f"POST /analyticsReportRequests  ONGOING for app {APP_ID}")
    if not yes:
        print("— dry run: pass --yes to ask Apple to start generating reports —")
        return False
    made = api.post("/analyticsReportRequests", body)["data"]
    print(f"✓ request {made['id']} made; the first instances appear in 1–2 days")
    return True


def funnel_verb(api, detailed):
    live = active_ongoing(requests_for_app(api))
    if not live:
        raise SystemExit("✗ no active ONGOING request — run: asc-report.py request --yes")
    level = "detailed" if detailed else "standard"
    reps = reports_by_key(api, live["id"], level)
    missing = [k for k, _ in REPORTS if k not in reps]
    if missing:
        print(f"(no {level} report yet for: {', '.join(missing)})")
    disc = report_rows(api, reps["discovery"]) if "discovery" in reps else []
    dl = report_rows(api, reps["downloads"]) if "downloads" in reps else []
    show_funnel(disc, dl, detailed)


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

def gz_tsv(header, rows):
    lines = ["\t".join(header)] + ["\t".join(r) for r in rows]
    return gzip.compress(("\n".join(lines) + "\n").encode())


class FakeASC:
    """Answers the paths the verbs use, serves segments by URL, records writes."""
    def __init__(self, reqs, reports, insts, segs, files):
        self.reqs, self.reports, self.insts, self.segs, self.files = reqs, reports, insts, segs, files
        self.posts, self.fetches = [], 0

    def get_all(self, path):
        if path.startswith(f"/apps/{APP_ID}/analyticsReportRequests"):
            return self.reqs
        m = re.match(r"/analyticsReportRequests/([^/]+)/reports", path)
        if m:
            return self.reports.get(m.group(1), [])
        m = re.match(r"/analyticsReports/([^/]+)/instances", path)
        if m:
            return self.insts.get(m.group(1), [])
        m = re.match(r"/analyticsReportInstances/([^/]+)/segments", path)
        if m:
            return self.segs.get(m.group(1), [])
        raise AssertionError("unexpected GET " + path)

    def post(self, path, body):
        self.posts.append((path, body))
        return {"data": {"id": "new"}}

    def fetch(self, url):
        self.fetches += 1
        return self.files[url]


def self_test():
    global CACHE
    ok = True

    def check(cond, label):
        nonlocal ok
        print(("  ok   " if cond else "  FAIL ") + label)
        ok = ok and cond

    # Names: both spellings Apple uses, and never pre-orders.
    check(match_report("App Store Discovery and Engagement Standard", "standard") == "discovery",
          "matches discovery, standard")
    check(match_report("App Store Discovery and Engagement Detailed", "standard") is None,
          "a detailed report is not read as standard")
    check(match_report("App Downloads Standard", "standard") == "downloads", "matches 'App Downloads'")
    check(match_report("App Store Downloads Detailed", "detailed") == "downloads",
          "matches 'App Store Downloads'")
    check(match_report("App Store Pre-orders Standard", "standard") is None, "never pre-orders")

    # Parsing: gzip, tabs or commas, column names not positions, a BOM.
    rows = parse(gz_tsv(["Counts", "Date", "Event"], [["7", "2026-09-01", "Impression"]]))
    check(rows == [{"counts": "7", "date": "2026-09-01", "event": "impression".title()}],
          "reads a gzipped TSV by column name")
    rows = parse("﻿Date,Event,Counts\n2026-09-01,Page view,3\n".encode())
    check(rows[0]["date"] == "2026-09-01" and count(rows[0]) == 3, "reads a plain CSV with a BOM")

    # The overwrite rule: day 2 appears in both instances; only the newer counts.
    older = [{"date": "2026-09-01", "counts": "5"}, {"date": "2026-09-02", "counts": "1"}]
    newer = [{"date": "2026-09-02", "counts": "4"}, {"date": "2026-09-03", "counts": "2"}]
    merged = latest_rows([("2026-09-04", newer), ("2026-09-03", older)])
    check(sum(count(r) for r in merged) == 11, "a restated day is taken from the newer instance only")
    check(sum(count(r) for r in latest_rows([("a", older), ("a", older)])) == 12,
          "the rule compares processingDate, not identity (a tie keeps both — Apple never ties)")

    # The funnel: events and download types, case-insensitive; pre-order rows ignored.
    disc = [{"date": "2026-09-01", "event": "Impression", "source type": "App Store search", "counts": "100"},
            {"date": "2026-09-01", "event": "PAGE VIEW", "source type": "App Store search", "counts": "20"},
            {"date": "2026-09-08", "event": "Tap", "source type": "Web referrer", "counts": "9"},
            {"date": "2026-09-08", "event": "Page view", "source type": "Web referrer", "counts": "10"}]
    dl = [{"date": "2026-09-02", "download type": "First-time download", "source type": "App Store search", "counts": "5"},
          {"date": "2026-09-09", "download type": "Redownload", "source type": "Web referrer", "counts": "1"},
          {"date": "2026-09-09", "download type": "Auto-update", "source type": "Web referrer", "counts": "50"}]
    weeks = funnel(disc, dl)
    check(weeks == {"2026-08-31": [100, 20, 5, 0], "2026-09-07": [0, 10, 0, 1]},
          "per week: impressions, views, first downloads, redownloads; taps and updates left out")
    check(funnel(disc, dl, "source type")["Web referrer"] == [0, 10, 0, 1], "per source")
    check(funnel([], [{"date": "2026-09-01", "download type": FIRST, "counts": "2"}], "campaign")
          == {"(none)": [0, 0, 2, 0]}, "a missing column groups as (none), never drops the row")

    # Segments: verified, cached, and a bad checksum is never read or kept.
    CACHE = tempfile.mkdtemp()
    good = gz_tsv(["Date", "Event", "Counts"], [["2026-09-01", "Impression", "3"]])
    fake = FakeASC(
        reqs=[{"id": "r1", "attributes": {"accessType": "ONGOING", "stoppedDueToInactivity": False}}],
        reports={"r1": [{"id": "d", "attributes": {"name": "App Store Discovery and Engagement Standard"}},
                        {"id": "x", "attributes": {"name": "App Store Pre-orders Standard"}}]},
        insts={"d": [{"id": "i1", "attributes": {"processingDate": "2026-09-02"}}]},
        segs={"i1": [{"id": "s1", "attributes": {"url": "u1", "sizeInBytes": len(good),
                                                 "checksum": hashlib.md5(good).hexdigest()}}]},
        files={"u1": good, "u2": good + b"x"})
    reps = reports_by_key(fake, "r1", "standard")
    check(set(reps) == {"discovery"}, "a request's reports sorted by key, pre-orders left out")
    rows = report_rows(fake, reps["discovery"])
    rows_again = report_rows(fake, reps["discovery"])
    check(len(rows) == 1 and rows == rows_again and fake.fetches == 1,
          "a segment is downloaded once, then read from the cache")
    bad = {"id": "s2", "attributes": {"url": "u2", "sizeInBytes": len(good),
                                      "checksum": hashlib.md5(good).hexdigest()}}
    try:
        segment_bytes(fake, bad)
        check(False, "a segment that fails its checksum is refused")
    except SystemExit:
        check(not os.path.exists(os.path.join(CACHE, "s2.gz")),
              "a segment that fails its checksum is refused and not cached")

    # The request guard: a dry run writes nothing; an active request is not doubled.
    check(request(fake, yes=True) is False and fake.posts == [], "an active ONGOING request is not doubled")
    fake.reqs = [{"id": "r0", "attributes": {"accessType": "ONGOING", "stoppedDueToInactivity": True}},
                 {"id": "r2", "attributes": {"accessType": "ONE_TIME_SNAPSHOT"}}]
    check(request(fake, yes=False) is False and fake.posts == [], "a dry run writes nothing")
    check(request(fake, yes=True) is True and len(fake.posts) == 1
          and fake.posts[0][1]["data"]["attributes"]["accessType"] == "ONGOING",
          "a stopped request or a snapshot does not count as active; --yes posts ONGOING")

    # Links.
    check(campaign_link("123456", "instagram") ==
          f"https://apps.apple.com/app/id{APP_ID}?pt=123456&ct=instagram&mt=8", "a campaign link")
    for pt, ct, label in (("", "x", "an empty provider token"), ("12a", "x", "a non-digit token"),
                          ("1", "X", "an uppercase campaign"), ("1", "a" * 41, "a campaign over 40"),
                          ("1", "a b", "a space in a campaign")):
        try:
            campaign_link(pt, ct)
            check(False, f"refuses {label}")
        except ValueError:
            check(True, f"refuses {label}")
    check(all(re.fullmatch(r"[a-z0-9_-]{1,40}", c) for c in CHANNELS) and len(set(CHANNELS)) == len(CHANNELS),
          "every channel is a valid, unique token")

    print("✓ asc-report self-test" if ok else "✗ asc-report self-test")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("verb", nargs="?", choices=("status", "request", "funnel", "links"))
    ap.add_argument("--detailed", action="store_true", help="funnel: campaign, referrer, page")
    ap.add_argument("--pt", default=os.environ.get("ASC_PROVIDER_TOKEN"),
                    help="links: the provider token (or ASC_PROVIDER_TOKEN)")
    ap.add_argument("--yes", action="store_true", help="request: write; without it a dry run")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.verb:
        ap.error("a verb or --self-test is required")
    if a.verb == "links":
        try:
            for ch in CHANNELS:
                print(f"{ch:12} {campaign_link(a.pt, ch)}")
        except ValueError as e:
            raise SystemExit(f"✗ {e}")
        return 0
    api = ASC(key_path())
    if a.verb == "status":
        status(api)
    elif a.verb == "request":
        request(api, a.yes)
    else:
        funnel_verb(api, a.detailed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
