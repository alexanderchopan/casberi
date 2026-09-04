#!/bin/zsh
# Casberi Ethrex Privacy self-test — the two Foundation-only files behind the
# fourth devnet seat (2026-09-04, prd §593):
#
#   Casberi/Casberi/Model/PrivacyDevnetSection.swift  — the seven scopes
#   Casberi/Casberi/Model/PrivacyDevnetRoots.swift    — the EIP-8272 window
#
# Both are Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED here.
#
# WHY A HARNESS. Nothing else in this repo can reach these rules. The chain is
# unreachable from a `swiftc` harness and from CI, the simulator has no seat to
# open, and every failure below renders as a PERFECTLY ORDINARY ROOM: a scope
# that never appears, a remembered scope resolving to one nobody picked, a root
# reported live when it aged out hours ago, or a source list that reshuffles
# between opens. A build is green for all of them.
#
# The sharpest ones are the two that would be invisible even to somebody using
# the seat daily: the window boundary (off by one reads as a root expiring a
# slot early, and only a person watching the boundary would ever see it — which
# is the only person this card is for) and the slot-vs-block confusion, which is
# silently correct on a chain that has never missed a slot and wrong by
# thousands on one that has.
set -uo pipefail
cd "${0:A:h}/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1 }

SECTION="Casberi/Casberi/Model/PrivacyDevnetSection.swift"
ROOTS="Casberi/Casberi/Model/PrivacyDevnetRoots.swift"
ROOM="Casberi/Casberi/Model/PrivacyDevnetRoom.swift"
FIG="Casberi/Casberi/Model/PrivacyDevnetFigure.swift"
VERIFY="scripts/verify.sh"
for f in "$SECTION" "$ROOTS" "$ROOM" "$FIG"; do [[ -f "$f" ]] || fail "$f not found"; done

# `swiftc` needs a main file; the sources are compiled WHOLE and unmodified.
cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ cond: Bool, _ what: String) {
    if !cond { print("  ✗ \(what)"); failures += 1 }
}
func d(_ hex: String) -> Data {
    var out = Data(); var s = Substring(hex)
    while s.count >= 2 {
        out.append(UInt8(s.prefix(2), radix: 16)!); s = s.dropFirst(2)
    }
    return out
}

// ─────────────────────────── PrivacyDevnetSection ───────────────────────────

check(PrivacyDevnetSection.order.count == PrivacyDevnetSection.allCases.count,
      "order lists every case — a case missing from order can never be shown")
check(PrivacyDevnetSection.order.first == .home, "home leads")
check(PrivacyDevnetSection.order.last == .sponsors, "sponsors is last, the rarest scope")

// THE ABSENT SCOPE. `coins` must not exist: the UTXO vault has no code on 8141,
// so the chip could never light. Asserted on the raw values because a `case
// coins` added later would compile fine and draw a permanently empty scope.
check(!PrivacyDevnetSection.allCases.contains { $0.rawValue == "coins" },
      "no `coins` scope — the UTXO vault has no code on this chain")
check(PrivacyDevnetSection.allCases.contains { $0.rawValue == "nullifiers" },
      "`nullifiers` exists, and is not spelled `nonces` as on Hegota")
check(!PrivacyDevnetSection.allCases.contains { $0.rawValue == "nonces" },
      "not `nonces` — here the keyed nonce is a nullifier (§593)")
check(PrivacyDevnetSection.allCases.contains { $0.rawValue == "roots" },
      "`roots` exists — the only chain in the app with EIP-8272 deployed")

// THE TAIL RULE: no unconditional scope may sit after a conditional one, so the
// strip's head never reflows as an address gains content.
let firstConditional = PrivacyDevnetSection.order.firstIndex { $0.isConditional }!
let lastUnconditional = PrivacyDevnetSection.order.lastIndex { !$0.isConditional }!
check(lastUnconditional < firstConditional,
      "every unconditional scope precedes every conditional one")
check(PrivacyDevnetSection.order[3] == .frames, "the conditional tail opens on frames")

// THE PAIRING: nullifiers and roots are two halves of one mechanism and must be
// adjacent, in that order — apart they read as two unrelated pieces of jargon.
let ni = PrivacyDevnetSection.order.firstIndex(of: .nullifiers)!
let ri = PrivacyDevnetSection.order.firstIndex(of: .roots)!
check(ri == ni + 1, "roots sits immediately after nullifiers")

for s in PrivacyDevnetSection.allCases {
    check(!s.label.isEmpty, "\(s.rawValue) has a label")
    check(!s.summary.isEmpty, "\(s.rawValue) has an accessibility summary")
    check(s.summary != s.label, "\(s.rawValue)'s summary says more than its label")
}
check(PrivacyDevnetSection.home.isAlwaysPresent && PrivacyDevnetSection.activity.isAlwaysPresent
        && PrivacyDevnetSection.accounts.isAlwaysPresent,
      "the three unconditional scopes are always present")
check(!PrivacyDevnetSection.frames.isAlwaysPresent, "frames is conditional")

// present(): the three constants survive an address with nothing else at all.
let bare = PrivacyDevnetSection.present(frames: false, nullifiers: false, roots: false, sponsors: false)
check(bare == [.home, .activity, .accounts], "a bare address keeps exactly the three constants")
let full = PrivacyDevnetSection.present(frames: true, nullifiers: true, roots: true, sponsors: true)
check(full == PrivacyDevnetSection.order, "an address with everything shows every scope, in order")
let some = PrivacyDevnetSection.present(frames: true, nullifiers: false, roots: true, sponsors: false)
check(some == [.home, .activity, .accounts, .frames, .roots],
      "present() drops exactly the absent scopes and keeps order")

