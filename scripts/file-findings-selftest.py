#!/usr/bin/env python3
"""Self-test for scripts/file-findings.py, against a stub `gh` that keeps its
issues in a JSON file. No network, no GitHub.

Proves: a finding files once and updates after; a closed finding reopens
rather than filing twice; only a `--complete` run closes by absence; `--resolve`
closes by name; a credential-shaped field files nothing and closes nothing; a
path under the repo or home is never written absolute; a missing or signed-out
`gh` exits 0; another source's issues are never touched.

Then a mutation pass: each rule above is broken in a copy of the filer, and the
same fixture must fail — a check that passes against a broken filer certifies
nothing.

Usage: scripts/file-findings-selftest.py [--verbose]
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILER = ROOT / "scripts/file-findings.py"
VERBOSE = "--verbose" in sys.argv

STUB = r'''#!/usr/bin/env python3
import json, os, sys
state_path = os.environ["STUB_STATE"]
st = json.load(open(state_path)) if os.path.exists(state_path) else {"issues": [], "authed": True}
a = sys.argv[1:]
def opt(name, many=False):
    vals = [a[i + 1] for i, x in enumerate(a) if x == name and i + 1 < len(a)]
    return vals if many else (vals[0] if vals else None)
def save():
    json.dump(st, open(state_path, "w"))
def issue(n):
    return next(i for i in st["issues"] if i["number"] == int(n))
if a[:2] == ["auth", "status"]:
    sys.exit(0 if st.get("authed", True) else 1)
if a[:2] == ["label", "create"]:
    sys.exit(0)
if a[:2] == ["issue", "list"]:
    labels, state = set(opt("--label", True)), opt("--state")
    out = [dict(number=i["number"], title=i["title"], body=i["body"], state=i["state"])
           for i in st["issues"] if labels <= set(i["labels"]) and i["state"] == state]
    print(json.dumps(out)); sys.exit(0)
if a[:2] == ["issue", "create"]:
    n = len(st["issues"]) + 1
    st["issues"].append(dict(number=n, title=opt("--title"), body=sys.stdin.read(),
                             labels=opt("--label", True), state="open", comments=[]))
    save(); sys.exit(0)
if a[:2] == ["issue", "edit"]:
    issue(a[2])["body"] = sys.stdin.read(); save(); sys.exit(0)
if a[:2] in (["issue", "close"], ["issue", "reopen"]):
    i = issue(a[2]); i["state"] = "closed" if a[1] == "close" else "open"
    i["comments"].append(opt("--comment") or ""); save(); sys.exit(0)
sys.stderr.write("stub: unknown call " + " ".join(a)); sys.exit(2)
'''

failures = []
QUIET = False   # a mutation run's own misses are the point; report only the verdict


def check(name, cond):
    if cond:
        if VERBOSE and not QUIET:
            print(f"  ok   {name}")
    else:
        failures.append(name)
        if not QUIET:
            print(f"  FAIL {name}")


class Rig:
    def __init__(self, tmp, filer):
        self.tmp, self.filer = pathlib.Path(tmp), filer
        self.stub = self.tmp / "gh"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.state = self.tmp / "state.json"

    def run(self, *args, gh=True):
        env = dict(os.environ, STUB_STATE=str(self.state),
                   FINDINGS_GH=str(self.stub) if gh else str(self.tmp / "no-gh"))
        r = subprocess.run([sys.executable, str(self.filer), "--sha", "abc1234"] + list(args),
                           env=env, capture_output=True, text=True)
        return r

    def issues(self, source=None):
        st = json.loads(self.state.read_text()) if self.state.exists() else {"issues": []}
        return [i for i in st["issues"] if source is None or f"source:{source}" in i["labels"]]

    def seed(self, data):
        self.state.write_text(json.dumps(data))


def fixture(filer):
    """Every rule, against one filer. Returns the names that failed."""
    global failures
    saved, failures = failures, []
    with tempfile.TemporaryDirectory() as tmp:
        rig = Rig(tmp, filer)
        rig.seed({"issues": [], "authed": True})

        r = rig.run("--source", "nightly-live", "--complete",
                    "--finding", "Peer — getLogs rejected", "✗ Peer — getLogs rejected: x", "row one",
                    "--finding", "L2BEAT — axis renamed", "✗ L2BEAT — axis renamed", f"log {ROOT}/scripts/output/live.log home {os.path.expanduser('~')}/x")
        check("exit 0 on a filing run", r.returncode == 0)
        live = rig.issues("nightly-live")
        check("two findings file two issues", len(live) == 2)
        check("every issue wears the claude label", all("claude" in i["labels"] for i in live))
        bodies = " ".join(i["body"] for i in live)
        check("no absolute repo path in a body", str(ROOT) not in bodies)
        home = os.path.expanduser("~")
        check("no absolute home path in a body", home in ("", "/") or home + "/" not in bodies)

        rig.run("--source", "nightly-live", "--complete",
                "--finding", "Peer — getLogs rejected", "✗ Peer — getLogs rejected: y", "row two",
                "--finding", "L2BEAT — axis renamed", "✗ L2BEAT — axis renamed", "again")
        live = rig.issues("nightly-live")
        check("a finding seen again files nothing new", len(live) == 2)
        peer = next(i for i in live if "Peer" in i["title"])
        check("a finding seen again counts its runs", '"count": 2' in peer["body"])
        check("a finding seen again carries the new detail", "row two" in peer["body"])

        rig.run("--source", "nightly-live", "--finding", "Peer — getLogs rejected", "Peer", "x")
        l2 = next(i for i in rig.issues("nightly-live") if "L2BEAT" in i["title"])
        check("an incomplete run closes nothing by absence", l2["state"] == "open")

        rig.run("--source", "nightly-live", "--complete",
                "--finding", "Peer — getLogs rejected", "Peer", "x")
        l2 = next(i for i in rig.issues("nightly-live") if "L2BEAT" in i["title"])
        check("a complete run closes what it no longer reports", l2["state"] == "closed")
        peer = next(i for i in rig.issues("nightly-live") if "Peer" in i["title"])
        check("a complete run keeps what it still reports open", peer["state"] == "open")

        rig.run("--source", "nightly-live", "--complete",
                "--finding", "L2BEAT — axis renamed", "✗ L2BEAT — axis renamed", "back",
                "--finding", "Peer — getLogs rejected", "Peer", "x")
        live = rig.issues("nightly-live")
        check("a returning finding reopens, never files twice", len(live) == 2)
        l2 = next(i for i in live if "L2BEAT" in i["title"])
        check("a returning finding's issue is open again", l2["state"] == "open")

        rig.run("--source", "screen-audit", "--finding", "settings-tray", "Settings tray clipped", "shot")
        rig.run("--source", "screen-audit", "--complete")
        check("another source's issues are untouched by a complete run",
              all(i["state"] == "open" for i in rig.issues("nightly-live")))
        sa = rig.issues("screen-audit")
        check("a complete run with no findings closes its source's issues", sa and sa[0]["state"] == "closed")

        rig.run("--source", "screen-audit", "--finding", "home-lede", "Home lede", "shot")
        rig.run("--source", "screen-audit", "--resolve", "home-lede")
        lede = next(i for i in rig.issues("screen-audit") if i["title"] == "Home lede")
        check("--resolve closes a finding by name", lede["state"] == "closed")

        before = len(rig.issues())
        rig.run("--source", "nightly-mac", "--finding", "k", "step failed",
                "token=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        check("a credential-shaped body files nothing", len(rig.issues()) == before)
        rig.run("--source", "nightly-mac", "--finding", "k2", "fine", "fine")
        rig.run("--source", "nightly-mac", "--complete", "--finding", "k2", "x",
                "-----BEGIN EC PRIVATE KEY-----")
        k2 = rig.issues("nightly-mac")
        check("a withheld finding counts as present, so it does not close", k2 and k2[0]["state"] == "open")

        r = rig.run("--source", "nightly-live", "--finding", "a", "b", "c", gh=False)
        check("no gh exits 0", r.returncode == 0 and "skipped" in r.stdout)
        st = json.loads(rig.state.read_text()); st["authed"] = False; rig.seed(st)
        n = len(rig.issues())
        r = rig.run("--source", "nightly-live", "--finding", "new", "b", "c")
        check("a signed-out gh exits 0 and files nothing", r.returncode == 0 and len(rig.issues()) == n)
    got, failures = failures, saved
    return got


def mutated(tmp, name, old, new):
    src = FILER.read_text()
    if old not in src:
        failures.append(f"mutation '{name}' did not apply — its anchor moved")
        print(f"  FAIL mutation '{name}' did not apply — its anchor moved")
        return None
    # The copy lives in a temp dir, so pin its ROOT to the repo's: otherwise
    # every mutant fails the path check and the others prove nothing.
    src = src.replace("ROOT = pathlib.Path(__file__).resolve().parent.parent",
                      f"ROOT = pathlib.Path({str(ROOT)!r})", 1)
    path = pathlib.Path(tmp) / f"m-{name}.py"
    path.write_text(src.replace(old, new, 1))
    return path


MUTATIONS = [
    ("files twice", "if f[\"key\"] in by_key_open:", "if False:"),
    ("never reopens", "elif f[\"key\"] in by_key_closed:", "elif False:"),
    ("closes when incomplete", "    if complete:\n        to_close", "    if True:\n        to_close"),
    ("no credential guard", "if leaks(f[\"key\"], f[\"title\"], f[\"body\"]):", "if False:"),
    ("absolute paths", "detail = scrub_paths(f[\"body\"]).strip()", "detail = f[\"body\"].strip()"),
    ("withheld closes", "        present.add(f[\"key\"])\n", ""),
    ("ignores --resolve", "to_close = {clean_key(k) for k in resolved}", "to_close = set()"),
]


def main():
    global QUIET
    print("▶ file-findings self-test")
    got = fixture(FILER)
    failures.extend(got)
    QUIET = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, old, new in MUTATIONS:
            path = mutated(tmp, name, old, new)
            if path is None:
                continue
            if fixture(path):
                if VERBOSE:
                    print(f"  ok   mutation '{name}' is caught")
            else:
                failures.append(f"mutation '{name}' passed the fixture")
                print(f"  FAIL mutation '{name}' passed the fixture — a rule has no check")
    if failures:
        print(f"✗ file-findings self-test: {len(failures)} failure(s)")
        return 1
    print(f"✓ file-findings self-test ({len(MUTATIONS)} mutations caught)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
