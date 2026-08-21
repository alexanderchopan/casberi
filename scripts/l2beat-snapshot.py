#!/usr/bin/env python3
"""Generate the bundled L2BEAT directory from L2BEAT's own published assessments.

WHAT THIS TAKES AND WHAT IT DELIBERATELY LEAVES (prd §428). L2BEAT publishes a great deal —
total value secured, activity, costs, contracts, permissions, DA layers — and their project
page is 4.5MB. This reads the RISK TABLE, the STAGE and the MILESTONES and nothing else.
Pulling in the analytics would make this a different and much larger feature, and none of it
is a judgment somebody independent made about whether your money can leave.

WHY A SNAPSHOT AT ALL, given the live read is one 290KB request for all 105 projects: so the
directory opens instantly and offline on a device that has never synced, and so a FOLLOWER
has L2BEAT's incident history without naming a chain first. The live read then supersedes it
for anything the sweep has seen. Bundled baseline + live enrichment, the §419 shape.

WHY WE NEVER COMPUTE A STAGE OR A SCORE: L2BEAT publishes its own composite and this cites
it. Nothing here ranks chains, sums sentiments, or picks a "safest" — that is an editorial
act, and putting our judgment behind their name is §83.

Usage:
  scripts/l2beat-snapshot.py             # regenerate the Swift directory in place
  scripts/l2beat-snapshot.py --check     # fail if the checked-in file is stale (no writes)
  scripts/l2beat-snapshot.py --icons     # also refresh the bundled chain marks
  scripts/l2beat-snapshot.py --self-test
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import gzip
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "Casberi", "Casberi", "Model", "L2beatDirectory.swift")

SITE = "l2beat.com"
SUMMARY_URL = f"https://{SITE}/api/scaling/summary"
RAW = "https://raw.githubusercontent.com/l2beat/l2beat/main"
CONFIG_PATH = "packages/config/src/projects/{pid}/{pid}.ts"

# L2BEAT's five risk axes, in their own order, paired with the Swift case that carries each.
#
# DRIVEN BY THIS TABLE AND NEVER BY THE PAYLOAD'S ORDER. Measured 2026-08-21: all 105
# projects list the five in one identical order, which is exactly the condition under which
# depending on it stays invisible until the day it changes.
AXES = (
    ("Sequencer Failure", "sequencerFailure"),
    ("State Validation", "stateValidation"),
    ("Data Availability", "dataAvailability"),
    ("Exit Window", "exitWindow"),
    ("Proposer Failure", "proposerFailure"),
)
AXIS_BY_NAME = dict(AXES)

# Their sentiment vocabulary. An unrecognised one becomes `unknown` and is REPORTED — never
# `good`, which is the one wrong default that reads as a clean bill of health.
SENTIMENTS = ("good", "warning", "bad", "neutral")

STAGES = {"Stage 0": "stage0", "Stage 1": "stage1", "Stage 2": "stage2",
          "Not applicable": "notApplicable"}

# The chains the demo furnishes. Chosen to exercise the range rather than to flatter the
# card: one on the top rung, one at the bottom with a flagged sequencer, and Arbitrum
# because its Exit Window is the measured `regular` second-reading case (see below).
DEMO_CHAINS = ("arbitrum", "base", "linea")

USER_AGENT = "Casberi/1.0 (+https://casberi.app) l2beat-snapshot"

# MEASURED 2026-08-21: `l2beat.com/api/*` sits behind Cloudflare and answers `error code:
# 1015` to a burst — the fifth quick request in a row was refused. The app makes ONE request
# per sweep so it never meets this, but a generator walking 105 config files does, so every
# fetch here is paced and retried.
PACE_SECONDS = 0.15


def fetch(url: str, timeout: int = 60, attempts: int = 3) -> bytes:
    last: Exception | None = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"}
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
                return raw
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise SystemExit(f"failed to read {url}: {last}")


# --------------------------------------------------------------------------------------
# Distilling the risk table
# --------------------------------------------------------------------------------------


def read_note(block) -> dict | None:
    """L2BEAT's own qualification on a risk — the `regular` or `warning` sub-block.

    MEASURED 2026-08-21 AND THE SHARPEST TRAP IN THIS PAYLOAD. Thirteen risks carry a
    `regular` block and four a `warning` block. Arbitrum — the most-watched chain on the
    list — has Exit Window `value: "None", sentiment: bad` at the top with
    `regular: {value: "10d", sentiment: warning}` underneath: the top level is the EMERGENCY
    case and `regular` is the ordinary one. Dropping it throws away the number an Arbitrum
    user actually wants. Merging it into the top-level sentiment would be us editing
    L2BEAT's call. So it is carried alongside, and the app draws both.
    """
    if not isinstance(block, dict):
        return None
    value = block.get("value")
    if not value:
        return None
    return {
        "value": value,
        "sentiment": sentiment_of(block.get("sentiment")),
        "description": " ".join((block.get("description") or "").split()) or None,
    }


def sentiment_of(raw) -> str:
    if isinstance(raw, str) and raw.lower() in SENTIMENTS:
        return raw.lower()
    if raw is not None:
        print(f"  ! unknown sentiment {raw!r} — kept as unknown", file=sys.stderr)
    return "unknown"


def distill_risks(raw) -> list[dict]:
    """Reduce one project's `risks` array to the five axes, in our order."""
    if not isinstance(raw, list):
        return []
    by_axis: dict[str, dict] = {}
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        case = AXIS_BY_NAME.get(name)
        if case is None:
            # An unrecognised axis is DROPPED rather than guessed into a slot — a five-cell
            # strip must never gain a sixth cell from a rename — but it is reported, because
            # a silently missing axis reads as a chain L2BEAT declined to assess.
            print(f"  ! unknown risk axis {name!r} — dropped", file=sys.stderr)
            continue
        value = entry.get("value")
        if not value:
            print(f"  ! {name}: empty value — dropped", file=sys.stderr)
            continue
        if case in by_axis:
            continue
        by_axis[case] = {
            "axis": case,
            "value": value,
            "sentiment": sentiment_of(entry.get("sentiment")),
            "description": " ".join((entry.get("description") or "").split()),
            "second": read_note(entry.get("regular")) or read_note(entry.get("warning")),
        }
    return [by_axis[case] for _, case in AXES if case in by_axis]