// resolve(): a remembered scope whose content has gone falls back to home,
// never to "the first present scope".
check(PrivacyDevnetSection.resolve(.roots, present: full) == .roots, "a present scope resolves to itself")
check(PrivacyDevnetSection.resolve(.roots, present: bare) == .home, "an absent scope falls back to home")
check(PrivacyDevnetSection.resolve(nil, present: full) == .home, "no memory opens on home")

// shows(): one chip is a label, not a control.
check(!PrivacyDevnetSection.shows(present: [.home]), "one scope draws no strip")
check(PrivacyDevnetSection.shows(present: bare), "three scopes draw a strip")

// No dot can ever light — including on roots, which has a real clock.
check(PrivacyDevnetSection.attention().isEmpty, "no scope ever wears a dot")

// ──────────────────────────── PrivacyDevnetRoots ────────────────────────────

check(PrivacyDevnetRoots.windowSlots == 8192, "the ring is 8192 slots — the predeploy's own 0x1fff mask")

let src = d("a0dfea37afb843c1fc18cfa21205766b96e6f7c7d7993ab5d5e041e0b1964f54")
let src2 = d("b08f15750c491f4cfd65215c11a33b3962903a8896fc586bbd7c697851c26e20")
let root = d("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")
let root2 = d("1ea261e94b9f2b02699e293bd4ad36b4c39cf23975b84c4cc39794bb577df422")
// The real reference off block 13347.
let real = PrivacyDevnetRoots.Reference(sourceID: src, slot: 0x3431, root: root)
check(real.sourceID.count == 32, "sourceId is 32 bytes — the width Hegota's UInt64 cannot hold")

// THE BOUNDARY. Three slots decide it and each renders identically from outside.
let base: UInt64 = 100_000
let r = PrivacyDevnetRoots.Reference(sourceID: src, slot: base, root: root)
check(PrivacyDevnetRoots.standing(of: r, headSlot: base) == .live(remaining: 8192),
      "a root registered this slot has the whole window left")
check(PrivacyDevnetRoots.standing(of: r, headSlot: base + 8191) == .live(remaining: 1),
      "the last acceptable slot still reads live, with one left")
check(PrivacyDevnetRoots.standing(of: r, headSlot: base + 8192) == .aged(by: 1),
      "one slot past the window is aged by exactly one")
check(PrivacyDevnetRoots.standing(of: r, headSlot: base + 8193) == .aged(by: 2),
      "aged-by counts from the first aged slot, not from registration")

// A head BEHIND the reference is not freshness, it is a stale head.
check(PrivacyDevnetRoots.standing(of: r, headSlot: base - 1) == .ahead,
      "a reference ahead of the head reports .ahead, never live")
check(PrivacyDevnetRoots.remaining(r, headSlot: base - 1) == nil, "an ahead reference has no remaining")
check(PrivacyDevnetRoots.remaining(r, headSlot: base + 8192) == nil, "an aged reference has no remaining")
check(PrivacyDevnetRoots.remaining(r, headSlot: base + 100) == 8092, "remaining counts down from the window")

// fraction(): nil rather than 0 for an aged root — "empty" and "nothing to say"
// are different claims and the second must not be drawn as the first.
check(PrivacyDevnetRoots.fraction(r, headSlot: base) == 1.0, "a fresh root reads full")
check(PrivacyDevnetRoots.fraction(r, headSlot: base + 8192) == nil, "an aged root has NO fraction, not zero")
check(PrivacyDevnetRoots.fraction(r, headSlot: base - 1) == nil, "an ahead root has no fraction")

check(PrivacyDevnetRoots.duration(slots: 8192) == 98_304, "the whole window is 98,304s ≈ 27.3h at 12s slots")

// bySource(): grouping, and a TOTAL order so the card cannot reshuffle.
let refs = [
    PrivacyDevnetRoots.Reference(sourceID: src, slot: 0x3431, root: root),
    PrivacyDevnetRoots.Reference(sourceID: src, slot: 0x3436, root: root2),
    PrivacyDevnetRoots.Reference(sourceID: src2, slot: 0x0af1, root: root),
]
let grouped = PrivacyDevnetRoots.bySource(refs)
check(grouped.count == 2, "two sources group into two rows")
check(grouped[0].source == src, "the newer source leads")
check(grouped[0].newest.slot == 0x3436, "a group reports its NEWEST reference")
check(grouped[0].count == 2, "a group counts every reference it holds")
check(grouped[1].source == src2, "the older source follows")
// Determinism over identical input, run twice — the failure this catches is a
// card that reorders between opens, which reads as broken rather than as wrong.
check(PrivacyDevnetRoots.bySource(refs).map(\.source) == PrivacyDevnetRoots.bySource(refs).map(\.source),
      "bySource is deterministic")
// A TIE on slot must still order totally.
let tieA = PrivacyDevnetRoots.Reference(sourceID: src, slot: 50, root: root)
let tieB = PrivacyDevnetRoots.Reference(sourceID: src2, slot: 50, root: root2)
let tied = PrivacyDevnetRoots.bySource([tieA, tieB])
check(tied.count == 2 && tied.map(\.source) == PrivacyDevnetRoots.bySource([tieB, tieA]).map(\.source),
      "a slot tie orders the same regardless of input order")

