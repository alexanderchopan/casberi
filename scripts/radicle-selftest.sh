#!/bin/zsh
# Casberi Radicle self-test — the SHIPPED wire logic behind the Radicle bridge
# (2026-08-18, prd §400):
#
#   Casberi/Casberi/Model/RadicleWire.swift
#     — date(epochSeconds:)  (seconds, never milliseconds)
#     — repo(_:rid:)         (the payloads nesting, and the named key)
#     — patch(_:) / issue(_:) (dates recovered from revisions[0] / discussion[0])
#     — Snapshot.*Changed    (the cheap sweep's whole decision)
#     — normalizeRID / normalizeSeed / permalink
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS, and why it is the ONLY proof this bridge has. Nothing on this
# host can open a patch, merge one, or close an issue, so the landing paths can
# never be exercised against a real change — the Stripe/PostHog situation, one
# degree worse, because those could at least be measured by anyone willing to
# mint a key and there is no key here to mint. Every failure below is a SILENT
# WRONG ANSWER that renders perfectly:
#
#   • a timestamp read as milliseconds, putting every patch in January 1970;
#   • the `payloads` nesting flattened, which yields nil for every field and an
#     EMPTY ROOM WITH NO ERROR — §400's first draft documented the flat shape,
#     and it was wrong (measured 2026-08-18);
#   • `payloads` read as "the first entry" rather than by name, which for the
#     4-in-11 repos carrying `xyz.radicle.crefs` reads the wrong payload;
#   • a patch dated by its NEWEST revision, so an old patch jumps to today
#     every time somebody pushes a fixup;
#   • an issue close stamped `.now` on first sight, dropping years-old work
#     into today's feed;
#   • a snapshot diff that only fires when a count GROWS, so a repo that
#     archives or reopens goes permanently blind.
#
# Pure, local, deterministic — no network, no simulator, no seed. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/RadicleWire.swift"
BRIDGE="Casberi/Casberi/Model/RadicleBridge.swift"
SCREEN="Casberi/Casberi/Screens/RadicleScreen.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
ROUTING="Casberi/Casberi/Model/BridgeRouting.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$WIRE" "$BRIDGE" "$SCREEN" "$REACH" "$REFRESH" "$ROUTING" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# A comment-stripped copy for the NEGATIVE guards. This file DOCUMENTS the
# things it must never do — it names `Authorization`, milliseconds and the flat
# shape in prose explaining why each is wrong — so a guard grepping raw source
# fires against the explanation. (The Obsidian/Cursor lesson, fifth time.)
STRIPPED=$(mktemp /tmp/radicle-stripped.XXXXXX.swift)
BRIDGE_STRIPPED=$(mktemp /tmp/radicle-bstripped.XXXXXX.swift)
trap 'rm -f "$STRIPPED" "$BRIDGE_STRIPPED"' EXIT
strip_comments() {
  python3 - "$1" "$2" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
out = []
for line in src.split("\n"):
    s = line.strip()
    if s.startswith("///") or s.startswith("//"):
        continue
    out.append(re.sub(r'\s//(?!/).*$', '', line))
open(sys.argv[2], "w").write("\n".join(out))
PY
}
strip_comments "$WIRE" "$STRIPPED"
strip_comments "$BRIDGE" "$BRIDGE_STRIPPED"

# --- conduct guard ----------------------------------------------------------
# THE PROMISE, MECHANICAL. The catalog says "read-only — the gateway has no
# credential and no way to write", and that is the strongest such claim in the
# app: not a minted scope (Trello), not a ticked box (PostHog, Stripe), not
# conduct (Privacy.com, Cursor) — NO CREDENTIAL AT ALL. It holds only while
# this file issues GETs and sends no authorization, so it is enforced, not
# remembered. `radicle-httpd` publishes no write verb, but a future editor
# reaching for `postJSON` would make the copy a lie in the same commit.
for verb in 'postJSON' 'deleteJSON' 'httpMethod' '"POST"' '"PUT"' '"PATCH"' '"DELETE"'; do
  if grep -qF -- "$verb" "$BRIDGE_STRIPPED"; then
    echo "✗ RadicleBridge names $verb — the catalog and setup copy promise this"
    echo "  bridge only ever reads. Change the copy in the same commit, or don't."
    exit 1
  fi
