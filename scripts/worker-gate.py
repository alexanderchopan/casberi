#!/usr/bin/env python3
"""The gate every Claude worker passes: whether it may run, which issues it may
take, and what it may commit. The rules it enforces are in docs/workers.md.

WHY THIS EXISTS (2026-10-14). Workers take `claude` issues and push fixes to
`main` with no review in between, into a PUBLIC repo, where anyone can comment
on an issue. Rules a worker only reads are rules a worker can talk itself out
of; this makes each one a check that fails closed.

  check        May a worker run now? Fails on any of:
                 · `.claude/workers.json` says `"enabled": false` (the switch);
                 · an OPEN issue filed by the owner, labelled `claude-stop` or
                   titled "Stop workers…" (the switch you can flip from your
                   phone, where only existing labels can be picked);
                 · `max_worker_commits_per_day` worker commits on main in 24h;
                 · a SUSPECT: a worker commit that a red nightly descends from
                   (an open `gating_sources` issue first seen at or after it),
                   not reverted and not cleared. Revert it, or clear it.
               Fails closed: no `gh`, no auth, or no fetch means no.
  issues       The issues a worker may take, as JSON: open, labelled `claude`,
               filed by the owner, not labelled `claude-needs-you`. Bodies
               only; comments are never read (anyone can write one).
  diff-check   May this diff be committed? (`--staged`, or a `<base>..<head>`
               range.) Fails on a `deny_paths` file, a deleted file, more than
               `max_files` files or `max_lines` changed lines.
  revert-ok <msgfile>
               Is this commit an exact revert of a worker commit? Its message
               names a full sha (`This reverts commit …`, as `git revert`
               writes), that commit carries the worker trailer, and the staged
               diff is that commit's inverse (equal `git patch-id`). A revert
               passes while a suspect stops everything else: undoing is
               always allowed.
  clear <sha>  The owner's verdict that a suspect commit did not cause the red:
               adds it to `cleared`. Commit the config change yourself.

A worker commit is one whose message carries a `Claude-Worker: #<issue>`
trailer, or any commit made with `CLAUDE_WORKER=1` in the environment, which a
worker's launcher sets (and which then requires the trailer, so the commit is
counted). `scripts/hooks/commit-msg` runs `revert-ok`, or `check` and
`diff-check --staged`, on every such commit, so a worker that skips the gate
cannot commit on a machine with the hooks installed.

Env (the self-test's): WORKER_GATE_ROOT (repo), WORKER_GATE_REF (default
origin/main), WORKER_GATE_FETCH=0 (skip the fetch), FINDINGS_GH (gh binary).
Self-test: scripts/worker-gate-selftest.py.
"""

import fnmatch
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(os.environ.get("WORKER_GATE_ROOT") or pathlib.Path(__file__).resolve().parent.parent)
CONFIG = ROOT / ".claude/workers.json"
REF = os.environ.get("WORKER_GATE_REF", "origin/main")
TRAILER = "Claude-Worker:"
META = re.compile(r"<!-- finding-meta (\{.*?\}) -->")
MARK = re.compile(r"<!-- finding:([^:\s]+):(.+?) -->")


def config():
    return json.loads(CONFIG.read_text())


def git(*args, check=True):
    r = subprocess.run(["git", "-C", str(ROOT)] + list(args), capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args[:2])}: {r.stderr.strip()[:200]}")
    return r


def find_gh():
    named = os.environ.get("FINDINGS_GH")
    if named:
        return named if os.path.exists(named) else None
    for p in (shutil.which("gh"), "/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if p and os.path.exists(p):
            return p
    return None


def gh_json(args):
    gh = find_gh()
    if not gh:
        raise RuntimeError("no gh on PATH")
    r = subprocess.run([gh] + args, cwd=str(ROOT), capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:2])}: {r.stderr.strip()[:200]}")
    return json.loads(r.stdout or "[]")