// ──────────────────────────── PrivacyDevnetRoom ───────────────────────

// THE BLACK-SCREEN RULE. This seat lands no `Thing` ever, so the head is the
// room's whole content and every branch must return one. Asserted over the
// cross product of the states that reach it, because a nil here is not an
// empty room — it is a black screen, which is how the Hegota room reached a
// device four times.
for hasRead in [false, true] {
  for reset in [nil, false, true] as [Bool?] {
    for accs in [[], [PrivacyDevnetRoom.Account()],
                 [PrivacyDevnetRoom.Account(nullifierCount: 2, frameCount: 2,
                                            roots: [r])]] {
      let h = PrivacyDevnetRoom.head(accounts: accs, watching: 0, hasRead: hasRead,
                                     headSlot: base + 10, wasReset: reset)
      // `.unwatched` legitimately claims zero — it is the state where nothing
      // IS watched. Every other lede must claim at least one, or a room says
      // it watches nothing while describing what it watched.
      if case .unwatched = h.lede {
          check(h.watching == 0, "the unwatched head claims zero, not one")
      } else {
          check(h.watching >= 1, "every other head claims at least one watched address")
      }
      check(!PrivacyDevnetRoom.sentence(h).isEmpty, "every head has a sentence")
    }
  }
}

// RANKING. A relaunch outranks everything, because every other reading would
// describe a chain that no longer exists.
let rich = [PrivacyDevnetRoom.Account(nullifierCount: 2, frameCount: 2, roots: [r])]
check(PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                             headSlot: base + 10, wasReset: true).lede == .relaunched,
      "a relaunch outranks a live root")
// nil is NOT true: not knowing is not the same as knowing it was wiped.
if case .relaunched = PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                                             headSlot: base + 10, wasReset: nil).lede {
    check(false, "an unobserved genesis must not claim a relaunch")
}
// A read that has not happened reads as reading — unless accounts are already
// here, which are themselves evidence of a read.
if case .reading = PrivacyDevnetRoom.head(accounts: [], watching: 1, hasRead: false,
                                          headSlot: base, wasReset: false).lede {} else {
    check(false, "no read and no accounts reads as reading")
}
// NOTHING WATCHED reads as `.unwatched`, never nil and never "reading" — see
// the black-screen note above.
if case .unwatched = PrivacyDevnetRoom.head(accounts: [], watching: 0, hasRead: false,
                                            headSlot: base, wasReset: false).lede {} else {
    check(false, "nothing watched reads as unwatched")
}
check(!PrivacyDevnetRoom.sentence(
        PrivacyDevnetRoom.head(accounts: [], watching: 0, hasRead: false,
                               headSlot: base, wasReset: false)).isEmpty,
      "the unwatched head still has a sentence")
if case .reading = PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: false,
                                          headSlot: base + 10, wasReset: false).lede {
    check(false, "accounts are themselves evidence of a read")
}
// A LIVE root outranks spends; an aged one does not outrank them.
if case .rootLive = PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                                           headSlot: base + 10, wasReset: false).lede {} else {
    check(false, "a live root leads")
}
if case .rootsAged = PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                                            headSlot: base + 99_999, wasReset: false).lede {} else {
    check(false, "every root out of the window reads as aged, not as quiet")
}
// A meter is drawn only over a LIVE root.
check(PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                             headSlot: base + 99_999, wasReset: false).windowFraction == nil,
      "an aged root draws no window meter")
check(PrivacyDevnetRoom.head(accounts: rich, watching: 1, hasRead: true,
                             headSlot: base + 10, wasReset: false).windowFraction != nil,
      "a live root draws a window meter")
// WHICH root leads, when there are several. The one-root fixture above cannot
// tell max from min — a mutation swapping them SURVIVED on it — so this pins a
// pair whose windows differ, and asserts the head reports the FRESHER one: the
// reference somebody still has time to care about.
let older = PrivacyDevnetRoots.Reference(sourceID: src, slot: base, root: root)
let fresher = PrivacyDevnetRoots.Reference(sourceID: src2, slot: base + 4000, root: root2)
let twoRoots = [PrivacyDevnetRoom.Account(nullifierCount: 1, roots: [older, fresher])]
if case .rootLive(let remaining, let sources) =
    PrivacyDevnetRoom.head(accounts: twoRoots, watching: 1, hasRead: true,
                           headSlot: base + 4100, wasReset: false).lede {
    // fresher: registered at base+4000, head at base+4100 → 8192 - 100 = 8092.
    // older:   registered at base,      head at base+4100 → 8192 - 4100 = 4092.
    check(remaining == 8092, "the head reports the root with the MOST window left")
    check(sources == 2, "and counts every distinct source, not just the leader's")
} else { check(false, "two live roots read as rootLive") }

// Spends without a root are their own reading, not quiet.
let spent = [PrivacyDevnetRoom.Account(nullifierCount: 3, frameCount: 1)]
if case .spends(let n) = PrivacyDevnetRoom.head(accounts: spent, watching: 1, hasRead: true,
                                                headSlot: base, wasReset: false).lede {
    check(n == 3, "spends counts every nullifier across accounts")
} else { check(false, "nullifiers with no root read as spends") }
if case .quiet = PrivacyDevnetRoom.head(accounts: [PrivacyDevnetRoom.Account()], watching: 2,
                                        hasRead: true, headSlot: base, wasReset: false).lede {} else {
    check(false, "an address that has done nothing reads as quiet")
}