def distill(key: str, block: dict) -> dict:
    """One project, reduced to what a row and a card draw.

    BOTH IDENTIFIERS ARE KEPT AND BOTH ARE LOAD-BEARING. `id` is the project's own directory
    name in L2BEAT's repo, which the milestone read joins on; `slug` is the segment in their
    public URL. Measured 2026-08-21 they differ for TEN of the 105 — OP Mainnet
    (`optimism`/`op-mainnet`), ZKsync Era (`zksync2`/`zksync-era`), World Chain, Ronin and
    six more — so joining on the wrong one loses four of the biggest chains on the list, and
    loses them SILENTLY: a chain with no milestone file reads exactly like a chain with no
    milestones.
    """
    pid = block.get("id") or key
    return {
        "id": pid,
        "slug": block.get("slug") or pid,
        "name": block.get("name") or pid,
        "layer": block.get("type") if block.get("type") in ("layer2", "layer3") else "layer2",
        "hostChain": block.get("hostChain"),
        "category": block.get("category"),
        "stage": block.get("stage"),
        "underReview": bool(block.get("isUnderReview")),
        "archived": bool(block.get("isArchived")),
        "risks": distill_risks(block.get("risks")),
    }


# --------------------------------------------------------------------------------------
# Milestones
# --------------------------------------------------------------------------------------

MILESTONE_KINDS = ("incident", "general")


def array_block(field: str, text: str) -> str | None:
    start = text.find(f"{field}: [")
    if start < 0:
        return None
    depth = 0
    started = False
    out = []
    for ch in text[start:]:
        if ch == "[":
            depth += 1
            started = True
        if started:
            out.append(ch)
        if ch == "]":
            depth -= 1
            if started and depth <= 0:
                break
    return "".join(out) or None