done
if grep -qE 'auth:|Authorization' "$BRIDGE_STRIPPED"; then
  echo "✗ RadicleBridge sends a credential — the whole seat is 'there is nothing"
  echo "  to mint and nothing a leak could spend'"; exit 1
fi

# --- drift guards -----------------------------------------------------------
# Facts the compiled file cannot prove on its own.

# §289: the seed host is TYPED BY THE PERSON, so NetworkReach cannot declare
# it. Every request must name its service to NetworkLedger, or the receipts
# screen reads a self-chosen seed as an undeclared reach — the exact defect
# that shipped five Alchemy hosts undisclosed.
if [[ $(grep -c 'service: service' "$BRIDGE_STRIPPED") -lt 4 ]]; then
  echo "✗ a Radicle request no longer names its service to NetworkLedger — a seed"
  echo "  the person typed would read as an undeclared reach (prd §289)"; exit 1
fi
grep -q 'Endpoint(service: "Radicle"' "$REACH" \
  || { echo "✗ Radicle is not in NetworkReach — the two default seeds must be declared"; exit 1; }
grep -q 'rosa.radicle.network' "$REACH" \
  || { echo "✗ the default seed is not declared in NetworkReach"; exit 1; }

# `activity` must stay UNREAD. §400's first draft built a room head on it,
# believing it returned the whole history; measured, it is a trailing ~365-day
# window (oldest entry 363/339/343/362/152/359 days ago across six repos), and
# feeding a span strip from it would re-commit the bug §398 had just fixed for
# the journals.
if grep -qE '/activity' "$BRIDGE_STRIPPED"; then
  echo "✗ the bridge reads /activity — it is a trailing ~365-day window, not the"
  echo "  whole history, and a span strip fed from it claims a span it cannot see"
  exit 1
fi

# The sweep must be wired, and the snapshot must advance only AFTER the rows
# land (StripeBridge's cursor rule — moving it first skips a window forever
# on a crash).
grep -q 'RadicleIngest.refresh' "$REFRESH" \
  || { echo "✗ nothing runs the Radicle sweep — the seat would only ever sync from"; \
       echo "  its own setup screen"; exit 1; }
python3 - "$BRIDGE_STRIPPED" <<'PY'
import sys
src = open(sys.argv[1]).read()
land = src.find("added += landIssues")
snap = src.find("store.remember(repo.snapshot")
if land == -1 or snap == -1 or snap < land:
    sys.stderr.write("✗ the snapshot advances before the rows land — a crash mid-pass\n"
                     "  would skip that window forever (StripeBridge's cursor rule)\n")
    sys.exit(1)
PY

# The registries a missing case answers nothing from.
grep -q 'case radicle' "$ROUTING" \
  || { echo "✗ Radicle has no BridgeRouting.Destination — Connect could never push"; exit 1; }
grep -q 'case .radicle:        RadicleScreen()' "$ROUTING" \
  || { echo "✗ the Radicle destination resolves to no screen"; exit 1; }
grep -q 'Offer(name: "Radicle"' "$CATALOG" \
  || { echo "✗ Radicle is not a catalog offer"; exit 1; }

# The seed field is the trust boundary and the copy must keep saying so.
grep -q 'seeds' "$SCREEN" \
  || { echo "✗ the setup screen no longer says a seed serves only what it seeds —"; \
       echo "  the deepest difference from GitHub, and the one that explains an"; \
       echo "  empty room"; exit 1; }