// THE NULLIFIER RULE. `0x0` is the default nonce channel every ordinary
// transaction uses, so counting it lights the scope on an address that has
// never touched the pool.
check(!PrivacyDevnetRoots.isNullifier(Data()), "an empty key is not a nullifier")
check(!PrivacyDevnetRoots.isNullifier(Data([0])), "0x0 is an ordinary nonce, not a nullifier")
check(!PrivacyDevnetRoots.isNullifier(Data(repeating: 0, count: 32)), "32 zero bytes is not a nullifier")
check(PrivacyDevnetRoots.isNullifier(d("0cca26d343c75c5d092b41abc4c7372c0105537e6f5209967fee5bb6b6ca390c")),
      "a real 32-byte key is a nullifier")
// The wire is QUANTITY-encoded, so a real key's leading zero is stripped and it
// arrives as 31 bytes — a length test would drop exactly the measured case.
check(PrivacyDevnetRoots.isNullifier(d("cca26d343c75c5d092b41abc4c7372c0105537e6f5209967fee5bb6b6ca390c")),
      "a 31-byte key (leading zero stripped on the wire) is still a nullifier")
// THE NAMED CHANNELS. Measured on the live chain: this devnet numbers its nonce
// channels after the EIPs under test, and a non-zero test counted every one of
// them as a nullifier — which lights the scope for an address that has never
// touched the pool. Found by running the walk and reading the result.
check(!PrivacyDevnetRoots.isNullifier(d("81410003")), "0x81410003 is a named channel (EIP-8141), not a nullifier")
check(!PrivacyDevnetRoots.isNullifier(d("82500001")), "0x82500001 is a named channel (EIP-8250), not a nullifier")
check(!PrivacyDevnetRoots.isNullifier(d("82502001")), "0x82502001 is a named channel, not a nullifier")
check(!PrivacyDevnetRoots.isNullifier(d("78050000")), "0x78050000 is a named channel (EIP-7805), not a nullifier")

// ─────────────────────────── PrivacyDevnetFigure ──────────────────────
// Written by the session that built the figures; landed here because this
// harness is mine. Every failure renders as an ordinary drawing: two diamonds
// on one point, a mark claiming an age it no longer has, overlapping labels,
// a floored frame silently below its floor, or a count quietly dropped.
typealias PF = PrivacyDevnetFigure
func fref(_ slot: UInt64) -> PrivacyDevnetRoots.Reference {
    PrivacyDevnetRoots.Reference(sourceID: d("aa"), slot: slot, root: d("bb"))
}
let fm = PF.marks([fref(13347), fref(13347), fref(12900), fref(5200)], headSlot: 14450)
check(fm.count == 3, "two proofs against one snapshot are ONE mark, not two diamonds on one point")
check(fm[0].slot == 13347 && fm[0].count == 2, "newest first, and the collapse carries its count")
check(fm[2].position == nil && fm[2].agedBy == 1059, "an aged mark has no position — nil, never zero")
check(fm[2].labelled, "an aged mark always gets words: its position says nothing")
check(fm.filter(\.labelled).count <= PF.labelCap, "labels are capped before the track becomes text")
// **A DISCRIMINATING fixture for the cap.** The set above collapses to exactly
// `labelCap` marks, so removing the cap leaves it unchanged — that mutation
// SURVIVED on this block's first run. Five marks, spread far wider than
// `labelGap` so the spacing rule cannot do the capping instead, is the case
// that can actually fail.
let wide = PF.marks([fref(14400), fref(13000), fref(11500), fref(10000), fref(8500)],
                    headSlot: 14450)
check(wide.count == 5, "the wide fixture really has five marks to label")
check(wide.filter(\.labelled).count == PF.labelCap,
      "and exactly labelCap of them are labelled — the cap, not the spacing, doing the work")
check(PF.marks([fref(14400), fref(14399)], headSlot: 14450).filter(\.labelled).count == 1,
      "two marks a slot apart never both label — the collision this rule exists for")
check(PF.marks([fref(14999)], headSlot: 14450)[0].position == 1,
      "a reference AHEAD of the head pins at now, never past it — a lagging RPC, not the future")
// FOUND while writing: clamp-then-renormalise pushed a floored frame BACK BELOW its floor.
let w = PF.shares([PF.Frame(gasLimit: 900), PF.Frame(gasLimit: 1)])
check(abs(w.reduce(0,+) - 1) < 1e-9, "weighted shares fill the strip exactly")
check(w[1] >= PF.minFrameShare - 1e-9, "the smallest step is still visible AFTER renormalising")
check(w[0] > w[1], "the bigger budget is still the wider bar")
let casc = PF.shares([PF.Frame(gasLimit: 10000), PF.Frame(gasLimit: 1), PF.Frame(gasLimit: 1)])
check(casc.allSatisfy { $0 >= PF.minFrameShare - 1e-9 } && abs(casc.reduce(0,+) - 1) < 1e-9,
      "flooring one frame can push the next below the floor — the cascade must settle")
check(PF.shares([PF.Frame(gasLimit: 90), PF.Frame()])[0] == PF.shares([PF.Frame(gasLimit: 90), PF.Frame()])[1],
      "ONE unread budget falls back to equal widths — never present a leftover as a budget")
