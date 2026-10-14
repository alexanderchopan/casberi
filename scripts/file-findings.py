#!/usr/bin/env python3
"""File what an unattended run found as GitHub issues labelled `claude`.

WHY THIS EXISTS (2026-10-14). The nightlies and the screen audit wrote their
findings to logs under `scripts/output/`, on the Mac, read only when a session
happened to open them. Nothing turned a red night into work. This makes every
finding ONE open issue in the repo, where a session (on the Mac or in the
cloud, which cannot see `scripts/output/`) picks it up without being told.

THE QUEUE'S RULES.

  * One issue per finding, identified by a fingerprint in its body
    (`<!-- finding:<source>:<key> -->`), never by its title. A finding seen
    again updates its issue's "Last seen" and count; it never files twice.
  * A finding that comes back after its issue was closed REOPENS that issue,
    so a regression keeps its history in one thread.
  * A run passed `--complete` closes every open issue of its source that it no
    longer reports. A run that died partway, or reached only some checks, must
    not pass it: it would close what it never looked at.
  * `--resolve <key>` closes one finding by name, for a source whose keys are
    not stable enough to close by absence (the screen audit's).
  * The repo is PUBLIC. A field that looks like a credential withholds the
    whole finding (it is not filed, and counts as still present, so nothing
    closes on it); absolute paths are written relative to the repo or `~`.
  * It never fails its caller. No `gh`, no auth or a refused call prints one
    `findings:` line and exits 0: a nightly's verdict is about the app, not
    about GitHub.

Usage:
  file-findings.py --source nightly-live --sha abc123 [--complete] \\
      [--finding KEY TITLE BODY]... [--resolve KEY]...
  file-findings.py --json findings.json
      {"source": …, "sha": …, "complete": bool,
       "findings": [{"key": …, "title": …, "body": …}], "resolved": [keys]}
  file-findings.py --list --source screen-audit     # open keys, one per line

`FINDINGS_GH` names the gh binary (the self-test's stub);
`FINDINGS_DRY_RUN=1` prints the calls instead of making them.
Self-test: scripts/file-findings-selftest.py.
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LABEL = "claude"
MARK = re.compile(r"<!-- finding:([^:\s]+):(.+?) -->")
META = re.compile(r"<!-- finding-meta (\{.*?\}) -->")
BODY_CAP = 6000
TITLE_CAP = 120

# Shapes that must never reach a public issue. Wide on purpose: a withheld
# finding costs a look at the local log; a filed key costs a rotation.
CREDENTIAL = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY"
    r"|\bgh[pousr]_[A-Za-z0-9]{20,}"
    r"|\bgithub_pat_[A-Za-z0-9_]{20,}"
    r"|\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}"
    r"|\bAKIA[0-9A-Z]{16}\b"
    r"|\bxox[abprs]-[A-Za-z0-9-]{10,}"
    r"|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    r"|nostr\+walletconnect://"
    r"|\b[xyzt]prv[1-9A-HJ-NP-Za-km-z]{20,}"
    r"|\b(?:password|passwd|secret|api[_-]?key|token)\s*[=:]\s*\S{8,}",
    re.IGNORECASE,
)


def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def scrub_paths(text):
    text = text.replace(str(ROOT) + "/", "").replace(str(ROOT), ".")
    home = os.path.expanduser("~")
    if home and home != "/":
        text = text.replace(home, "~")
    return text


def leaks(*fields):
    return any(CREDENTIAL.search(f or "") for f in fields)


def find_gh():
    named = os.environ.get("FINDINGS_GH")
    if named:
        return named if os.path.exists(named) else None
    found = shutil.which("gh")
    if found:
        return found
    # A LaunchAgent's PATH is /usr/bin:/bin:… — Homebrew's gh is not on it.
    for p in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if os.path.exists(p):
            return p
    return None


class GH:
    def __init__(self, binary, dry):
        self.binary, self.dry, self.errors = binary, dry, []

    def run(self, args, stdin=None, mutates=True):
        if self.dry and mutates:
            print("dry-run: gh " + " ".join(args))
            return ""
        try:
            r = subprocess.run([self.binary] + args, input=stdin, cwd=str(ROOT),
                               capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired) as e:
            self.errors.append(f"gh {args[0]} {args[1] if len(args) > 1 else ''}: {e}")
            return None
        if r.returncode != 0:
            self.errors.append(f"gh {' '.join(args[:2])}: {r.stderr.strip()[:200]}")
            return None
        return r.stdout

    def issues(self, source, state):
        out = self.run(["issue", "list", "--label", LABEL, "--label", f"source:{source}",
                        "--state", state, "--limit", "300", "--json", "number,title,body,state"],
                       mutates=False)
        if out is None:
            return None
        try:
            return json.loads(out or "[]")
        except ValueError:
            self.errors.append("gh issue list: unreadable JSON")
            return None


def fingerprint(issue):
    m = MARK.search(issue.get("body") or "")
    return (m.group(1), m.group(2)) if m else None


def meta_of(body):
    m = META.search(body or "")
    if not m:
        return {}
    try:
        return json.loads(m.group(1))
    except ValueError:
        return {}


def compose(source, f, sha, meta):
    detail = scrub_paths(f["body"]).strip()
    if len(detail) > BODY_CAP:
        detail = detail[:BODY_CAP] + "\n… (cut; the full log is on the Mac)"
    m = json.dumps(meta, sort_keys=True)
    seen = (f"**Source:** `{source}` · **First seen:** {meta['first']} at `{meta['first_sha']}`"
            f" · **Last seen:** {meta['last']} at `{sha}` · **Runs:** {meta['count']}")
    return (f"<!-- finding:{source}:{f['key']} -->\n<!-- finding-meta {m} -->\n"
            f"{seen}\n\n{detail}\n\n---\n"
            f"Filed by `scripts/file-findings.py`. It closes on the first complete "
            f"`{source}` run that no longer reports it.\n")


def clean_key(key):
    # The key lives inside an HTML comment and a `:`-split marker.
    return re.sub(r"\s+", " ", key.replace("-->", "").replace("\n", " ")).strip()[:100]


def file_findings(source, sha, findings, resolved, complete, gh):
    stats = dict(opened=0, updated=0, reopened=0, closed=0, withheld=0)
    if gh.dry:
        print(f"dry-run: label {LABEL}, source:{source}")
    else:
        gh.run(["label", "create", LABEL, "--force", "--color", "D97757",
                "--description", "Work for Claude, filed by an unattended run"])
        gh.run(["label", "create", f"source:{source}", "--force", "--color", "C5DEF5",
                "--description", f"Filed by {source}"])

    open_ = gh.issues(source, "open")
    if open_ is None:
        return stats, False
    closed = gh.issues(source, "closed") or []
    by_key_open = {fp[1]: i for i in open_ if (fp := fingerprint(i)) and fp[0] == source}
    by_key_closed = {}
    for i in closed:
        fp = fingerprint(i)
        if fp and fp[0] == source and fp[1] not in by_key_closed:
            by_key_closed[fp[1]] = i

    present = set()
    for f in findings:
        f = dict(f, key=clean_key(f["key"]))
        present.add(f["key"])
        if leaks(f["key"], f["title"], f["body"]):
            stats["withheld"] += 1
            print(f"findings: withheld one {source} finding — a field looked like a credential; "
                  f"read the local log", file=sys.stderr)
            continue
        title = scrub_paths(f["title"]).strip()[:TITLE_CAP] or f["key"]
        if f["key"] in by_key_open:
            issue = by_key_open[f["key"]]
            meta = meta_of(issue["body"]) or {"first": now(), "first_sha": sha, "count": 0}
            meta.update(last=now(), count=int(meta.get("count", 0)) + 1)
            if gh.run(["issue", "edit", str(issue["number"]), "--body-file", "-"],
                      stdin=compose(source, f, sha, meta)) is not None:
                stats["updated"] += 1
        elif f["key"] in by_key_closed:
            issue = by_key_closed[f["key"]]
            meta = meta_of(issue["body"]) or {"first": now(), "first_sha": sha, "count": 0}
            meta.update(last=now(), count=int(meta.get("count", 0)) + 1)
            n = str(issue["number"])
            if gh.run(["issue", "reopen", n, "--comment",
                       f"Back on {now()} at `{sha}`.\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_"]) is not None:
                gh.run(["issue", "edit", n, "--body-file", "-"], stdin=compose(source, f, sha, meta))
                stats["reopened"] += 1
        else:
            meta = {"first": now(), "first_sha": sha, "last": now(), "count": 1}
            if gh.run(["issue", "create", "--title", title, "--label", LABEL,
                       "--label", f"source:{source}", "--body-file", "-"],
                      stdin=compose(source, f, sha, meta)) is not None:
                stats["opened"] += 1

    to_close = {clean_key(k) for k in resolved}
    if complete:
        to_close |= set(by_key_open) - present
    for key in sorted(to_close):
        issue = by_key_open.get(key)
        if not issue:
            continue
        why = ("no longer reported by a complete run" if key not in {clean_key(k) for k in resolved}
               else "resolved by the run")
        if gh.run(["issue", "close", str(issue["number"]), "--reason", "completed", "--comment",
                   f"Green on {now()} at `{sha}`: {why}.\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_"]) is not None:
            stats["closed"] += 1
    return stats, True


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--source")
    p.add_argument("--sha", default="")
    p.add_argument("--complete", action="store_true")
    p.add_argument("--finding", nargs=3, action="append", default=[], metavar=("KEY", "TITLE", "BODY"))
    p.add_argument("--resolve", action="append", default=[])
    p.add_argument("--json")
    p.add_argument("--list", action="store_true")
    a = p.parse_args(argv)

    findings = [{"key": k, "title": t, "body": b} for k, t, b in a.finding]
    source, sha, complete, resolved = a.source, a.sha, a.complete, list(a.resolve)
    if a.json:
        try:
            doc = json.loads(pathlib.Path(a.json).read_text())
            source = doc.get("source", source)
            sha = doc.get("sha", sha)
            complete = bool(doc.get("complete", complete))
            findings += [{"key": f["key"], "title": f.get("title", f["key"]), "body": f.get("body", "")}
                         for f in doc.get("findings", [])]
            resolved += doc.get("resolved", [])
        except (OSError, ValueError, KeyError, TypeError) as e:
            print(f"findings: skipped — unreadable {a.json}: {e}")
            return 0
    if not source or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", source):
        print("findings: skipped — --source must be lowercase words joined by '-'")
        return 0
    if not sha:
        sha = (subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True).stdout.strip() or "unknown")

    binary = find_gh()
    if not binary:
        print(f"findings: skipped — no gh on PATH ({source})")
        return 0
    gh = GH(binary, os.environ.get("FINDINGS_DRY_RUN") == "1")
    if not gh.dry and gh.run(["auth", "status"], mutates=False) is None:
        print(f"findings: skipped — gh is not signed in ({source})")
        return 0

    if a.list:
        for i in gh.issues(source, "open") or []:
            fp = fingerprint(i)
            if fp and fp[0] == source:
                print(f"#{i['number']}\t{fp[1]}\t{i['title']}")
        return 0

    stats, reached = file_findings(source, sha, findings, resolved, complete, gh)
    line = " ".join(f"{k}={v}" for k, v in stats.items())
    if not reached:
        line = "skipped — could not list issues"
    print(f"findings: {source} {line}" + (f" errors={len(gh.errors)}" if gh.errors else ""))
    for e in gh.errors[:5]:
        print(f"  {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