def open_issues(cfg, label):
    rows = gh_json(["issue", "list", "--label", label, "--state", "open", "--limit", "300",
                    "--json", "number,title,body,author,labels"])
    # Filed by the owner, or not ours to act on: labels need write access,
    # but a stranger's issue must never steer a worker even if someone adds one.
    return [i for i in rows if (i.get("author") or {}).get("login") == cfg["owner"]]


def stop_issues(cfg):
    rows = gh_json(["issue", "list", "--state", "open", "--author", cfg["owner"], "--limit", "300",
                    "--json", "number,title,body,author,labels"])
    rows = [i for i in rows if (i.get("author") or {}).get("login") == cfg["owner"]]
    return [i for i in rows
            if "claude-stop" in {l.get("name") for l in i.get("labels") or []}
            or (i.get("title") or "").strip().lower().startswith("stop workers")]


def worker_commits(since):
    out = git("log", REF, f"--since={since}", "--format=%H%x09%cI%x09%s", f"--grep=^{TRAILER}").stdout
    return [line.split("\t") for line in out.splitlines() if line.strip()]


def reverted(sha):
    return bool(git("log", REF, "--format=%H", f"--grep=This reverts commit {sha}").stdout.strip())


def descends(ancestor, sha):
    full = git("rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}", check=False).stdout.strip()
    if not full:
        return False
    return git("merge-base", "--is-ancestor", ancestor, full, check=False).returncode == 0


def suspects(cfg):
    window = f"{int(cfg.get('suspect_window_hours', 72))}.hours.ago"
    commits = worker_commits(window)
    if not commits:
        return []
    cleared = set(cfg.get("cleared", []))
    reds = []
    for source in cfg.get("gating_sources", []):
        for i in open_issues(cfg, f"source:{source}"):
            m = META.search(i.get("body") or "")
            if not m:
                continue
            try:
                first = json.loads(m.group(1)).get("first_sha", "")
            except ValueError:
                continue
            if first:
                reds.append((i["number"], first))
    out = []
    for sha, _, subject in commits:
        if sha in cleared or any(sha.startswith(c) for c in cleared if len(c) >= 7) or reverted(sha):
            continue
        hit = [n for n, first in reds if descends(sha, first)]
        if hit:
            out.append((sha, subject, hit))
    return out


def cmd_check():
    reasons = []
    try:
        cfg = config()
    except (OSError, ValueError) as e:
        print(f"✗ workers stopped: unreadable {CONFIG.name}: {e}")
        return 1
    if not cfg.get("enabled"):
        reasons.append("the switch is off (`enabled: false` in .claude/workers.json)")
    if os.environ.get("WORKER_GATE_FETCH", "1") != "0":
        if git("fetch", "--quiet", "origin", "main", check=False).returncode != 0:
            reasons.append("could not fetch origin/main — the gate reads main, and will not guess")
    try:
        stops = stop_issues(cfg)
        if stops:
            reasons.append("stopped by the owner: " + ", ".join(f"#{i['number']} {i['title']}" for i in stops))
        n = len(worker_commits("24.hours.ago"))
        cap = int(cfg.get("max_worker_commits_per_day", 3))
        if n >= cap:
            reasons.append(f"daily cap: {n} worker commits on main in 24h (cap {cap})")
        for sha, subject, issues in suspects(cfg):
            reasons.append(f"suspect {sha[:9]} \"{subject}\" — red since: "
                           + ", ".join(f"#{n}" for n in issues)
                           + f". Revert it (git revert {sha[:9]}) or the owner clears it")
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as e:
        reasons.append(f"cannot read the queue or main ({e}) — failing closed")
    if reasons:
        print("✗ workers stopped:")
        for r in reasons:
            print(f"  · {r}")
        return 1
    print("✓ workers may run")
    return 0


def cmd_issues():
    try:
        cfg = config()
        rows = open_issues(cfg, "claude")
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as e:
        print(f"✗ cannot list issues: {e}", file=sys.stderr)
        return 1
    out = []
    for i in rows:
        labels = {l.get("name") for l in i.get("labels") or []}
        if labels & {"claude-needs-you", "claude-stop"}:
            continue
        m = MARK.search(i.get("body") or "")
        out.append(dict(number=i["number"], title=i["title"],
                        source=m.group(1) if m else "owner", key=m.group(2) if m else "",
                        body=i.get("body") or ""))
    print(json.dumps(out, indent=1))
    return 0