check(abs(PF.shares(Array(repeating: PF.Frame(gasLimit: 5), count: 12))[0] - 1.0/12) < 1e-9,
      "too many frames for the floor stops pretending and draws equal")
if case .frame(_, let bad) = PF.anatomy(frames: [PF.Frame(succeeded: nil)], keys: 0, roots: 0, sponsored: false)[0] {
    check(!bad, "an UNREAD status is not a failure — gasUsed/succeeded are nil on 8141")
}
let an = PF.anatomy(frames: [PF.Frame(), PF.Frame()], keys: 2, roots: 1, sponsored: true)
check(an.count == 6, "frames, keys, roots, payer — nothing dropped")
if case .frame = an[0] {} else { check(false, "frames lead: what it DID before what it proved") }
if case .sponsor = an[5] {} else { check(false, "who paid is last") }
check(PF.pips(0).empty == 1, "zero draws one empty pip so the column still reads as a comparison")
check(PF.pips(12).overflow == 4, "over the cap the rest is COUNTED, never silently dropped")
// FOUND: Home's budget was computed against a one-line sentence; the relaunch notice runs to three.
// **WITH A TRACK, HOME DRAWS NO MOVES.** Two estimates in a row (154, then
// 232) left one row that fitted the arithmetic and was CLIPPED mid-line on a
// device — reported twice with a screenshot. A third estimate would have been
// another arithmetic answer to a layout question.
check(PF.homeMoves(hasTrack: true, box: 300) == 0,
      "a track leaves no room for moves — they are one chip away in Activity")
check(PF.homeMoves(hasTrack: false, box: 300) >= 1,
      "without a track the moves ARE the content, so at least one draws")
check(PF.homeMoves(hasTrack: false, box: 300) <= 3, "\"a few\" is three")
// The slot constant is spelled here because this file is Foundation-only; if
// the chassis moves, this silently starts budgeting against the wrong box.
check(PF.DSRoomChassisSlot == 300, "the slot constant still matches DSRoomChassis.visualSlot")
check(PF.rowCap(box: 10, rowHeight: 14, spacing: 6, chrome: 40, minimum: 0) == 0,
      "Home is the ONE list allowed to vanish, so the send panel needs no second decision")
check(PF.rowCap(box: 10, rowHeight: 14, spacing: 6, chrome: 40) == 1,
      "every other scope draws at least one row — a list scope must not render empty")

check(!PrivacyDevnetRoots.present([]), "no references means no roots scope")
check(PrivacyDevnetRoots.present(refs), "references mean the scope draws")

if failures == 0 { print("  ok   \(0) failures") } else { exit(1) }
SWIFT

print "  building…"
xcrun swiftc -Onone -o "$work/pv" "$SECTION" "$ROOTS" "$ROOM" "$FIG" "$work/main.swift" 2>"$work/build.log" \
  || { cat "$work/build.log"; fail "the sources did not compile — they must stay Foundation-only" }
"$work/pv" || fail "assertions failed"
print "  ok   assertions"

# ── mutations ──────────────────────────────────────────────────────────
# Each is a silent wrong answer that renders as an ordinary room. A mutation
# that SURVIVES means the assertions above are not testing what they claim.
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  local dir="$work/m"; rm -rf "$dir"; mkdir -p "$dir"
  cp "$SECTION" "$dir/PrivacyDevnetSection.swift"; cp "$ROOTS" "$dir/PrivacyDevnetRoots.swift"
  cp "$ROOM" "$dir/PrivacyDevnetRoom.swift"; cp "$FIG" "$dir/PrivacyDevnetFigure.swift"
  local target="$dir/$(basename $file)"
  grep -qF -- "$from" "$target" || fail "mutation '$name' matches nothing — it is stale and tests the shipped code"
  python3 - "$target" "$from" "$to" <<'PY'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if xcrun swiftc -Onone -o "$dir/pv" "$dir/PrivacyDevnetSection.swift" "$dir/PrivacyDevnetRoots.swift" \
        "$dir/PrivacyDevnetRoom.swift" "$dir/PrivacyDevnetFigure.swift" "$work/main.swift" 2>/dev/null && "$dir/pv" >/dev/null 2>&1; then
    fail "mutation SURVIVED: $name"
  fi
  print "  ok   caught: $name"
}

mutate "the window off by one (a root expires a slot early)" \
  "$ROOTS" "if age >= windowSlots" "if age > windowSlots"
mutate "an ahead reference reported live instead of stale-head" \
  "$ROOTS" "if reference.slot > headSlot { return .ahead }" "if false { return .ahead }"
mutate "an aged root drawn as an empty meter rather than no meter" \
  "$ROOTS" "guard let left = remaining(reference, headSlot: headSlot) else { return nil }" \
  "let left = remaining(reference, headSlot: headSlot) ?? 0; if false { return nil }"
mutate "the ring resized (the predeploy's own 0x1fff mask ignored)" \
  "$ROOTS" "static let windowSlots: UInt64 = 8192" "static let windowSlots: UInt64 = 4096"
mutate "a group reporting its OLDEST reference as its newest" \
  "$ROOTS" "let newest = refs.max" "let newest = refs.min"
mutate "the source list ordered oldest-first" \
  "$ROOTS" "return a.newest.slot > b.newest.slot" "return a.newest.slot < b.newest.slot"
