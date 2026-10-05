#!/usr/bin/env python3
"""Expire every TestFlight build older than the one external testers can
install, per platform, so nobody keeps asking about an old build.

An expired build stops launching ("This beta has expired") and TestFlight
offers the newest; the tester's data stays (app group + iCloud). It cannot
be undone. Per platform this KEEPS the newest build whose beta review is
APPROVED and everything newer (still in review, or internal-only), so no
tester is ever left with nothing to update to, and any build an App Store
version is still waiting on.

Dry run by default; --yes applies.

  scripts/dev-keys.sh get-file asc-p8 /tmp/asc-expire.p8
  ASC_KEY_ID=TR287WZD72 ASC_ISSUER_ID=2152ec98-0a7c-477a-9c4a-e1c478a3a106 \
    ASC_KEY_PATH=/tmp/asc-expire.p8 scripts/testflight-expire-old.py [--yes]
  rm -f /tmp/asc-expire.p8
"""
import json, os, subprocess, sys, urllib.request, urllib.error

APP_ID = "6788637831"
API = "https://api.appstoreconnect.apple.com"
JWT_GEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asc-jwt.py")


def jwt():
    return subprocess.run(
        ["python3", JWT_GEN, os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"],
         os.environ["ASC_KEY_PATH"]],
        stdout=subprocess.PIPE, check=True, text=True).stdout.strip()


def call(method, url, body=None, token=None):
    req = urllib.request.Request(url if url.startswith("http") else API + url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode()
    with urllib.request.urlopen(req) as r:
        return r.status, (json.loads(r.read() or b"{}"))


def builds(token):
    url = (f"/v1/builds?filter[app]={APP_ID}&filter[expired]=false&limit=200"
           "&include=preReleaseVersion,betaAppReviewSubmission"
           "&fields[builds]=version,uploadedDate,expired,processingState,preReleaseVersion,betaAppReviewSubmission"
           "&fields[preReleaseVersions]=platform,version"
           "&fields[betaAppReviewSubmissions]=betaReviewState")
    rows, included = [], {}
    while url:
        _, page = call("GET", url, token=token)
        rows += page["data"]
        for inc in page.get("included", []):
            included[(inc["type"], inc["id"])] = inc["attributes"]
        url = page.get("links", {}).get("next")
    out = []
    for b in rows:
        rel = b["relationships"]
        pre = rel["preReleaseVersion"]["data"]
        sub = rel["betaAppReviewSubmission"]["data"]
        pv = included.get(("preReleaseVersions", pre["id"]), {}) if pre else {}
        rs = included.get(("betaAppReviewSubmissions", sub["id"]), {}) if sub else {}
        out.append({"id": b["id"], "build": int(b["attributes"]["version"]),
                    "platform": pv.get("platform", "?"), "marketing": pv.get("version", "?"),
                    "review": rs.get("betaReviewState", "—"),
                    "state": b["attributes"]["processingState"]})
    return out


# A build an App Store version is still waiting on. Expiring it can strand the
# review (2026-10-04: the first run expired iOS 2.0.2's build 736 while it sat
# WAITING_FOR_REVIEW). Only a version that is live or gone lets its build go.
SETTLED = {"READY_FOR_SALE", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE",
           "REPLACED_WITH_NEW_VERSION", "READY_FOR_DISTRIBUTION"}


def store_held(token):
    _, page = call("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=50&include=build"
                          "&fields[appStoreVersions]=appStoreState,build", token=token)
    return {v["relationships"]["build"]["data"]["id"]
            for v in page["data"]
            if v["attributes"]["appStoreState"] not in SETTLED
            and v["relationships"]["build"]["data"]}


def main():
    apply = "--yes" in sys.argv
    token = jwt()
    rows = builds(token)
    held = store_held(token)
    doomed = []
    for platform in sorted({r["platform"] for r in rows}):
        mine = sorted((r for r in rows if r["platform"] == platform), key=lambda r: -r["build"])
        approved = [r for r in mine if r["review"] == "APPROVED"]
        if not approved:
            print(f"{platform}: no APPROVED build, keeping all {len(mine)}")
            continue
        floor = approved[0]["build"]
        keep = [r for r in mine if r["build"] >= floor]
        old = [r for r in mine if r["build"] < floor and r["id"] not in held]
        for r in mine:
            if r["build"] < floor and r["id"] in held:
                print(f"{platform}: keep {r['build']}, an App Store version is waiting on it")
        kept = ", ".join(f"{r['build']} ({r['marketing']}, {r['review']})" for r in keep)
        print(f"{platform}: keep {kept}")
        gone = ", ".join(str(r["build"]) for r in old) or "none"
        print(f"{platform}: expire {len(old)}: {gone}")
        doomed += old
    if not apply:
        print(f"\ndry run, {len(doomed)} to expire; pass --yes to apply")
        return
    failed = 0
    for i, r in enumerate(doomed):
        if i and i % 150 == 0:
            token = jwt()  # a token lives ~20min; hundreds of PATCHes outlast it
        body = {"data": {"type": "builds", "id": r["id"], "attributes": {"expired": True}}}
        try:
            call("PATCH", f"/v1/builds/{r['id']}", body, token)
            print(f"expired {r['platform']} {r['build']}")
        except urllib.error.HTTPError as e:
            failed += 1
            print(f"FAILED {r['platform']} {r['build']}: {e.code} {e.read()[:200]!r}")
    print(f"\n{len(doomed) - failed} expired, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