def objects(block: str) -> list[str]:
    """Split `[ {…}, {…} ]` into its top-level objects, brace-counted and quote-aware."""
    out: list[str] = []
    depth = 0
    current: list[str] = []
    quote: str | None = None
    escaped = False
    for ch in block:
        if quote:
            current.append(ch)
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            if depth > 0:
                current.append(ch)
            quote = ch
            continue
        if ch == "{":
            depth += 1
            if depth == 1:
                current = []
                continue
        if ch == "}":
            depth -= 1
            if depth == 0:
                out.append("".join(current))
                current = []
                continue
        if depth > 0:
            current.append(ch)
    return out


def field(name: str, obj: str) -> str | None:
    """A quoted string for `<name>:`, anchored so `url:` cannot match inside `sourceUrl:`."""
    for m in re.finditer(rf"(?<![A-Za-z0-9_]){re.escape(name)}:\s*", obj):
        rest = obj[m.end():]
        if not rest or rest[0] not in "'\"":
            continue
        quote = rest[0]
        value: list[str] = []
        escaped = False
        for ch in rest[1:]:
            if escaped:
                value.append(ch)
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == quote:
                return " ".join("".join(value).split())
            value.append(ch)
    return None


def milestones_in(text: str, pid: str) -> list[dict]:
    block = array_block("milestones", text)
    if not block:
        return []
    out = []
    for obj in objects(block):
        title = field("title", obj)
        raw_date = field("date", obj)
        if not title or not raw_date:
            continue
        day = raw_date[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
            continue
        kind = field("type", obj)
        out.append({
            "projectID": pid,
            "title": title,
            "summary": field("description", obj),
            # An unknown type stays `general` and STILL LANDS: a new milestone type is news
            # whether or not we have a word for it.
            "kind": kind if kind in MILESTONE_KINDS else "general",
            "day": day,
            "url": field("url", obj),
        })
    return out


def milestone_slug(title: str) -> str:
    words = re.split(r"[^a-z0-9]+", title.lower())
    return "-".join([w for w in words if w][:8])


# --------------------------------------------------------------------------------------
# Gathering
# --------------------------------------------------------------------------------------


def gather() -> dict:
    print(f"summary  {SUMMARY_URL}", file=sys.stderr)
    doc = json.loads(fetch(SUMMARY_URL))
    table = doc.get("projects")
    if not isinstance(table, dict) or not table:
        # The one shape assertion that cannot be recovered from: no projects key means the
        # site API moved, and writing an empty directory would report to every reader that
        # L2BEAT rates nothing.
        raise SystemExit("no `projects` in the summary — the site API's shape changed")
    projects = [distill(k, v) for k, v in table.items() if isinstance(v, dict)]
    projects.sort(key=lambda p: p["name"].lower())
    print(f"         {len(projects)} projects", file=sys.stderr)

    thin = [p["id"] for p in projects if len(p["risks"]) != 5]
    if thin:
        # Reported, never fatal: a project L2BEAT lists with fewer than five risks is still a
        # real chain and still belongs in the directory. But the strip is built for five, so
        # a growing list here is the signal that it needs a gate (see L2beatRating.swift).
        print(f"  ! {len(thin)} projects without all five risks: {', '.join(thin[:8])}",
              file=sys.stderr)

    # ---- Milestones, one config file per project -------------------------------------
    #
    # Joined on `id`, the repo directory name. See `distill` for why the slug would lose ten.
    def one(project: dict):
        url = f"{RAW}/{CONFIG_PATH.format(pid=project['id'])}"
        time.sleep(PACE_SECONDS)
        try:
            text = fetch(url, attempts=2).decode("utf-8", "replace")
        except SystemExit:
            return project["id"], None
        return project["id"], milestones_in(text, project["id"])

    found: dict[str, list[dict]] = {}
    unreadable: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for pid, got in pool.map(one, projects):
            if got is None:
                unreadable.append(pid)
            else:
                found[pid] = got

    if unreadable:
        # A project whose config we cannot read contributes no milestones, which is a hole in
        # a security feed. Named rather than silent, and fatal past a handful — a run that
        # quietly lost half the incidents would ship a directory claiming a quiet ecosystem.
        print(f"  ! no config file for {len(unreadable)}: {', '.join(unreadable[:10])}",
              file=sys.stderr)
        if len(unreadable) > 12:
            raise SystemExit(f"{len(unreadable)} projects unreadable — the repo layout changed")

    every = [m for ms in found.values() for m in ms]
    incidents = [m for m in every if m["kind"] == "incident"]
    incidents.sort(key=lambda m: (m["day"], m["projectID"]), reverse=True)
    print(f"         {len(every)} milestones, {len(incidents)} incidents", file=sys.stderr)

    demo_missing = [c for c in DEMO_CHAINS if not any(p["id"] == c for p in projects)]
    if demo_missing:
        raise SystemExit(f"demo chains missing from the summary: {', '.join(demo_missing)}")

    return {
        "generated": datetime.date.today().isoformat(),
        "projects": projects,
        # ONLY the incidents are bundled, and that is the tier split as data (prd §428):
        # FOLLOWING gets L2BEAT's incident history for every chain they cover, which is 33
        # rows and ~8KB; WATCHING a chain adds that chain's full timeline, read live. The
        # alternative — bundling all 226 — measured ~56KB of string literals compiled into
        # every shipped binary, which is the §419 `whyItMatters` decision with the same answer.
        "incidents": incidents,
        "milestoneCount": len(every),
    }


# --------------------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------------------


def swift_string(value) -> str:
    if value is None:
        return "nil"
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def optional_string(value) -> str:
    return "nil" if value in (None, "") else swift_string(value)


class Notes:
    """A dedup table for L2BEAT's risk sentences.

    MEASURED 2026-08-21: 525 risks carry 83,466 characters of description between them and
    only 110 DISTINCT sentences — L2BEAT writes one explanation per (value, axis) and reuses
    it across every chain with that reading. Emitting them inline is 83KB of literals in
    every shipped binary; emitting them once and indexing is under 20KB. That is what makes
    bundling the COMPLETE risk table affordable, where §419 had to drop Walletbeat's longest
    prose from its snapshot to stay under budget.
    """

    def __init__(self) -> None:
        self.items: list[str] = []
        self.index: dict[str, int] = {}

    def ref(self, text: str | None) -> str:
        if not text:
            return '""'
        if text not in self.index:
            self.index[text] = len(self.items)
            self.items.append(text)
        return f"note({self.index[text]})"

    def optional_ref(self, text: str | None) -> str:
        return "nil" if not text else self.ref(text)


def render(snapshot: dict) -> str:
    notes = Notes()
    lines: list[str] = []
    add = lines.append

    # Bodies are rendered FIRST so the note table is complete before it is emitted.
    project_lines: list[str] = []
    for p in snapshot["projects"]:
        project_lines.append("\t\tL2beatProject(")
        project_lines.append(f"\t\t\tid: {swift_string(p['id'])},")
        project_lines.append(f"\t\t\tslug: {swift_string(p['slug'])},")
        project_lines.append(f"\t\t\tname: {swift_string(p['name'])},")
        project_lines.append(f"\t\t\tlayer: .{p['layer']},")
        project_lines.append(f"\t\t\thostChain: {optional_string(p['hostChain'])},")
        project_lines.append(f"\t\t\tcategory: {optional_string(p['category'])},")
        stage = STAGES.get(p["stage"])
        project_lines.append(f"\t\t\tstage: {('.' + stage) if stage else 'nil'},")
        project_lines.append(f"\t\t\tunderReview: {'true' if p['underReview'] else 'false'},")
        project_lines.append(f"\t\t\tarchived: {'true' if p['archived'] else 'false'},")
        project_lines.append("\t\t\trisks: [")
        for r in p["risks"]:
            second = "nil"
            if r["second"]:
                s = r["second"]
                second = ("L2beatRiskNote(value: %s, sentiment: .%s, explanation: %s)"
                          % (swift_string(s["value"]), s["sentiment"],
                             notes.optional_ref(s["description"])))
            project_lines.append(
                "\t\t\t\tL2beatRisk(axis: .%s, value: %s, sentiment: .%s, explanation: %s, second: %s),"
                % (r["axis"], swift_string(r["value"]), r["sentiment"],
                   notes.ref(r["description"]), second)
            )
        project_lines.append("\t\t\t]),")

    incident_lines: list[str] = []
    for m in snapshot["incidents"]:
        incident_lines.append(
            "\t\tSeed(project: %s, day: %s, title: %s, summary: %s, url: %s),"
            % (swift_string(m["projectID"]), swift_string(m["day"]),
               swift_string(m["title"]), notes.optional_ref(m["summary"]),
               optional_string(m["url"]))
        )

    add("// Generated by scripts/l2beat-snapshot.py — DO NOT EDIT BY HAND.")
    add("//")
    add("// L2BEAT's risk assessment for every chain it covers, plus the incidents it has")
    add("// recorded. Regenerate at ship time; `scripts/l2beat-snapshot.py --check` fails the")
    add("// build when this file no longer matches what L2BEAT publishes.")
    add("//")
    add("// These are L2BEAT'S judgments, not ours. Nothing here ranks chains or folds five")
    add("// risks into a verdict — the one composite shown anywhere is their own stage (prd §428).")
    add("")
    add("import Foundation")
    add("")
    add("enum L2beatDirectory {")
    add(f"\t/// The day this snapshot was taken from {SITE}.")
    add(f"\tstatic let generated = {swift_string(snapshot['generated'])}")
    add("")
    add("\t/// L2BEAT's risk sentences, stored once and indexed.")
    add("\t///")
    add("\t/// 525 risks carry only 110 distinct explanations between them — they write one")
    add("\t/// per reading and reuse it across every chain that shares it. Inline that is 83KB")
    add("\t/// of literals in the binary; indexed it is a fifth of that, which is what makes")
    add("\t/// bundling the COMPLETE table affordable rather than a counts-only summary.")
    add("\tprivate static let notes: [String] = [")
    for text in notes.items:
        add(f"\t\t{swift_string(text)},")
    add("\t]")
    add("")
    add("\tprivate static func note(_ index: Int) -> String {")
    add("\t\tindex >= 0 && index < notes.count ? notes[index] : \"\"")
    add("\t}")
    add("")
    add("\tstatic let projects: [L2beatProject] = [")
    lines.extend(project_lines)
    add("\t]")
    add("")
    add("\tstatic func project(_ id: String) -> L2beatProject? {")
    add("\t\tprojects.first { $0.id == id }")
    add("\t}")
    add("")
    add("\t/// L2BEAT's recorded INCIDENTS, across every chain they cover.")
    add("\t///")
    add("\t/// This is the follow tier as data (prd §428): following L2BEAT gets you these")
    add("\t/// without naming a chain, because an incident on a chain you do not use is still")
    add("\t/// how you learn what this ecosystem does. A chain's GENERAL milestones — launches,")
    add("\t/// upgrades, proof systems going live — arrive only for chains you watch, read live,")
    add("\t/// because there are 193 of them against these 33.")
    add("\tstruct Seed: Sendable, Equatable {")
    add("\t\tlet project: String")
    add("\t\tlet day: String")
    add("\t\tlet title: String")
    add("\t\tlet summary: String?")
    add("\t\tlet url: String?")
    add("\t}")
    add("")
    add("\tstatic let incidents: [Seed] = [")
    lines.extend(incident_lines)
    add("\t]")
    add("")
    add("\t/// The bundled incidents as milestones, dated and ready to land.")
    add("\tstatic var seededIncidents: [L2beatMilestone] {")
    add("\t\tincidents.compactMap { seed in")
    add("\t\t\tguard let date = L2beatNewsParse.date(fromISO: seed.day) else { return nil }")
    add("\t\t\treturn L2beatMilestone(")
    add("\t\t\t\tprojectID: seed.project, title: seed.title, summary: seed.summary,")
    add("\t\t\t\tkind: .incident, day: seed.day, date: date, url: seed.url)")
    add("\t\t}")
    add("\t}")
    add("")
    add("\t/// The chains the demo furnishes, with L2BEAT's real readings and real sentences —")
    add("\t/// so the furnished demo shows what the feature actually shows.")
    add("\tstatic let demoChains: [String] = [")
    for c in DEMO_CHAINS:
        add(f"\t\t{swift_string(c)},")
    add("\t]")
    add("}")
    add("")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------
# Self-test. A generator that cannot demonstrate it catches a bad snapshot certifies
# nothing, so every rule above is exercised against a fixture before it is trusted.
# --------------------------------------------------------------------------------------


def self_test() -> int:
    failures: list[str] = []

    def check(name: str, cond: bool) -> None:
        if cond:
            print(f"  ok   {name}")
        else:
            failures.append(name)
            print(f"  FAIL {name}")

    print("l2beat-snapshot self-test")

    # ---- Sentiment ------------------------------------------------------------------
    check("reads a known sentiment", sentiment_of("bad") == "bad")
    check("reads a capitalised sentiment", sentiment_of("Good") == "good")
    # The one wrong default that would read as a clean bill of health.
    check("an unknown sentiment is never good", sentiment_of("spicy") == "unknown")
    check("a missing sentiment is unknown", sentiment_of(None) == "unknown")

    # ---- Risks ----------------------------------------------------------------------
    raw = [
        {"name": "Exit Window", "value": "None", "sentiment": "bad",
         "description": "There is no window.",
         "regular": {"value": "10d", "sentiment": "warning", "description": "Ten days."}},
        {"name": "Sequencer Failure", "value": "Self sequence", "sentiment": "good",
         "description": "You can force a transaction."},
        {"name": "Teleportation Risk", "value": "Bad", "sentiment": "bad", "description": "x"},
    ]
    risks = distill_risks(raw)
    check("keeps only known axes", [r["axis"] for r in risks]
          == ["sequencerFailure", "exitWindow"])
    check("orders by OUR axis table, not the payload",
          risks[0]["axis"] == "sequencerFailure")
    # The Arbitrum case: the second reading is carried, never merged.
    exit_window = next(r for r in risks if r["axis"] == "exitWindow")
    check("carries the nested regular reading", exit_window["second"]["value"] == "10d")
    check("the nested reading keeps its own sentiment",
          exit_window["second"]["sentiment"] == "warning")
    check("the top-level sentiment is NOT softened by it", exit_window["sentiment"] == "bad")
    check('"None" is a value, not an absence', exit_window["value"] == "None")

    warn_only = distill_risks([
        {"name": "Exit Window", "value": "Not applicable", "sentiment": "neutral",
         "description": "Donations.",
         "warning": {"value": "One address can withdraw all funds.", "sentiment": "bad"}}])
    check("a `warning` block is read when there is no `regular`",
          warn_only[0]["second"]["sentiment"] == "bad")
    check("a warning block with no description survives",
          warn_only[0]["second"]["description"] is None)

    check("an empty value is dropped",
          distill_risks([{"name": "Exit Window", "value": "", "sentiment": "bad"}]) == [])
    check("a duplicate axis yields one cell, not two",
          len(distill_risks([
              {"name": "Exit Window", "value": "a", "sentiment": "bad", "description": ""},
              {"name": "Exit Window", "value": "b", "sentiment": "good", "description": ""}])) == 1)

    # ---- Projects -------------------------------------------------------------------
    op = distill("optimism", {"id": "optimism", "slug": "op-mainnet", "name": "OP Mainnet",
                              "type": "layer2", "stage": "Stage 1", "isUnderReview": False,
                              "hostChain": "Ethereum", "category": "Optimistic Rollup",
                              "risks": raw})
    check("keeps the repo id", op["id"] == "optimism")
    check("keeps the public slug apart from it", op["slug"] == "op-mainnet")
    check("keeps the stage verbatim", op["stage"] == "Stage 1")
    l3 = distill("x", {"type": "layer3", "name": "X"})
    check("an L3 keeps its layer", l3["layer"] == "layer3")
    check("an unknown type falls back to layer2",
          distill("y", {"type": "layer9"})["layer"] == "layer2")
    check("a missing name falls back to the id", distill("z", {})["name"] == "z")

    # ---- Milestones -----------------------------------------------------------------
    config = """
    export const arbitrum: ScalingProject = {
      id: ProjectId('arbitrum'),
      milestones: [
        {
          title: 'Bridge emergency upgrade',
          url: 'https://forum.example/t/action-24-05-2026/30910',
          date: '2026-05-24T00:00:00Z',
          description: 'Security Council patches a DoS. No funds at risk.',
          type: 'incident',
        },
        {
          title: 'Nitro upgrade',
          date: '2022-08-31T00:00:00Z',
          type: 'general',
        },
      ],
      display: { name: 'Arbitrum One' },
    }
    """
    got = milestones_in(config, "arbitrum")
    check("reads both milestones", len(got) == 2)
    check("reads the incident type", got[0]["kind"] == "incident")
    check("keeps only the day from an ISO date", got[0]["day"] == "2026-05-24")
    check("reads the citation", got[0]["url"].endswith("/30910"))
    check("a milestone with no description survives", got[1]["summary"] is None)
    check("an untyped milestone defaults to general",
          milestones_in("milestones: [{title: 'x', date: '2024-01-02T00:00:00Z'}]", "p")[0]["kind"]
          == "general")
    check("an unknown type is kept as general, never dropped",
          milestones_in("milestones: [{title: 'x', date: '2024-01-02', type: 'gossip'}]", "p")[0]["kind"]
          == "general")
    check("a milestone with no date is dropped",
          milestones_in("milestones: [{title: 'x', type: 'incident'}]", "p") == [])
    check("a file with no milestones yields none", milestones_in("export const x = {}", "p") == [])

    # The anchored field read: `url:` must not be found inside `sourceUrl:`.
    check("field names are anchored",
          field("url", "sourceUrl: 'https://wrong', url: 'https://right'") == "https://right")
    check("a brace inside a URL does not end the object",
          len(objects("[{title: 'a{b}c', date: '2024-01-01'}, {title: 'd'}]")) == 2)
    check("a comma inside a quoted string does not split an object",
          field("title", objects("[{title: 'a, b', date: 'x'}]")[0]) == "a, b")
    check("hard-wrapped prose collapses to spaces",
          field("description", "description:\n  'one\n   two'") == "one two")

    check("slug is lowercased and hyphenated",
          milestone_slug("Bridge Emergency Upgrade!") == "bridge-emergency-upgrade")
    check("slug is capped at eight words",
          len(milestone_slug(" ".join(str(i) for i in range(20))).split("-")) == 8)

    # ---- Rendering ------------------------------------------------------------------
    check('escapes a quote in a name', swift_string('He said "hi"') == '"He said \\"hi\\""')
    check("escapes a backslash", swift_string("a\\b") == '"a\\\\b"')
    check("renders nil for a missing optional", optional_string(None) == "nil")
    check("renders nil for an empty optional", optional_string("") == "nil")

    notes = Notes()
    a = notes.ref("shared sentence")
    b = notes.ref("shared sentence")
    c = notes.ref("other")
    check("the note table dedupes", a == b and a != c and len(notes.items) == 2)
    check("an empty note is a literal, not an index", notes.ref("") == '""')
    check("a nil note stays nil", notes.optional_ref(None) == "nil")

    out = render({"generated": "2026-08-21", "projects": [op, l3],
                  "incidents": [{"projectID": "arbitrum", "day": "2026-05-24",
                                 "title": "Bridge emergency upgrade",
                                 "summary": "A DoS was patched.",
                                 "url": "https://forum.example/x"}],
                  "milestoneCount": 2})
    check("renders both projects", out.count("L2beatProject(") == 2)
    check("renders the slug apart from the id",
          'id: "optimism"' in out and 'slug: "op-mainnet"' in out)
    check("renders the stage as a case", "stage: .stage1" in out)
    check("renders a nil stage for a project with none", "stage: nil" in out)
    check("renders the nested second reading", "L2beatRiskNote(value: \"10d\"" in out)
    check("renders the incident seed", out.count("Seed(project:") == 1)
    check("emits the note table", "private static let notes: [String] = [" in out)

    # The negative guard reads a COMMENT-STRIPPED copy. The generated header DOCUMENTS this
    # rule by naming what it must never emit ("nothing here ranks chains or folds five risks
    # into a verdict"), so a guard over raw text fires on the prose explaining it and reports
    # a correct file as broken — §419 earned this on its own guard's first run.
    body = "\n".join(l for l in out.splitlines() if not l.lstrip().startswith("//")).lower()
    check("emits no score field", "score" not in body)
    check("emits no ranking field", "rank" not in body)

    print(f"\n{'FAILED: ' + ', '.join(failures) if failures else 'all checks passed'}")
    return 1 if failures else 0


# --------------------------------------------------------------------------------------
# Chain marks
#
# L2BEAT serves a 128px PNG for every project it lists (`/icons/<slug>.png`), measured
# 2026-08-21 at 0.4–2.6KB each — about 120KB for all 105. They are snapshotted at ship time
# beside the assessments, so the app reaches NO image server at run time and no new host
# joins `NetworkReach`. Keyed by `id` in the asset catalog and fetched by `slug`, because
# those differ for ten projects (see `distill`).
# --------------------------------------------------------------------------------------


def write_icons(projects: list[dict]) -> None:
    assets = os.path.join(REPO_ROOT, "Casberi", "Casberi", "Assets.xcassets")
    written, missing = 0, []
    for project in projects:
        url = f"https://{SITE}/icons/{project['slug']}.png"
        time.sleep(PACE_SECONDS)
        try:
            raw = fetch(url, attempts=2)
        except SystemExit:
            missing.append(project["id"])
            continue
        if not raw.startswith(b"\x89PNG"):
            # A 200 that is not a PNG is their site answering with an error page; writing it
            # produces an asset that fails to decode at run time and draws nothing.
            missing.append(project["id"])
            continue
        out_dir = os.path.join(assets, f"brand-l2b-{project['id']}.imageset")
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "icon.png"), "wb") as fh:
            fh.write(raw)
        with open(os.path.join(out_dir, "Contents.json"), "w") as fh:
            json.dump({"images": [{"filename": "icon.png", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1}}, fh, indent=2)
        written += 1
    print(f"wrote {written} chain marks")
    if missing:
        # Named, never silent: a chain with no mark falls back to its monogram, and the
        # difference between "they publish none" and "the path changed" matters.
        print(f"  ! no icon published for: {', '.join(missing)}", file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--icons", action="store_true", help="also refresh the bundled chain marks")
    ap.add_argument("--check", action="store_true", help="fail if the checked-in file is stale")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    snapshot = gather()

    if args.icons:
        write_icons(snapshot["projects"])

    rendered = render(snapshot)

    if args.check:
        try:
            with open(OUT_PATH, encoding="utf-8") as fh:
                current = fh.read()
        except FileNotFoundError:
            print(f"MISSING {OUT_PATH}", file=sys.stderr)
            return 1
        # The generated date changes every run and is not drift; compare everything else.
        strip = lambda t: re.sub(r'static let generated = "[^"]*"', "", t)
        if strip(current) != strip(rendered):
            print("STALE — L2BEAT's assessments have changed since this was generated.",
                  file=sys.stderr)
            print("Run scripts/l2beat-snapshot.py to refresh.", file=sys.stderr)
            return 1
        print("l2beat directory is current")
        return 0

    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    projects = snapshot["projects"]
    l3 = sum(1 for p in projects if p["layer"] == "layer3")
    print(f"wrote {OUT_PATH}")
    print(f"  {len(projects)} projects ({len(projects) - l3} L2, {l3} L3)")
    print(f"  {len(snapshot['incidents'])} incidents bundled of {snapshot['milestoneCount']} milestones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