mutate "home no longer the fallback for a vanished scope" \
  "$SECTION" "guard let wanted, present.contains(wanted) else { return .home }" \
  "guard let wanted else { return .home }"
mutate "the strip drawn over a single chip" \
  "$SECTION" "present.count > 1" "present.count > 0"
mutate "a conditional scope promoted into the stable head" \
  "$SECTION" "case .frames, .nullifiers, .roots, .sponsors: return true" \
  "case .nullifiers, .roots, .sponsors: return true\n        case .frames: return false"
mutate "roots separated from nullifiers" \
  "$SECTION" ".nullifiers, .roots, .sponsors]" ".roots, .nullifiers, .sponsors]"
mutate "a named nonce channel counted as a nullifier" \
  "$ROOTS" 'significant.count >= nullifierFloor' '!significant.isEmpty'
mutate "the nullifier floor measured on RAW bytes (a stripped leading zero drops a real key)" \
  "$ROOTS" 'while significant.first == 0 { significant.removeFirst() }' '' 
  "static func isNullifier(_ key: Data) -> Bool { !key.isEmpty }"
# The figures' own mutations, from the session that wrote them. Each is a
# silent wrong drawing: an ordinary-looking ring, strip or tally that says
# something the chain does not.
mutate "an aged root placed at the far edge rather than nowhere" \
  "$FIG" "return Mark(slot: slot, position: nil, agedBy: by," \
  "return Mark(slot: slot, position: 0, agedBy: by,"
mutate "two labels allowed to overlap (the commonest arrangement there is)" \
  "$FIG" "if let last = lastLabelled, abs(last - p) < labelGap { continue }" \
  "if false { continue }"
mutate "the label cap removed — the track becomes text" \
  "$FIG" "guard spent < labelCap else { break }" "guard true else { break }"
mutate "pips dropping their overflow instead of counting it (§307 again)" \
  "$FIG" "return (pipCap, 0, n - pipCap)" "return (pipCap, 0, 0)"
mutate "zero drawing no pip at all, so the column stops reading as a comparison" \
  "$FIG" "if n == 0 { return (0, 1, 0) }" "if n == 0 { return (0, 0, 0) }"
mutate "an unobserved genesis claiming a relaunch (not knowing read as knowing)" \
  "$ROOM" "if wasReset == true { return finish(.relaunched) }" \
  "if wasReset != false { return finish(.relaunched) }"
mutate "a relaunch demoted below a live root" \
  "$ROOM" "if wasReset == true { return finish(.relaunched) }" "if false { return finish(.relaunched) }"
mutate "a populated room put back into Reading the chain" \
  "$ROOM" "guard hasRead || !accounts.isEmpty else {" "guard hasRead else {"
mutate "the head leading with the root that has LEAST window left" \
  "$ROOM" "a.1 == b.1 ? a.0.slot < b.0.slot : a.1 < b.1" "a.1 == b.1 ? a.0.slot < b.0.slot : a.1 > b.1"
mutate "an aged root drawing a window meter anyway" \
  "$ROOM" "return finish(.rootsAged(count: refs.count))" \
  "return finish(.rootsAged(count: refs.count), fraction: 0)"
mutate "spends swallowed into quiet" \
  "$ROOM" "if nullifiers > 0 { return finish(.spends(nullifiers: nullifiers)) }" \
  "if false { return finish(.spends(nullifiers: nullifiers)) }"
mutate "the head claiming zero watched addresses (a room that says it watches nothing)" \
  "$ROOM" "Head(lede: lede, watching: max(watching, 1)" "Head(lede: lede, watching: watching"
mutate "a chip allowed to wear a dot" \
  "$SECTION" "static func attention() -> Set<PrivacyDevnetSection> { [] }" \
  "static func attention() -> Set<PrivacyDevnetSection> { [.roots] }"

# ── drift guards ───────────────────────────────────────────────────────
# The rules that live in ANOTHER file, which the compiled sources cannot prove.
# Read from a COMMENT-STRIPPED copy: both files DOCUMENT these rules by naming
# the thing they must not do, so a guard over raw source fires on the prose
# explaining it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
out=[]; i=0; n=len(s); instr=False; esc=False
while i < n:
    c = s[i]
    if instr:
        out.append(c)
        if esc: esc=False
        elif c=='\\': esc=True
        elif c=='"': instr=False
        i+=1; continue
    if c=='"': instr=True; out.append(c); i+=1; continue
    if c=='/' and i+1<n and s[i+1]=='/':
        while i<n and s[i]!='\n': i+=1
        continue
    if c=='/' and i+1<n and s[i+1]=='*':
        i+=2
        while i+1<n and not (s[i]=='*' and s[i+1]=='/'): i+=1
        i+=2; continue
    out.append(c); i+=1
sys.stdout.write(''.join(out))
PY
}
strip_comments "$ROOTS" > "$work/roots.bare"
strip_comments "$SECTION" > "$work/section.bare"
strip_comments "$ROOM" > "$work/room.bare"

# NO PRICE, EVER. Test ETH has no market; a figure here would be §83 in the room
# whose whole subject is what can and cannot be claimed.
for w in 'priceValue' 'priceCurrency' 'usdValue' 'formatted(currency'; do
  grep -qF -- "$w" "$work/roots.bare" && fail "PrivacyDevnetRoots names $w — test ETH has no price"
done

