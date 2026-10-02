#!/usr/bin/env python3
"""asc-screenshots.py — replace an App Store version's screenshots.

  asc-screenshots.py read                          every set on the editable iOS version
  asc-screenshots.py replace --iphone DIR --ipad DIR          (dry run)
  asc-screenshots.py replace --iphone DIR --ipad DIR --yes    (delete old, upload new)

Built for the 2.0 resubmission (prd §1077, the 4.1(a) rejection): the old sets
carried an icon pile and a logo grid, and Apple's only remedy is new pictures.
`replace` targets the iOS version in an editable state (prepare, rejected,
developer-rejected), DELETES every screenshot in the iPhone 6.5" and iPad 12.9"
sets, then uploads the PNGs in each folder, in filename order. Nothing is sent
without --yes; a dry run lists what would be deleted and uploaded.

Credentials as asc-copy.py: the .p8 at ASC_KEY_PATH (staged by
`scripts/dev-keys.sh get-file asc-p8 <path>`), never printed.
"""
import argparse, hashlib, json, os, subprocess, sys, time
import urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6788637831"
KEY_ID = os.environ.get("ASC_KEY_ID", "TR287WZD72")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "2152ec98-0a7c-477a-9c4a-e1c478a3a106")
EDITABLE = {"PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED", "METADATA_REJECTED"}
SETS = {"iphone": "APP_IPHONE_65", "ipad": "APP_IPAD_PRO_3GEN_129"}


class ASC:
    def __init__(self, key_path):
        self.key_path, self._token, self._minted = key_path, None, 0

    def token(self):
        if not self._token or time.time() - self._minted > 900:
            self._token = subprocess.run(
                [sys.executable, os.path.join(ROOT, "scripts", "asc-jwt.py"),
                 KEY_ID, ISSUER_ID, self.key_path],
                check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
            self._minted = time.time()
        return self._token

    def call(self, method, path, body=None):
        url = path if path.startswith("http") else API + path
        req = urllib.request.Request(
            url, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + self.token(),
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise SystemExit(f"✗ {method} {path} → HTTP {e.code}: {detail[:400]}")


def editable_version(asc):
    vs = asc.call("GET", f"/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    for v in vs:
        if v["attributes"]["appStoreState"] in EDITABLE:
            return v
    raise SystemExit("✗ no editable iOS version (" +
                     ", ".join(f'{v["attributes"]["versionString"]} {v["attributes"]["appStoreState"]}' for v in vs) + ")")


def localization(asc, version_id):
    locs = asc.call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    return next(l for l in locs if l["attributes"]["locale"] == "en-US")


def sets_by_type(asc, loc_id):
    data = asc.call("GET", f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50")["data"]
    return {s["attributes"]["screenshotDisplayType"]: s for s in data}


def shots(asc, set_id):
    return asc.call("GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]


def upload(asc, set_id, path):
    data = open(path, "rb").read()
    made = asc.call("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in made["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                     headers={h["name"]: h["value"] for h in op["requestHeaders"]})
        urllib.request.urlopen(req, timeout=120).read()
    asc.call("PATCH", f"/appScreenshots/{made['id']}", {"data": {
        "type": "appScreenshots", "id": made["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return made["id"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("verb", choices=["read", "replace"])
    ap.add_argument("--iphone"); ap.add_argument("--ipad"); ap.add_argument("--yes", action="store_true")
    a = ap.parse_args()
    asc = ASC(os.environ.get("ASC_KEY_PATH", "/tmp/asc.p8"))
    v = editable_version(asc)
    loc = localization(asc, v["id"])
    have = sets_by_type(asc, loc["id"])
    print(f'iOS {v["attributes"]["versionString"]} ({v["attributes"]["appStoreState"]}), en-US')
    for t, s in sorted(have.items()):
        print(f"  {t}: {len(shots(asc, s['id']))} screenshot(s)")
    if a.verb == "read":
        return
    plan = []
    for key, display in SETS.items():
        folder = getattr(a, key)
        if not folder:
            continue
        files = sorted(os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith(".png"))
        if not files:
            raise SystemExit(f"✗ no PNGs in {folder}")
        plan.append((display, files))
        old = len(shots(asc, have[display]["id"])) if display in have else 0
        print(f"→ {display}: delete {old}, upload {len(files)}: " + ", ".join(os.path.basename(f) for f in files))
    if not a.yes:
        print("— dry run: pass --yes to replace —")
        return
    for display, files in plan:
        if display in have:
            set_id = have[display]["id"]
            for s in shots(asc, set_id):
                asc.call("DELETE", f"/appScreenshots/{s['id']}")
        else:
            set_id = asc.call("POST", "/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                "relationships": {"appStoreVersionLocalization": {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]["id"]
        for f in files:
            print(f"  ↑ {display} {os.path.basename(f)} → {upload(asc, set_id, f)}")
    print("✓ replaced; re-reading")
    for t, s in sorted(sets_by_type(asc, loc["id"]).items()):
        print(f"  {t}: {len(shots(asc, s['id']))} screenshot(s)")


if __name__ == "__main__":
    main()