# --- the driver -------------------------------------------------------------
TMP=$(mktemp -d /tmp/radicle-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"; rm -f "$STRIPPED" "$BRIDGE_STRIPPED"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let cal = Calendar(identifier: .gregorian)
func year(_ d: Date?) -> Int? { d.map { cal.component(.year, from: $0) } }

// ── time ───────────────────────────────────────────────────────────────────
print("date(epochSeconds:) — seconds, never milliseconds")
do {
    // The exact value measured on a live patch revision, 2026-08-18.
    let measured = 1_783_931_502
    check("a real revision timestamp reads as 2026", year(RadicleWire.date(epochSeconds: measured)) == 2026)
    // The whole bug in one assertion: the same number read as milliseconds.
    let asMillis = Date(timeIntervalSince1970: Double(measured) / 1000)
    check("…and would be 1970 if read as milliseconds", cal.component(.year, from: asMillis) == 1970)
    check("a millisecond-scale value is REFUSED, not silently accepted",
          RadicleWire.date(epochSeconds: measured * 1000) == nil)
}
do {
    check("a String timestamp is read", year(RadicleWire.date(epochSeconds: "1783931502")) == 2026)
    check("a Double timestamp is read", year(RadicleWire.date(epochSeconds: 1_783_931_502.0)) == 2026)
    check("nil is nil", RadicleWire.date(epochSeconds: nil) == nil)
    check("a non-number is nil", RadicleWire.date(epochSeconds: "soon") == nil)
    check("zero is refused (the epoch is not a date anybody meant)",
          RadicleWire.date(epochSeconds: 0) == nil)
    check("a pre-2015 value is refused", RadicleWire.date(epochSeconds: 1_000_000_000) == nil)
    check("a far-future value is refused",
          RadicleWire.date(epochSeconds: Int(Date().timeIntervalSince1970) + 400_000) == nil)
    // The boundary has slack for a seed whose clock runs ahead — a real seed
    // being a few minutes fast must not silently drop its newest patch.
    check("a seed running slightly fast is still accepted",
          RadicleWire.date(epochSeconds: Int(Date().timeIntervalSince1970) + 3_600) != nil)
}

// ── the payloads nesting ───────────────────────────────────────────────────
print("repo(_:) — the nesting §400's first draft got wrong")
// Shaped exactly as measured from rosa.radicle.network, 2026-08-18.
func repoJSON(name: String = "heartwood",
              extraPayload: Bool = false,
              open: Int = 2, merged: Int = 17,
              issuesOpen: Int = 1, issuesClosed: Int = 2) -> [String: Any] {
    var payloads: [String: Any] = [
        "xyz.radicle.project": [
            "data": ["defaultBranch": "main", "description": "Radicle heartwood", "name": name],
            "meta": [
                "head": "8c5df5ecbd3f2507d323608b52e1fbf7b177d864",
                "issues": ["open": issuesOpen, "closed": issuesClosed],
                "patches": ["open": open, "draft": 0, "archived": 0, "merged": merged],
            ],
        ],
    ]
    if extraPayload { payloads["xyz.radicle.crefs"] = ["data": ["name": "WRONG"]] }
    return [
        "payloads": payloads,
        "rid": "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5",
        "seeding": 279,
        "threshold": 1,
        "visibility": ["type": "public"],
        "delegates": [
            ["id": "did:key:z6MkireRatUThvd3qzfKht1S44wpm4FEWSSa4PRMTSQZ3voM", "alias": "fintohaps"],
            ["id": "did:key:z6MkkPvBfjP4bQmco5Dm7UGsX2ruDBieEHi8n9DVJWX5sTEz"],
        ],
    ]
}
do {
    let repo = RadicleWire.repo(repoJSON())
    check("the repo parses at all", repo != nil)
    check("the name comes out of payloads.data", repo?.name == "heartwood")
    check("the description too", repo?.description == "Radicle heartwood")
    check("head comes out of payloads.meta", repo?.snapshot.head?.hasPrefix("8c5df5") == true)
    check("the patch counts are read", repo?.snapshot.patchesMerged == 17)
    check("the issue counts are read", repo?.snapshot.issuesClosed == 2)
    check("the rid survives", repo?.rid == "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5")
}
do {
    // THE 4-IN-11 CASE. A repo carrying a second payload must still read the
    // project one — taking "the first payload" is a dictionary-order bet.
    let repo = RadicleWire.repo(repoJSON(extraPayload: true))
    check("a second payload does not displace the project one", repo?.name == "heartwood")
}
do {
    // The FLAT shape §400's first draft documented. It must not parse — if it
    // did, a bridge could read either and nobody would notice which.
    let flat: [String: Any] = [
        "rid": "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5", "name": "heartwood",
        "meta": ["head": "abc", "patches": ["open": 2], "issues": ["open": 1]],
    ]
    check("the flat shape yields nothing (it is not what a seed serves)",
          RadicleWire.repo(flat) == nil)
    // DETERMINISTIC by construction, and it has to be. The `extraPayload`
    // case above cannot pin "named, never first": Swift dictionary order is
    // nondeterministic, so a bridge reading `payloads.values.first` picks the
    // right one about half the time and that fixture passes by luck — which is
    // exactly how the mutation for it SURVIVED this harness's first run. Here
    // the only payload present is the wrong one AND it carries a usable name,
    // so a by-name read must yield nil and a by-order read must yield "WRONG".
    check("a repo whose only payload is not the project one yields nothing",
          RadicleWire.repo(["payloads": ["xyz.radicle.crefs": ["data": ["name": "WRONG"]]],
                            "rid": "rad:zAAAA"]) == nil)
    check("a nameless repo yields nothing",
          RadicleWire.repo(repoJSON(name: "")) == nil)
}
do {
    let repo = RadicleWire.repo(repoJSON())
    check("a delegate's alias is read", repo?.delegates.first?.display == "fintohaps")
    // A DID with no alias must NOT be given one — an invented handle on a row
    // saying who did something is fake status where it would be believed.
    check("a delegate with no alias keeps its DID tail, never an invented name",
          repo?.delegates.last?.alias == nil)
    check("…and still displays as something distinguishing",
          repo?.delegates.last?.display.isEmpty == false)
    // `party()` maps an EMPTY alias to nil before Party is built, so the
    // display guard is only reachable by constructing one directly — which is
    // done here on purpose: "never invent a name" has to hold for every
    // caller, not only the one that happens to sanitise first. Without this,
    // replacing the guard with a stand-in name goes undetected.
    let anonymousDID = "did:key:z6MkkPvBfjP4bQmco5Dm7UGsX2ruDBieEHi8n9DVJWX5sTEz"
    check("a Party built with an empty alias shows its DID tail, never a stand-in",
          RadicleWire.Party(did: anonymousDID, alias: "").display
            == String(anonymousDID.suffix(8)))
}

// ── the sweep's decision ───────────────────────────────────────────────────
print("Snapshot — the cheap sweep's whole decision")
do {
    let old = RadicleWire.Snapshot(head: "a", patchesOpen: 2, patchesDraft: 0,
                                   patchesArchived: 0, patchesMerged: 17,
                                   issuesOpen: 1, issuesClosed: 2)
    check("an unchanged repo spends no request on patches", !old.patchesChanged(from: old))
    check("…nor on issues", !old.issuesChanged(from: old))

    var grew = old; grew.patchesOpen = 3
    check("a new patch is worth a walk", grew.patchesChanged(from: old))

    // THE DIRECTION CASE. A patch can be archived or reopened, which moves a
    // count DOWN; a bridge that only looked when a number grew would go blind
    // to a repo that churns.
    var shrank = old; shrank.patchesOpen = 1
    check("a patch ARCHIVED (count falls) is also worth a walk",
          shrank.patchesChanged(from: old))
    var moved = old; moved.patchesOpen = 1; moved.patchesMerged = 18
    check("open→merged, which nets zero on one field, is caught by the other",
          moved.patchesChanged(from: old))

    var closed = old; closed.issuesOpen = 0; closed.issuesClosed = 3
    check("an issue closing is worth a walk", closed.issuesChanged(from: old))
    check("…and is reported as a close we WATCHED happen", closed.sawIssueClose(from: old))
    var opened = old; opened.issuesOpen = 2
    check("an issue merely OPENING is not a close", !opened.sawIssueClose(from: old))
    var reopened = old; reopened.issuesClosed = 1
    check("a REOPEN is not a close either", !reopened.sawIssueClose(from: old))
    check("patch churn does not trigger an issue walk", !grew.issuesChanged(from: old))
}

// ── patches ────────────────────────────────────────────────────────────────
print("patch(_:) — a date recovered from the record, not estimated")
// Shaped exactly as measured, 2026-08-18.
func patchJSON(status: String = "merged", revisions: [Int] = [1_786_704_641],
               merges: [Int] = [1_786_712_883]) -> [String: Any] {
    [
        "id": "1665105af9a59b5dfd4c0a20b050a7cc6fc7acb1",
        "title": "dependency: Upgrade spin to v0.9.9",
        "author": ["id": "did:key:z6MkfbK946evvPVhWkibuyDGfGGkQcpEGaWdTUCASuuwUP2n",
                   "alias": "dsommers"],
        "state": ["status": status, "revision": "d304aa99", "commit": "2a9b5e72"],
        "labels": [], "assignees": [],
        "merges": merges.map { ["author": ["id": "did:key:z6MkkPvB", "alias": "lorenz"],
                                "commit": "2a9b5e72", "timestamp": $0] },
        "revisions": revisions.map { ["id": "d304aa99", "timestamp": $0] },
    ]
}
do {
    let p = RadicleWire.patch(patchJSON())
    check("a patch parses", p != nil)
    check("there is NO top-level timestamp to read", patchJSON()["timestamp"] == nil)
    check("opened comes from revisions[0]", year(p?.opened) == 2026)
    check("merged comes from merges[]", year(p?.merged) == 2026)
    check("merged is AFTER opened", (p?.merged ?? .distantPast) > (p?.opened ?? .distantFuture))
    check("the author's alias is read", p?.author.display == "dsommers")
    check("the MERGER is named, not the author", p?.mergedBy?.display == "lorenz")
    check("merged is recognised", p?.isMerged == true)
}
do {
    // THE FIXUP CASE. A patch with several revisions must be dated by its
    // FIRST, or every pushed fixup drags an old patch to today.
    let p = RadicleWire.patch(patchJSON(revisions: [1_600_000_000, 1_786_704_641]))
    check("a re-revised patch keeps its ORIGINAL proposal date",
          year(p?.opened) == 2020)
}
do {
    // Several delegates merged; the EARLIEST is when it landed.
    let p = RadicleWire.patch(patchJSON(merges: [1_786_800_000, 1_786_712_883]))
    check("the earliest merge is when it landed", year(p?.merged) == 2026)
    check("…specifically the earlier of the two",
          p?.merged == Date(timeIntervalSince1970: 1_786_712_883))
}
do {
    let open = RadicleWire.patch(patchJSON(status: "open", merges: []))
    check("an open patch has no merge date", open?.merged == nil)
    check("…and is not merged", open?.isMerged == false)
    check("a patch with no revisions has no open date",
          RadicleWire.patch(patchJSON(revisions: []))?.opened == nil)
    check("a titleless patch yields nothing",
          RadicleWire.patch(["id": "a", "author": ["id": "did:key:z"], "title": ""]) == nil)
    check("an authorless patch yields nothing",
          RadicleWire.patch(["id": "a", "title": "t"]) == nil)
}

// ── issues ─────────────────────────────────────────────────────────────────
print("issue(_:) — the root comment IS the body")
func issueJSON(status: String = "closed", reason: String? = "solved",
               comments: [Int] = [1_780_560_068, 1_781_862_543]) -> [String: Any] {
    var state: [String: Any] = ["status": status]
    if let reason { state["reason"] = reason }
    return [
        "id": "9f8c1d", "title": "NO_COLOR disables all styling",
        "author": ["id": "did:key:z6MkwGoyYxt6A2VE", "alias": "ade"],
        "state": state, "assignees": [], "labels": [],
        "discussion": comments.map { ["id": "c", "body": "…", "timestamp": $0] },
    ]
}
do {
    let i = RadicleWire.issue(issueJSON())
    check("an issue parses", i != nil)
    check("there is NO top-level timestamp", issueJSON()["timestamp"] == nil)
    check("opened comes from discussion[0]", year(i?.opened) == 2026)
    check("…which is the ROOT comment, not the newest",
          i?.opened == Date(timeIntervalSince1970: 1_780_560_068))
    check("the author's alias is read", i?.author.display == "ade")
    check("closed is recognised", i?.isClosed == true)
}
do {
    // THE MEASURED ABSENCE, and the sharpest assertion in this file. A closed
    // issue carries `{status: closed, reason: solved}` and NO close timestamp
    // anywhere — so `closedDate` must stay nil. If it ever starts returning a
    // date it will be a guess (the newest comment is not when it closed), and
    // a guessed date on a years-old issue lands it in today's feed.
    let i = RadicleWire.issue(issueJSON())
    check("a close carries NO recoverable date — and we do not invent one",
          i?.closedDate == nil)
    check("…not even the newest comment's",
          i?.closedDate != Date(timeIntervalSince1970: 1_781_862_543))
}
do {
    check("an issue with no discussion has no open date",
          RadicleWire.issue(issueJSON(comments: []))?.opened == nil)
    check("an open issue is not closed", RadicleWire.issue(issueJSON(status: "open"))?.isClosed == false)
    check("a missing state defaults to open",
          RadicleWire.issue(["id": "a", "title": "t",
                             "author": ["id": "did:key:z"]])?.status == "open")
}

// ── identity ───────────────────────────────────────────────────────────────
print("normalizeRID — what a person actually has")
do {
    let real = "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5"
    check("a bare id passes", RadicleWire.normalizeRID(real) == real)
    check("whitespace is trimmed", RadicleWire.normalizeRID("  \(real)\n") == real)
    check("a percent-encoded id is decoded",
          RadicleWire.normalizeRID("rad%3Az3gqcJUoA1n9HaHKufZs5FCSGazv5") == real)
    check("an explorer URL yields the id",
          RadicleWire.normalizeRID("https://radicle.network/nodes/rosa.radicle.network/\(real)") == real)
    check("…including a deep link to a patch",
          RadicleWire.normalizeRID(
            "https://radicle.network/nodes/rosa.radicle.network/rad%3Az3gqcJUoA1n9HaHKufZs5FCSGazv5/patches/1665105a") == real)
}
do {
    check("a plain word is refused", RadicleWire.normalizeRID("heartwood") == nil)
    check("an empty string is refused", RadicleWire.normalizeRID("") == nil)
    check("a bare `rad:` is refused", RadicleWire.normalizeRID("rad:") == nil)
    check("a too-short id is refused", RadicleWire.normalizeRID("rad:z3gq") == nil)
    check("a URL is refused", RadicleWire.normalizeRID("https://example.com") == nil)
    // Path separators in an id would escape the URL this gets interpolated into.
    check("an id carrying a slash is refused",
          RadicleWire.normalizeRID("rad:z3gqcJUoA1n9HaHKufZs5FCSGa/../etc") == nil)
    check("an id carrying punctuation is refused",
          RadicleWire.normalizeRID("rad:z3gqcJUoA1n9HaHKufZs5FCSG?a=1") == nil)
}
print("normalizeSeed — this string is interpolated into every request")
do {
    check("a bare host passes", RadicleWire.normalizeSeed("rosa.radicle.network") == "rosa.radicle.network")
    check("a scheme is stripped", RadicleWire.normalizeSeed("https://rosa.radicle.network") == "rosa.radicle.network")
    check("a path is dropped", RadicleWire.normalizeSeed("https://rosa.radicle.network/api/v1") == "rosa.radicle.network")
    check("case is normalised", RadicleWire.normalizeSeed("ROSA.Radicle.Network") == "rosa.radicle.network")
    check("a hostless string is refused", RadicleWire.normalizeSeed("localhost") == nil)
    check("an empty string is refused", RadicleWire.normalizeSeed("") == nil)
    check("a host with a space is refused", RadicleWire.normalizeSeed("bad host.com") == nil)
    check("a leading dot is refused", RadicleWire.normalizeSeed(".radicle.network") == nil)
}

// ── links ──────────────────────────────────────────────────────────────────
print("permalink — the encoding that skips the 307")
do {
    let rid = "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5"
    let url = RadicleWire.permalink(seed: "rosa.radicle.network", rid: rid)
    check("the RID is percent-encoded", url.contains("rad%3Az3gqcJ"))
    check("…so no bare colon survives in the path", !url.contains("/rad:"))
    check("the seed is named", url.contains("/nodes/rosa.radicle.network/"))
    let patch = RadicleWire.permalink(seed: "rosa.radicle.network", rid: rid, path: "patches/abc")
    check("a patch path is appended", patch.hasSuffix("/patches/abc"))
    check("no path leaves the repo URL", url.hasSuffix("Gazv5"))
}
print("title — the repo leads")
do {
    let t = RadicleWire.title(repo: "heartwood", verb: "merged", subject: "Fix seed discovery")
    check("the repo is first", t.hasPrefix("heartwood · "))
    check("the verb is second", t.contains("· merged ·"))
    // §303's clamp ruling: `titleLine` cuts at 80, so a trailing verb is what
    // the clamp eats and a merge reads as an ordinary patch.
    check("the verb survives an 80-character clamp",
          String(RadicleWire.title(repo: "heartwood", verb: "merged",
                                   subject: String(repeating: "x", count: 200)).prefix(80))
            .contains("merged"))
}

print("")
if failures > 0 { print("✗ \(failures) assertion(s) failed"); exit(1) }
print("✓ all assertions passed")
SWIFT

if ! swiftc -O -o "$TMP/run" "$WIRE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped RadicleWire.swift:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each of these is a real defect this
# bridge could ship; the harness must go red for every one.
echo
echo "mutations — each must be caught"

mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/RadicleWire.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/RadicleWire.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/RadicleWire.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/RadicleWire.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE HEADLINE BUG: timestamps read as milliseconds. Every row lands in 1970.
mutate "timestamps read as milliseconds" \
  'return Date(timeIntervalSince1970: seconds)' \
  'return Date(timeIntervalSince1970: seconds / 1000)'

# 2. The plausibility window removed — a millisecond value is accepted as a
#    date in the year 58,500 rather than refused.
mutate "the plausibility window removed" \
  'guard seconds >= 1_420_070_400,' \
  'guard seconds >= 0,'

# 3. THE NESTING FLATTENED — §400's first draft's shape. Empty room, no error.
mutate "the payloads nesting flattened" \
  'let data = project["data"] as? [String: Any] ?? [:]' \
  'let data = root'

# 4. The payload taken by ORDER rather than by name — wrong for the 4-in-11
#    repos carrying a second payload.
mutate "the payload taken as the first entry" \
  'let project = payloads[projectPayload] as? [String: Any]' \
  'let project = payloads.values.first as? [String: Any]'

# 5. meta read from the wrong level — head and all six counts go nil.
mutate "meta read off the root" \
  'let meta = project["meta"] as? [String: Any] ?? [:]' \
  'let meta = root["meta"] as? [String: Any] ?? [:]'

# 6. A patch dated by its NEWEST revision — every fixup drags it to today.
mutate "a patch dated by its newest revision" \
  'let opened = date(epochSeconds: revisions.first?["timestamp"])' \
  'let opened = date(epochSeconds: revisions.last?["timestamp"])'

# 7. The merge taken as the LATEST rather than the earliest.
mutate "the latest merge taken as when it landed" \
  '.sorted { $0.0 < $1.0 }' \
  '.sorted { $0.0 > $1.0 }'

# 8. An issue dated by its newest comment — a long thread moves the open date.
mutate "an issue dated by its newest comment" \
  'opened: date(epochSeconds: discussion.first?["timestamp"])' \
  'opened: date(epochSeconds: discussion.last?["timestamp"])'

# 9. THE INVENTED CLOSE DATE. There is no close timestamp on the wire; a
#    bridge that guessed one would drop years-old issues into today's feed.
mutate "a close date invented from the newest comment" \
  'var closedDate: Date? { nil }' \
  'var closedDate: Date? { opened }'

# 10. The snapshot diff made growth-only — a repo that archives goes blind.
mutate "the patch diff made growth-only" \
  'patchesOpen != old.patchesOpen' \
  'patchesOpen > old.patchesOpen'

# 11. A reopen counted as a close — a "closed" row for an issue that reopened.
mutate "a reopen counted as a close" \
  'issuesClosed > old.issuesClosed' \
  'issuesClosed != old.issuesClosed'

# 12. The RID character guard dropped — a slash escapes the request URL.
mutate "the RID character guard dropped" \
  'body.allSatisfy({ $0.isLetter || $0.isNumber })' \
  'true'

# 13. The permalink's encoding dropped — every link takes a 307, and breaks
#     the day the redirect stops being served.
mutate "the permalink encoding dropped" \
  'let encoded = rid.replacingOccurrences(of: ":", with: "%3A")' \
  'let encoded = rid'

# 14. An alias invented for a DID that has none.
mutate "an alias invented for an anonymous DID" \
  'if let alias, !alias.isEmpty { return alias }' \
  'if let alias { return alias.isEmpty ? "someone" : alias }'

# 15. The seed guard relaxed — a host with a space or a path reaches the URL.
mutate "the seed host guard relaxed" \
  's.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" })' \
  'true'

echo
echo "✓ radicle self-test: assertions and mutations all passed"