# NO NOTIFICATION. §593's ruling: the root window is a deadline nobody can act
# on, so it must never reach the notification sweep.
grep -qE "Notif|NotifyKind|NotifySweep" "$work/roots.bare" \
  && fail "PrivacyDevnetRoots reaches the notification sweep — the window is a deadline nobody can act on"

# THE SLOT/BLOCK RULE. `standing` must compare slots. A block-number parameter
# creeping in is silently correct on a chain that never missed a slot.
grep -qE "blockNumber|blockHeight" "$work/roots.bare" \
  && fail "PrivacyDevnetRoots names a block number — the window is measured in SLOTS (frames runs 5,223 ahead)"

# The chain's own numbers must stay where a reader can find them.
grep -qF "8192" "$work/roots.bare" || fail "the 8192-slot window is no longer stated"

# WATCH-ONLY, MECHANICALLY (§593a). This seat may not sign or broadcast while
# its type-0x6 envelope is unreproduced: a guessed layout yields a signature
# that is well-formed, recovers to a real address, and authorises something
# other than what the screen said, and no build or sweep can see that. The
# catalog bullet says "nothing is signed and nothing is sent", so this guard and
# that copy must be retired in the SAME commit that lands sending.
BRIDGE="Casberi/Casberi/Model/PrivacyDevnetBridge.swift"
[[ -f "$BRIDGE" ]] || fail "$BRIDGE not found"
strip_comments "$BRIDGE" > "$work/bridge.bare"
#
# THE BAN IS ON SIGNING AND BROADCASTING, NOT ON POST. Every JSON-RPC read is a
# POST, so an over-broad `postJSON` ban would stop the seat reading at all —
# which the first cut of this guard did, and which would have read as the seat
# being broken rather than as the guard being wrong. `postJSONBody` IS banned:
# it is the broadcast helper (§530), and nothing this seat reads needs it.
for verb in 'eth_sendRawTransaction' 'eth_sendTransaction' 'eth_sign' 'personal_sign' \
            'eth_signTransaction' 'postJSONBody' 'PrivacyDevnetSend' 'PrivacyDevnetKey' \
            'SecItemAdd' 'secp256k1' 'signingPreimage'; do
  grep -qF -- "$verb" "$work/bridge.bare" \
    && fail "PrivacyDevnetBridge names $verb — the seat is watch-only until the envelope is reproduced (§593a); retire this guard and the catalog bullet in the same commit"
done
# And the copy must keep SAYING it, or the guard protects a promise nobody made.
grep -qF 'Watching only — nothing is signed and nothing is sent' \
  "Casberi/Casberi/Model/BridgeCatalog.swift" \
  || fail "the catalog no longer says this seat only watches, but nothing here signs — restore the bullet or land the write with it"

# THE DEMO FIXTURE'S HEX VALUES ARE PINNED (§593). Two of the four nullifiers
# in `seedDemo` were FABRICATED and shipped — the count was measured by running
# the walk, the values were then written from a different block's census, and
# the comment above them claimed the measurement while standing over invented
# bytes. Nothing here could see it: a fixture that LOOKS like a 32-byte key is
# indistinguishable from one that is, so eye review cannot catch it and the
# harness pinned only the named channels and the width rule.
#
# These four keys, two hashes and two roots were read back off
# `eth_getTransactionByHash` against rpc1.privacy.ethrex.xyz. This guard cannot
# prove a value is real — nothing offline can — but it fails the build the
# moment one CHANGES, which forces the next edit to be a deliberate one that
# says where the new value came from.
for v in \
  '0cca26d343c75c5d092b41abc4c7372c0105537e6f5209967fee5bb6b6ca390c' \
  '277a116036d2c29207c09c18015780c8e161402d2017d07012147a1d4b7240fe' \
  '1871055c1947afa152d04f00757f94f890efa87190de3d8e481d7c22b6b381e1' \
  '1a3f0e61700a2fc8652d33787331f955bff2b1a500426b4dfd83481f5c645ffe' \
  '0xfa32623718a4ac87bca85daa2f62af32522f4e2f763adec8ac2fbde5aeb5cf0f' \
  '0xeda9b1c8231c7ba375c831d63655acc813cf8c7d3ac2b095b23e3011d7b2999a' \
  '448132919986930440'; do
  grep -qF -- "$v" "$work/bridge.bare" \
    || fail "a measured demo fixture value changed or vanished ($v) — every hex value here was read back off the chain, and two were once fabricated; re-measure and say so rather than editing in place"
done
# And the two that were fabricated must never come back.
for v in '055b6c2720e71fbe4d5fa4ad130f4f7b68879ee7d062d0e21af30c5e8ce5839c' \
         '08cda6582e3ed667ed4b907d27093659da30882f1d1437ee86125664ecf6f9ce'; do
  grep -qF -- "$v" "$work/bridge.bare" \
    && fail "a FABRICATED nullifier is back in the demo fixture ($v) — it is on neither of this address's transactions"
done

# THE UNBOUNDED RANGE. A sibling ethrex node already refuses `fromBlock: 0x0`
# with `query exceeds max block range 100000`, and walkCap cannot help because
# it is applied after the response arrives — a refused query returns nil and
# four scopes go silently absent.
grep -qF 'fromBlock": "0x0"' "$work/bridge.bare" \
  && fail "the walk asks for the whole chain in one eth_getLogs again — a sibling node refuses exactly that"
grep -qF 'walkChunk' "$work/bridge.bare" \
  || fail "the walk is no longer chunked"
