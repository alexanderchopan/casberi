#!/usr/bin/env python3
"""Self-test for scripts/worker-gate.py, in a scratch git repo against a stub
`gh`. No network, no GitHub.

Proves: the switch stops workers; an owner's `claude-stop` issue stops them
and a stranger's does not; the daily cap counts worker commits from the last
24h only; a red nightly first seen at or after a worker commit makes it a
suspect until it is reverted or cleared, and a red that predates it does not;
no `gh` fails closed; `issues` lists only the owner's, never `claude-needs-you`;
`diff-check` refuses a denied path, a deletion and an oversize diff, and allows
an ordinary one. Then each rule is broken in a copy of the gate, and the
fixture must fail.

Usage: scripts/worker-gate-selftest.py [--verbose]
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
GATE = ROOT / "scripts/worker-gate.py"
VERBOSE = "--verbose" in sys.argv

STUB = r'''#!/usr/bin/env python3
import json, os, sys
st = json.load(open(os.environ["STUB_STATE"]))
a = sys.argv[1:]
if a[:2] == ["issue", "list"]:
    labels = {a[i + 1] for i, x in enumerate(a) if x == "--label"}
    author = next((a[i + 1] for i, x in enumerate(a) if x == "--author"), None)
    print(json.dumps([i for i in st["issues"]
                      if labels <= {l["name"] for l in i["labels"]} and i.get("state", "open") == "open"
                      and (author is None or i["author"]["login"] == author)]))
    sys.exit(0)
sys.exit(2)
'''


class Rig:
    def __init__(self, tmp, gate):
        self.tmp = pathlib.Path(tmp)
        self.gate = gate
        self.repo = self.tmp / "repo"
        self.repo.mkdir()
        self.state = self.tmp / "gh.json"
        self.stub = self.tmp / "gh"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.issues = []
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        (self.repo / ".claude").mkdir()
        self.cfg = json.loads((ROOT / ".claude/workers.json").read_text())
        self.cfg["enabled"] = True
        self.save_cfg()
        (self.repo / "app.swift").write_text("let a = 1\n")
        self.commit("start")

    def git(self, *args, env=None):
        return subprocess.run(["git", "-C", str(self.repo)] + list(args), capture_output=True,
                              text=True, env=env).stdout.strip()

    def save_cfg(self):
        (self.repo / ".claude/workers.json").write_text(json.dumps(self.cfg))

    def commit(self, msg, worker=None, days_ago=0, path="app.swift"):
        p = self.repo / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text((p.read_text() if p.exists() else "") + f"// {msg}\n")
        self.git("add", "-A")
        body = msg + (f"\n\nClaude-Worker: #{worker}" if worker else "")
        env = dict(os.environ)
        if days_ago:
            stamp = f"{int(__import__('time').time()) - days_ago * 86400} +0000"
            env.update(GIT_COMMITTER_DATE=stamp, GIT_AUTHOR_DATE=stamp)
        self.git("commit", "-q", "-m", body, env=env)
        return self.git("rev-parse", "HEAD")

    def issue(self, number, labels, author="alexanderchopan", first_sha=None, title="t"):
        body = ""
        if first_sha:
            body = (f"<!-- finding:nightly-mac:k{number} -->\n<!-- finding-meta "
                    + json.dumps({"first_sha": first_sha[:7]}) + " -->\nx")
        self.issues.append(dict(number=number, title=title, body=body, author={"login": author},
                                labels=[{"name": l} for l in labels]))

    def run(self, *args, gh=True):
        self.state.write_text(json.dumps({"issues": self.issues}))
        env = dict(os.environ, STUB_STATE=str(self.state), WORKER_GATE_ROOT=str(self.repo),
                   WORKER_GATE_REF="main", WORKER_GATE_FETCH="0",
                   FINDINGS_GH=str(self.stub) if gh else str(self.tmp / "no-gh"))
        r = subprocess.run([sys.executable, str(self.gate)] + list(args), env=env,
                           capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr


def fixture(gate):
    bad = []

    def check(name, cond):
        if not cond:
            bad.append(name)

    with tempfile.TemporaryDirectory() as tmp:
        r = Rig(tmp, gate)
        code, out = r.run("check")
        check("an enabled gate with nothing wrong lets workers run", code == 0)

        r.cfg["enabled"] = False; r.save_cfg()
        code, out = r.run("check")
        check("the switch off stops workers", code == 1 and "switch is off" in out)
        r.cfg["enabled"] = True; r.save_cfg()

        r.issue(90, ["claude-stop"], author="stranger")
        code, out = r.run("check")
        check("a stranger's stop issue is ignored", code == 0)
        r.issue(91, ["claude-stop"])
        code, out = r.run("check")
        check("the owner's stop issue stops workers", code == 1 and "#91" in out)
        r.issues = [i for i in r.issues if i["number"] != 91]
        r.issue(92, [], title="Stop workers, something is off")
        code, out = r.run("check")
        check("the owner's issue titled Stop workers stops them, no label needed", code == 1 and "#92" in out)
        r.issues = [i for i in r.issues if i["number"] != 92]
        r.issue(93, [], author="stranger", title="Stop workers")
        code, out = r.run("check")
        check("a stranger's Stop workers title is ignored", code == 0)

        code, out = r.run("check", gh=False)
        check("no gh fails closed", code == 1 and "failing closed" in out)

    with tempfile.TemporaryDirectory() as tmp:
        r = Rig(tmp, gate)
        r.commit("old worker fix", worker=1, days_ago=3)
        r.commit("w2", worker=2)
        r.commit("w3", worker=3)
        code, out = r.run("check")
        check("two worker commits in 24h are under a cap of 3", code == 0)
        r.commit("w4", worker=4)
        code, out = r.run("check")
        check("the third worker commit in 24h reaches the cap", code == 1 and "daily cap" in out)

    with tempfile.TemporaryDirectory() as tmp:
        r = Rig(tmp, gate)
        before = r.commit("a human commit before the suspect")
        r.issue(50, ["claude", "source:nightly-mac"], first_sha=before)
        code, out = r.run("check")
        check("a red that predates a worker commit makes no suspect", code == 0)

        w = r.commit("worker change", worker=5, path="fix.swift")
        after = r.commit("the nightly ran here")
        r.issue(51, ["claude", "source:nightly-mac"], first_sha=after)
        code, out = r.run("check")
        check("a red first seen after a worker commit makes it a suspect",
              code == 1 and "suspect " + w[:9] in out and "#51" in out)

        r.cfg["cleared"] = [w]; r.save_cfg()
        code, out = r.run("check")
        check("a cleared suspect no longer stops workers", code == 0)
        r.cfg["cleared"] = []; r.save_cfg()

        msg = r.tmp / "msg"
        r.git("revert", "--no-commit", w)
        msg.write_text(f"Revert\n\nThis reverts commit {w}.\n")
        code, out = r.run("revert-ok", str(msg))
        check("an exact revert of a worker commit is allowed", code == 0)
        (r.repo / "app.swift").write_text("tampered\n")
        r.git("add", "-A")
        code, out = r.run("revert-ok", str(msg))
        check("a 'revert' carrying other changes is refused", code == 1 and "not the inverse" in out)
        r.git("reset", "-q", "--hard")
        r.git("revert", "--no-commit", after)
        msg.write_text(f"Revert\n\nThis reverts commit {after}.\n")
        code, out = r.run("revert-ok", str(msg))
        check("a revert of a non-worker commit is refused", code == 1 and "not a worker commit" in out)
        r.git("reset", "-q", "--hard")
        r.git("revert", "--no-edit", w)
        code, out = r.run("check")
        check("a reverted suspect no longer stops workers", code == 0)

    with tempfile.TemporaryDirectory() as tmp:
        r = Rig(tmp, gate)
        r.issue(60, ["claude"], author="stranger", title="stranger")
        r.issue(61, ["claude", "claude-needs-you"], title="held")
        r.issue(62, ["claude"], title="ours")
        code, out = r.run("issues")
        titles = {i["title"] for i in json.loads(out)} if code == 0 else set()
        check("issues lists the owner's", "ours" in titles)
        check("issues never lists a stranger's", "stranger" not in titles)
        check("issues never lists one held for the owner", "held" not in titles)

        (r.repo / "app.swift").write_text("let a = 2\n")
        r.git("add", "-A")
        code, out = r.run("diff-check", "--staged")
        check("an ordinary diff is allowed", code == 0)
        r.git("reset", "-q")
        r.git("checkout", "--", "app.swift")

        (r.repo / "scripts").mkdir(exist_ok=True)
        (r.repo / "scripts/x-selftest.sh").write_text("true\n")
        r.git("add", "-A")
        code, out = r.run("diff-check", "--staged")
        check("a check file is refused", code == 1 and "x-selftest.sh" in out)
        r.git("reset", "-q")
        (r.repo / "scripts/x-selftest.sh").unlink()

        (r.repo / "Casberi/Sub").mkdir(parents=True)
        (r.repo / "Casberi/Sub/Info.plist").write_text("<plist/>\n")
        r.git("add", "-A")
        code, out = r.run("diff-check", "--staged")
        check("a nested denied file is refused", code == 1 and "Info.plist" in out)
        r.git("reset", "-q")
        (r.repo / "Casberi/Sub/Info.plist").unlink()

        r.git("rm", "-q", "app.swift")
        code, out = r.run("diff-check", "--staged")
        check("a deletion is refused", code == 1 and "deletes app.swift" in out)
        r.git("reset", "-q", "HEAD", "app.swift")
        r.git("checkout", "--", "app.swift")

        (r.repo / "big.swift").write_text("x\n" * 400)
        r.git("add", "-A")
        code, out = r.run("diff-check", "--staged")
        check("an oversize diff is refused", code == 1 and "changed lines" in out)
    return bad


MUTATIONS = [
    ("switch ignored", 'if not cfg.get("enabled"):', "if False:"),
    ("strangers obeyed", 'if (i.get("author") or {}).get("login") == cfg["owner"]]', "]"),
    ("stop title ignored", 'or (i.get("title") or "").strip().lower().startswith("stop workers")]', "]"),
    ("no cap", "if n >= cap:", "if False:"),
    ("no suspects", "hit = [n for n, first in reds if descends(sha, first)]", "hit = []"),
    ("revert ignored", " or reverted(sha):", ":"),
    ("held listed", 'if labels & {"claude-needs-you", "claude-stop"}:', "if False:"),
    ("deny list ignored", 'if matches(path, cfg.get("deny_paths", [])):', "if False:"),
    ("deletions allowed", 'if kind.startswith("D"):', "if False:"),
    ("no line cap", 'if lines > int(cfg.get("max_lines", 300)):', "if False:"),
    ("any revert passes", "if not staged or staged != inverse:", "if False:"),
    ("reverts non-worker", 'if not re.search(rf"^{TRAILER}", body, re.M):', "if False:"),
    ("fails open", 'reasons.append(f"cannot read the queue or main ({e}) — failing closed")', "pass"),
]


def main():
    print("▶ worker-gate self-test")
    failures = fixture(GATE)
    for f in failures:
        print(f"  FAIL {f}")
    if VERBOSE and not failures:
        print("  ok   every rule as designed")
    src = GATE.read_text()
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, old, new) in enumerate(MUTATIONS):
            if old not in src:
                failures.append(f"mutation '{name}' did not apply")
                print(f"  FAIL mutation '{name}' did not apply — its anchor moved")
                continue
            path = pathlib.Path(tmp) / f"m{i}.py"
            path.write_text(src.replace(old, new, 1))
            if fixture(path):
                if VERBOSE:
                    print(f"  ok   mutation '{name}' is caught")
            else:
                failures.append(name)
                print(f"  FAIL mutation '{name}' passed the fixture — a rule has no check")
    if failures:
        print(f"✗ worker-gate self-test: {len(failures)} failure(s)")
        return 1
    print(f"✓ worker-gate self-test ({len(MUTATIONS)} mutations caught)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