def matches(path, globs):
    for g in globs:
        if fnmatch.fnmatchcase(path, g):
            return True
        if g.endswith("/**") and (path == g[:-3] or path.startswith(g[:-2])):
            return True
        if g.startswith("**/") and fnmatch.fnmatchcase(pathlib.PurePosixPath(path).name, g[3:]):
            return True
    return False


def cmd_diff_check(spec):
    cfg = config()
    args = ["diff", "--cached"] if spec == "--staged" else ["diff", spec]
    status = git(*(args + ["--name-status", "--no-renames"])).stdout.splitlines()
    numstat = git(*(args + ["--numstat", "--no-renames"])).stdout.splitlines()
    reasons, files, lines = [], [], 0
    for row in status:
        parts = row.split("\t")
        if len(parts) < 2:
            continue
        kind, path = parts[0], parts[-1]
        files.append(path)
        if kind.startswith("D"):
            reasons.append(f"deletes {path} — a worker never deletes a file")
        if matches(path, cfg.get("deny_paths", [])):
            reasons.append(f"touches {path} — on the deny list in .claude/workers.json")
    for row in numstat:
        a, d = (row.split("\t") + ["0", "0"])[:2]
        lines += (int(a) if a.isdigit() else 0) + (int(d) if d.isdigit() else 0)
    if len(files) > int(cfg.get("max_files", 8)):
        reasons.append(f"{len(files)} files (cap {cfg.get('max_files', 8)}) — too large for an unreviewed push")
    if lines > int(cfg.get("max_lines", 300)):
        reasons.append(f"{lines} changed lines (cap {cfg.get('max_lines', 300)}) — too large for an unreviewed push")
    if not files:
        reasons.append("nothing to commit")
    if reasons:
        print("✗ diff refused:")
        for r in reasons:
            print(f"  · {r}")
        return 1
    print(f"✓ diff allowed: {len(files)} files, {lines} lines")
    return 0


def patch_id(diff_text):
    r = subprocess.run(["git", "-C", str(ROOT), "patch-id", "--stable"], input=diff_text,
                       capture_output=True, text=True)
    return (r.stdout.split() or [""])[0]


def cmd_revert_ok(msgfile):
    msg = pathlib.Path(msgfile).read_text()
    m = re.search(r"^This reverts commit ([0-9a-f]{40})", msg, re.M)
    if not m:
        print("✗ not a revert: no `This reverts commit <full sha>` line")
        return 1
    sha = m.group(1)
    body = git("log", "-1", "--format=%B", sha, check=False).stdout
    if not re.search(rf"^{TRAILER}", body, re.M):
        print(f"✗ {sha[:9]} is not a worker commit — a worker reverts only its own kind")
        return 1
    staged = patch_id(git("diff", "--cached").stdout)
    inverse = patch_id(git("diff", sha, f"{sha}^").stdout)
    if not staged or staged != inverse:
        print(f"✗ the staged diff is not the inverse of {sha[:9]}")
        return 1
    print(f"✓ exact revert of worker commit {sha[:9]}")
    return 0


def cmd_clear(sha):
    full = git("rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}", check=False).stdout.strip()
    if not full:
        print(f"✗ no commit {sha}")
        return 1
    cfg = config()
    if full not in cfg.setdefault("cleared", []):
        cfg["cleared"].append(full)
    CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"✓ cleared {full[:9]} — commit .claude/workers.json to make it stand")
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    cmd = argv[0]
    if cmd == "check":
        return cmd_check()
    if cmd == "issues":
        return cmd_issues()
    if cmd == "diff-check" and len(argv) == 2:
        return cmd_diff_check(argv[1])
    if cmd == "revert-ok" and len(argv) == 2:
        return cmd_revert_ok(argv[1])
    if cmd == "clear" and len(argv) == 2:
        return cmd_clear(argv[1])
    print(f"unknown: {' '.join(argv)} — see --help")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