# THE ORDERING. `reverse()` assumed eth_getLogs answers oldest-first, which no
# spec guarantees; a newest-first node would keep the genesis fixtures and
# report a busy address as quiet — the exact failure the code claimed to prevent.
grep -qF 'hashes.reverse()' "$work/bridge.bare" \
  && fail "the walk orders by reversing the node's own order again — sort on blockNumber/logIndex instead"

# The Foundation-only figure file spells DSRoomChassis.visualSlot itself, since
# it cannot import the design layer. If the chassis moves, Home budgets against
# the wrong box and clips again.
grep -qE 'static let visualSlot: CGFloat = 300' "Casberi/Casberi/Design/DSRoomChassis.swift" \
  || fail "DSRoomChassis.visualSlot changed — PrivacyDevnetFigure spells it as 300 and now budgets against the wrong box"

# THE UNWATCHED ROOM (§593). The seat is in `LiveRoomSources`, which tells the
# feed not to draw the corpus-shaped empty state — so a nil head is a BLACK
# SCREEN, and a deep link reaches this room whether or not anything is watched.
# Reproduced on a simulator when a permission sheet swallowed the tap that
# would have watched an address.
grep -qE 'static func compose\(scope: String\? = nil\) -> PrivacyDevnetRoom\.Head \{' \
  "Casberi/Casberi/Model/PrivacyDevnetRoomSource.swift" \
  || fail "PrivacyDevnetRoomSource.compose is Optional again — a nil head on a LiveRoomSources seat is a BLACK SCREEN, not an empty room"
grep -qF 'case unwatched' "$work/room.bare" \
  || fail "the unwatched lede is gone — the room has nothing to say before anything is watched, which renders as nothing at all"

# THE RELAUNCHED DEMO (§593). `DemoSeedAll` runs on demo ENTRY only, this state
# is in-memory, and DemoMode is sticky across launches — so a relaunch inside a
# demo leaves the fixture gone AND the live read refused, and the room says
# "Reading the chain…" forever over a chain it is not allowed to read. Reported
# from a device. `HegotaLiveState.refreshIfStale` had already solved it.
grep -qE 'if DemoMode\.isActive \{[^}]*seedDemo' "$work/bridge.bare" \
  || grep -qF 'if accounts.isEmpty { PrivacyDevnetLiveState.seedDemo() }' "$work/bridge.bare" \
  || fail "refreshIfStale no longer re-installs the demo fixture — a relaunched demo would sit on 'Reading the chain…' over a chain it is not allowed to read"

# THE OBSERVATION MECHANISM (§593). This shipped as `ObservableObject` +
# `@Published`, and the room reads it through STATIC functions — where a
# `@Published` read establishes no dependency at all. The demo fixture installs
# asynchronously, SwiftUI never learns, and the room sits on "Reading the
# chain…" forever over a fixture already in memory. It passed my own testing
# because the install happened to land before the first compose, which is what
# makes it a race rather than a miss. Both sibling seats use `@Observable`.
grep -qF '@Observable' "$work/bridge.bare" \
  || fail "PrivacyDevnetLiveState is not @Observable — the room reads it from static functions, so ObservableObject would leave it on 'Reading the chain…' whenever the install loses the race"
grep -qF 'ObservableObject' "$work/bridge.bare" \
  && fail "PrivacyDevnetLiveState is an ObservableObject again — a @Published read from a static context tracks nothing"

# THE WALK'S BOUNDS (§593). Its stated ceiling is that a transaction emitting no
# log is invisible, and its cost is bounded three ways. Each of these failing is
# invisible from outside: a room that is merely slow, or one that reports a busy
# address as quiet.
grep -qE 'value.block > .1.value.block' "$work/bridge.bare" \
  || fail "the walk no longer orders newest-first — on a chain that outgrows walkCap that reports a busy address as quiet"
grep -qF 'prefix(Self.walkCap)' "$work/bridge.bare" \
  || fail "the walk is unbounded — its cost would grow with the chain until a room open costs minutes"
grep -qF 'refreshIfStale' "$work/bridge.bare" \
  || fail "the walk lost its staleness guard — it is ~15s and would run on every room open"
# The receipt is read ONLY for a transaction already matched to a watched
# address. Reading one per log-touched transaction triples the walk for nothing.
grep -qF 'wanted.contains(sender) else { continue }' "$work/bridge.bare" \
  || fail "the walk no longer filters to watched senders before reading receipts"

# THE BLACK-SCREEN RULE, mechanically: this seat lands no Thing, so a nil head
# is not an empty room but a black screen. `head` must return a non-optional.
grep -qE "static func head\(.*\) -> Head\?" "$work/room.bare" \
  && fail "PrivacyDevnetRoom.head became Optional — a nil head on a rowless seat is a BLACK SCREEN (the Hegota room reached a device four times that way)"

# THE COINS BAN, mechanically. A `coins` case added later compiles fine.
grep -qE "case +coins" "$work/section.bare" \
  && fail "a coins scope reappeared — the UTXO vault has no code on 8141, so the chip could never light"

# This harness must stay in verify.sh's hand list (that guard fails the build
# until it is named WITH its reason, which is the part that gets skipped).
grep -q "privacy-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

print "  ok   drift guards: no price, no notification, slots not blocks, no coins scope"
print "✓ privacy: 7 scopes, the 8272 window, the room head, the figures, 25 mutations, 7 drift guards"
