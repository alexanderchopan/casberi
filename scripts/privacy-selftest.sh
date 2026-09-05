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
# The moments ledger (prd §598). Foundation-only and every store injectable,
# because a once-ever flag whose only proof is "it did not fire again on my
# phone" is not proven at all — and because the failure this catches is the
# retroactive claim: a "your first transaction landed" fired over an account
# that sent last week.
MOMENTS="Casberi/Casberi/Model/PrivacyDevnetMoments.swift"
# Foundation-only, and compiled here so the root derivation can be pinned
# against a hash the chain really produced rather than against a stub.
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
VERIFY="scripts/verify.sh"
for f in "$SECTION" "$ROOTS" "$ROOM" "$FIG" "$MOMENTS" "$KECCAK"; do [[ -f "$f" ]] || fail "$f not found"; done

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
// **AGED MARKS ARE NOT LABELLED (prd §593d).** "gone N ago" stacked into a
// double line under the track that read as broken; the hollow shape past the
// leading edge and the axis label already say it. Only live marks earn words.
check(!fm[2].labelled, "an aged mark carries no label — the hollow shape past the edge is the reading")
check(fm.filter(\.labelled).allSatisfy { $0.position != nil }, "only live marks are labelled")
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

// ── prd §598: the ring, the ordinal, and the estimate that may not age ──
// Every failure below renders as an ordinary ring: two sets folded into one
// diamond, a live snapshot drawn in the exit gap, an ordinal that changes
// between opens, or an estimate quietly deciding a proof has expired.

// **THE COLLAPSE IS BY (SET, SLOT), NOT BY SLOT.** Two sources may register in
// the same slot, and folding those into one mark draws two anonymity sets as
// one point — the exact error the ring exists to make visible.
func fref2(_ slot: UInt64) -> PrivacyDevnetRoots.Reference {
    PrivacyDevnetRoots.Reference(sourceID: d("bb"), slot: slot, root: d("cc"))
}
let shared = PF.marks([fref(13347), fref2(13347)], headSlot: 14450)
check(shared.count == 2, "two SOURCES registering in one slot are two marks, not one")
check(Set(shared.map(\.id)).count == 2, "and their ids differ, or a ForEach draws one of them")
check(Set(shared.map(\.set)).count == 2, "each carries its own set's ordinal")
// The ordinal is `bySource`'s own total order, so it cannot reshuffle.
let orderA = PF.marks([fref(13347), fref2(13347)], headSlot: 14450).map { "\($0.set):\($0.slot)" }
let orderB = PF.marks([fref2(13347), fref(13347)], headSlot: 14450).map { "\($0.set):\($0.slot)" }
check(orderA == orderB, "the ordinal a set wears is total — a ring that renumbers between opens reads as broken")
check(PF.marks([fref(13347)], headSlot: 14450)[0].set == 0, "a lone source is set 0")

// **NOW IS AT THE TOP AND AGE RUNS CLOCKWISE.**
check(PF.ringAngle(position: 1) == 0, "a snapshot registered this slot sits at NOW")
check(abs(PF.ringAngle(position: 0) - PF.ringSweep) < 1e-9,
      "one about to leave sits at the end of the arc, just before the gap")
check(PF.ringAngle(position: nil) == PF.ringAgedAngle,
      "an aged snapshot sits INSIDE the gap — out of the ring, which is where it is")
check(PF.ringAgedAngle > PF.ringSweep,
      "and the gap really is past the arc's end, or an aged mark lands among the live ones")
check(PF.ringSweep < 360, "the ring is OPEN — the gap is the exit, and it is what replaced the caption")

// **THE NUDGE: crowding relieved, order and age exact.**
let ringCrowded = PF.ringPlacements(PF.marks([fref(14449), fref(14448), fref(14447)], headSlot: 14450))
check(ringCrowded.count == 3, "three snapshots minutes apart stay three marks")
let angles = ringCrowded.filter { $0.mark.position != nil }.map(\.angle).sorted()
check(zip(angles, angles.dropFirst()).allSatisfy { $1 - $0 >= PF.ringGap - 1e-9 },
      "and none is closer than one mark-width to its neighbour")
// **A DISCRIMINATING FIXTURE FOR THE EXIT SWEEP, and the first one was not.**
// Three marks crowded at NOW nudge to 0/12/24 and never approach the arc's
// end, so deleting the exit sweep left the suite green — the mutation SURVIVED
// on this block's first run. The case that can actually fail is three marks
// crowded at the OLD end, where the forward push runs them past the exit and
// into the gap, i.e. draws three live snapshots as three that have left.
let ancient = PF.marks([fref(100), fref(101), fref(102)], headSlot: 100 + 8190)
check(ancient.allSatisfy { $0.position != nil }, "the fixture's marks really are still live")
let atExit = PF.ringPlacements(ancient)
check(atExit.allSatisfy { $0.angle <= PF.ringSweep + 1e-9 },
      "no LIVE mark is ever pushed into the gap — that reads as one that has already left")
let exitAngles = atExit.map(\.angle).sorted()
check(zip(exitAngles, exitAngles.dropFirst()).allSatisfy { $1 - $0 >= PF.ringGap - 1e-9 },
      "and pulling them back off the exit keeps them a mark-width apart")
check(ringCrowded.allSatisfy { $0.mark.position == nil || $0.angle <= PF.ringSweep + 1e-9 },
      "the crowded-at-NOW set stays on the arc too")
// Aged marks are not spread: they are all in one place by definition.
let mixedAged = PF.ringPlacements(PF.marks([fref(1), fref(2)], headSlot: 20000))
check(Set(mixedAged.map(\.angle)) == [PF.ringAgedAngle],
      "aged marks are never nudged apart — the gap carries no scale to spread them along")

// **THE DRIFT IS AN ESTIMATE AND MAY NEVER CROSS THE RIM.** This is the whole
// safety argument for a moving ring: only a real read may say a snapshot has
// aged out, because the seconds-per-slot figure is this devnet's ASSUMED
// cadence and the aged state is the only one here that changes what a row says.
check(PF.drifted(position: 1, secondsSinceRead: 0) == 1, "no time, no drift")
check(PF.drifted(position: 0.5, secondsSinceRead: 120) < 0.5, "the ring drains while nobody reads it")
check(PF.drifted(position: 0.0001, secondsSinceRead: 100_000) > 0,
      "an estimate NEVER reaches the rim — aging a proof out is a read's job alone")
check(PF.drifted(position: 0.5, secondsSinceRead: 100_000)
      == PF.drifted(position: 0.5, secondsSinceRead: PF.driftCap),
      "and it FREEZES at the cap — extrapolating an unobserved hour is inventing an hour of chain")
check(PF.drifted(position: 0.5, secondsSinceRead: -5) == 0.5, "a clock that ran backwards moves nothing")

// ── prd §598: words a reader can feel, hedged every time ──
check(PrivacyDevnetRoots.approximate(slots: 8192).contains("about"),
      "the conversion ALWAYS says about — the slot time is an assumption, not a measurement")
check(PrivacyDevnetRoots.approximate(slots: 1) == "under a minute", "12 seconds is under a minute")
check(PrivacyDevnetRoots.approximate(slots: 300) == "about 1 hour",
      "300 slots at 12s IS an hour — and reads as one, not as sixty minutes")
check(PrivacyDevnetRoots.approximate(slots: 50).contains("minute"), "ten minutes of slots reads in minutes")
check(PrivacyDevnetRoots.approximateShort(slots: 8192).hasPrefix("~"),
      "the short form carries the hedge as a tilde — the one place the word does not fit")
// A single set is not "Set 1": an ordinal implies a second.
check(PrivacyDevnetRoots.setLabel(0, of: 1) == "The set", "one source wears no number")
check(PrivacyDevnetRoots.setLabel(0, of: 2) == "Set 1", "two sources are numbered from one")
check(PrivacyDevnetRoots.setIndex(of: src, in: refs) != nil, "a known source has an ordinal")
check(PrivacyDevnetRoots.setIndex(of: d("ff"), in: refs) == nil, "an unknown one has none — never 0")
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
// **HOME'S MOVES ARE A STATED CAP, NOT A BOX BUDGET (prd §602).** They used
// to be budgeted against `DSRoomSlot`'s 300pt box because they were drawn
// INSIDE it, and that box clips: two estimates each cut a row mid-line on a
// device, and the ruling became "with a figure, draw none" — which is every
// time a proof is live, so the scope promised "the last few moves" and had
// none. Below the rail nothing clips, so there is no third estimate to get
// wrong.
check(PF.homeMoveCap == 3, "\"a few\" is three — past that it is the Activity scope one chip away")
check(PF.homeMoveCap > 0, "Home lists its moves again rather than promising them and showing none")
// **THE MIRRORED SLOT CONSTANT IS GONE WITH THE BUDGET THAT NEEDED IT (§602).**
// This file spelled `DSRoomChassis.visualSlot` itself because it is
// Foundation-only and could not import the design layer — a mirror that had to
// be kept level by hand. Home's rows moved below the rail, so nothing here
// budgets against that box any more and the mirror is deleted rather than
// left to drift.
check(PF.rowCap(box: 10, rowHeight: 14, spacing: 6, chrome: 40, minimum: 0) == 0,
      "Home is the ONE list allowed to vanish, so the send panel needs no second decision")
check(PF.rowCap(box: 10, rowHeight: 14, spacing: 6, chrome: 40) == 1,
      "every other scope draws at least one row — a list scope must not render empty")

check(!PrivacyDevnetRoots.present([]), "no references means no roots scope")
check(PrivacyDevnetRoots.present(refs), "references mean the scope draws")

// ───────────────── the predeploy's own storage (prd §593d) ─────────────────
// MEASURED against live state on 2026-09-04: all four root-carrying
// transactions on 8141 matched byte-for-byte. These pin the derivation read off
// the deployed bytecode, and every failure below renders as a probe that says a
// registration is missing when the chain is holding it.

check(PrivacyDevnetRoots.ringIndex(slot: 2801) == 2801, "a slot inside the first turn is its own index")
check(PrivacyDevnetRoots.ringIndex(slot: 13361) == 13361 - 8192, "a slot past one turn wraps by exactly the window")
check(PrivacyDevnetRoots.ringIndex(slot: 8192) == 0, "the first slot of the second turn lands on index 0")

check(PrivacyDevnetRoots.bigEndian64(1) == d("0000000000000001"), "a slot is EIGHT big-endian bytes")
check(PrivacyDevnetRoots.bigEndian64(0xaf1) == d("0000000000000af1"), "0xaf1 as eight bytes")

// 32-BYTE PADDING. The wire is quantity-encoded, so a sourceId or root whose
// first byte is zero arrives 31 bytes long — hashing it as-is derives a key
// that matches nothing, which reads as the chain having forgotten a
// registration it still holds.
check(PrivacyDevnetRoots.padded32(d("0cca26d3")).count == 32, "a short value is left-padded to 32")
check(PrivacyDevnetRoots.padded32(d("0cca26d3")).first == 0, "the padding goes on the LEFT")
check(PrivacyDevnetRoots.padded32(d("0cca26d3")).last == 0xd3, "the value keeps its low byte")

check(PrivacyDevnetRoots.bytes(hex: "0x0a0b") == d("0a0b"), "an 0x prefix is accepted")
check(PrivacyDevnetRoots.bytes(hex: "0a0b") == d("0a0b"), "a bare hex string is accepted")
check(PrivacyDevnetRoots.bytes(hex: "0a0") == Data(), "an odd length yields EMPTY, never a partial key")
check(PrivacyDevnetRoots.bytes(hex: "zz") == Data(), "a non-hex character yields EMPTY")
check(PrivacyDevnetRoots.bytes(hex: PrivacyDevnetRoots.registrationHashDomain).count == 32,
      "the value domain is a full word")
check(PrivacyDevnetRoots.bytes(hex: PrivacyDevnetRoots.registrationSlotDomain).count == 32,
      "the slot domain is a full word")

// THE PREIMAGE LENGTHS, which are what the disassembly actually pinned: the
// contract hashes 0x68 (104) bytes for the value and 0x48 (72) for the key. An
// off-by-a-word here compiles, runs, and matches nothing.
var valuePre = Data()
_ = PrivacyDevnetRoots.registrationValue(
    sourceID: d("b08f15750c491f4cfd65215c11a33b3962903a8896fc586bbd7c697851c26e20"),
    // Past the window, for the reason spelled at the key fixture below: inside
    // the first turn the raw slot and the ring index are the same number.
    slot: 13361,
    root: d("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4"),
    hash: { valuePre = $0; return Data(repeating: 0, count: 32) })
check(valuePre.count == 104, "the value preimage is 104 bytes: domain, source, an EIGHT-byte slot, root")
// **THE SLOT HERE MUST BE PAST THE WINDOW, AND THE FIRST CUT'S WAS NOT.** With
// slot 0xaf1 (2801) the ring index IS 2801, so "hashes the ring index" and
// "hashes the raw slot" are the same assertion and the mutation swapping them
// SURVIVED on the first run. 13361 wraps to 5169, which is the only shape that
// tells the two apart — a fixture only tests the rule it names if it fails that
// rule and passes every other one.
check(PrivacyDevnetRoots.ringIndex(slot: 13361) != 13361,
      "the fixture's own premise: this slot really is past one turn of the ring")
var keyPre = Data()
_ = PrivacyDevnetRoots.registrationKey(
    sourceID: d("b08f15750c491f4cfd65215c11a33b3962903a8896fc586bbd7c697851c26e20"),
    slot: 13361,
    hash: { keyPre = $0; return Data(repeating: 0, count: 32) })
check(keyPre.count == 72, "the key preimage is 72 bytes: domain, source, an EIGHT-byte ring index")
check(keyPre.suffix(8) == PrivacyDevnetRoots.bigEndian64(13361 - 8192),
      "the key hashes the RING INDEX, not the raw slot — the whole point of the mask")
check(valuePre.suffix(40).prefix(8) == PrivacyDevnetRoots.bigEndian64(13361),
      "the VALUE hashes the raw slot, not the ring index")
check(PrivacyDevnetRoots.windowSlots == 8192,
      "the window is the predeploy's own 0x1fff mask plus one")

// **THE MEASURED VECTOR, END TO END.** Everything above pins a preimage's
// SHAPE; this pins the answer. `0xfa32623718…` on chain 8141 references this
// source, slot and root, and `eth_getStorageAt(0x…8272, key)` really returns
// this word — read on 2026-09-04. Without it the two domain constants can be
// swapped and every length assertion above still passes, which is exactly what
// happened on this harness's first run.
let realSource = d("a0dfea37afb843c1fc18cfa21205766b96e6f7c7d7993ab5d5e041e0b1964f54")
let realRoot = d("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")
func kec(_ x: Data) -> Data { Data(Keccak256.hash([UInt8](x))) }
check(kec(Data()).map { String(format: "%02x", $0) }.joined()
      == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
      "the harness's own keccak is Keccak-256 and not NIST SHA3 — different padding, different hash")
check(PrivacyDevnetRoots.registrationKey(sourceID: realSource, slot: 13361, hash: kec)
      == d("0bb304652ae43d052d74492ecf73f05b142ecafb1f8b13f42f81f119699b398e"),
      "the storage key for a real reference, measured")
check(PrivacyDevnetRoots.registrationValue(sourceID: realSource, slot: 13361, root: realRoot, hash: kec)
      == d("26dd34bbf3729b0bbfad49ee5f9e41a4fcc02cd165398ffe69453ee48c18bc2e"),
      "the word the chain is really storing there, measured")

// ─────────────────── marks stay countable (prd §593d) ───────────────────
// The Activity figure collapsed on the real chain: the pool address's four
// transactions sit in two pairs five blocks apart across ~10,500, so two marks
// rendered as one. Every failure below draws a figure that under-reports how
// many transactions there were.

let crowded = PrivacyDevnetFigure.spaced([13351, 13356, 2801, 2806], width: 300, mark: 9)
check(crowded.count == 4, "one mark per value, always")
check(zip(crowded, crowded.dropFirst()).allSatisfy { $1 - $0 >= 8.999 },
      "no two marks are closer than one mark's width — the collapse this exists to fix")
check(crowded == crowded.sorted(), "marks come back in ascending position: a nudge, never a re-ranking")
check(crowded.allSatisfy { $0 >= 0 && $0 <= 300 - 9 }, "every mark is on the track")
check(abs(crowded[0] - 0) < 0.001, "the earliest keeps the left edge exactly")
check(abs(crowded[crowded.count - 1] - (300 - 9)) < 0.001, "the latest keeps the right edge exactly")

check(PrivacyDevnetFigure.spaced([], width: 300, mark: 9).isEmpty, "nothing in, nothing out")
let one = PrivacyDevnetFigure.spaced([42], width: 300, mark: 9)
check(one.count == 1 && abs(one[0] - (300 - 9) / 2) < 0.001,
      "a lone mark CENTRES — at the left edge it reads as the beginning of something that isn't there")
let same = PrivacyDevnetFigure.spaced([7, 7, 7], width: 300, mark: 9)
check(same.count == 3 && zip(same, same.dropFirst()).allSatisfy { $1 - $0 >= 8.999 },
      "three transactions in ONE block still draw three marks")
// A track too narrow to hold them: an even spread rather than a stack at the
// right edge, which is what clamping alone produces.
let tight = PrivacyDevnetFigure.spaced([1, 2, 3, 4, 5], width: 20, mark: 9)
check(tight.count == 5, "a narrow track still draws every mark")
check(tight == tight.sorted(), "and still in order")
check(Set(tight).count == 5, "and does not stack them all on one point")

// ── prd §602: what it was allowed, and what it spent ──
// The room could state every transaction's BUDGET and no transaction's COST,
// over a receipt the walk had already fetched. Every failure here renders as
// an ordinary bar: a denominator summed over frames that did not all carry
// one, a transfer claiming to have overspent a budget it never had, or a fill
// drawn past its own track.
check(PF.allowance([]) == nil,
      "a plain transfer has NO allowance — nil, never zero, or it reads as having overspent nothing")
check(PF.allowance([PF.Frame(gasLimit: 21_000), PF.Frame(gasLimit: 9_000)]) == 30_000,
      "the allowance is the sum of the frame budgets")
check(PF.allowance([PF.Frame(gasLimit: 21_000), PF.Frame()]) == nil,
      "ONE unread budget and there is no total — a partial sum stated as the whole is a number invented here")
check(PF.allowance([PF.Frame(gasLimit: 0)]) == nil, "a zero total is no denominator at all")
check(PF.allowance([PF.Frame(gasLimit: .max), PF.Frame(gasLimit: .max)]) == nil,
      "a budget wide enough to overflow 64 bits is refused, never wrapped into a small honest-looking number")
check(PF.usedShare(gasUsed: nil, frames: [PF.Frame(gasLimit: 100)]) == nil,
      "an unread receipt says nothing — not zero spent")
check(PF.usedShare(gasUsed: 50, frames: []) == nil,
      "a spend with no allowance draws no bar; the sheet states the figure alone")
check(PF.usedShare(gasUsed: 50, frames: [PF.Frame(gasLimit: 100)]) == 0.5,
      "half the budget spent is half the track")
// The clamp is a REAL case: the receipt's total covers the whole transaction
// while the allowance sums the FRAME budgets, and nothing makes the first sit
// inside the second.
check(PF.usedShare(gasUsed: 400, frames: [PF.Frame(gasLimit: 100)]) == 1,
      "an overrun fills the track and never runs past it — the exact figures are in words beside it")

// ── prd §598: the moments, and everything they refuse to claim ──
// Every failure here is a wrong CLAIM rather than a wrong drawing: a "your
// first transaction landed" over an account that sent last week, a moment
// that fires twice, or a room that seals forty rings the day somebody
// arrives. A scratch suite, so the harness never touches a real install's
// ledger and every assertion starts from a known state.
typealias PM = PrivacyDevnetMoments
let box = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!

// **RULE 1: NEVER RETROACTIVE.** A non-zero nonce on the install's first read
// means the send happened before anything was watching.
check(PM.isFirstRead(box), "a fresh install has not read yet")
check(!PM.noteNonce(3, seeding: true, box),
      "an account that had ALREADY sent is seeded in silence — never congratulated for history")
check(!PM.firstSettleOwed(box), "and the moment is spent, so it can never fire later")

let box2 = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!
check(!PM.noteNonce(0, seeding: true, box2), "an account that has never sent earns nothing")
check(PM.firstSettleOwed(box2), "and the moment is still owed")
check(!PM.noteNonce(nil, seeding: false, box2), "an UNREAD nonce is not a zero and not a landing")
check(PM.firstSettleOwed(box2), "a failed read leaves the moment owed")
check(PM.noteNonce(1, seeding: false, box2),
      "0 → 1 watched by this device IS the first transaction landing")
check(PM.firstSettleOwed(box2), "and it stays owed until the ROOM says so — nobody was necessarily looking")
PM.spendFirstSettle(box2)
check(!PM.firstSettleOwed(box2), "spent once the room has drawn it")
check(!PM.noteNonce(9, seeding: false, box2), "and never again")

// **RULE 2: a discovery, not an achievement** — and seeded the same way.
let box3 = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!
check(!PM.notePoolSight(hasKeys: false, seeding: false, box3), "no keys, no moment")
check(PM.poolSightOwed(box3), "and nothing is spent by looking")
check(!PM.notePoolSight(hasKeys: true, seeding: true, box3),
      "an address watched before this build brings its keys with it — silence")
check(!PM.poolSightOwed(box3), "seeded, so it cannot fire tomorrow over the same keys")

let box4 = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!
check(PM.notePoolSight(hasKeys: true, seeding: false, box4), "a pool key appearing while watching IS the moment")
PM.spendPoolSight(box4)
check(!PM.notePoolSight(hasKeys: true, seeding: false, box4), "once ever")

// **THE SEEN LEDGER.** First sight seeds silently; only a genuinely new key
// seals. `hasSeenAnyKey` is what separates "you just arrived" from "one
// landed", and the room reads it before `unseen`.
let box5 = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!
let k1 = d("0cca26d3"), k2 = d("aa11bb22"), k3 = d("cc33dd44")
check(!PM.hasSeenAnyKey(box5), "a device that has seen nothing says so")
check(PM.unseen([k1, k2], box5).count == 2, "before anything is recorded every key is unseen")
PM.markSeen([k1, k2], box5)
check(PM.hasSeenAnyKey(box5), "and after the first read it has")
check(PM.unseen([k1, k2], box5).isEmpty, "a key already seen never seals again")
check(PM.unseen([k1, k3], box5) == [PM.hex(k3)], "only the new one seals")
PM.markSeen([k1, k3], box5)
check(PM.unseen([k3], box5).isEmpty, "and then it too is remembered")
// The cap drops the OLDEST, so the keys most likely to be on screen survive.
let many = (0..<(PM.seenCap + 20)).map { Data([UInt8($0 % 251), UInt8($0 / 251), 0xab]) }
let box6 = UserDefaults(suiteName: "privacy-selftest-\(UUID().uuidString)")!
PM.markSeen(many, box6)
check(PM.unseen([many[many.count - 1]], box6).isEmpty, "the NEWEST key is kept")
check(!PM.unseen([many[0]], box6).isEmpty, "and the oldest is the one dropped by the cap")

if failures == 0 { print("  ok   \(0) failures") } else { exit(1) }
SWIFT

print "  building…"
xcrun swiftc -Onone -o "$work/pv" "$SECTION" "$ROOTS" "$ROOM" "$FIG" "$MOMENTS" "$KECCAK" "$work/main.swift" 2>"$work/build.log" \
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
  cp "$MOMENTS" "$dir/PrivacyDevnetMoments.swift"; cp "$KECCAK" "$dir/Keccak256.swift"
  local target="$dir/$(basename $file)"
  grep -qF -- "$from" "$target" || fail "mutation '$name' matches nothing — it is stale and tests the shipped code"
  python3 - "$target" "$from" "$to" <<'PY'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if xcrun swiftc -Onone -o "$dir/pv" "$dir/PrivacyDevnetSection.swift" "$dir/PrivacyDevnetRoots.swift" \
        "$dir/PrivacyDevnetRoom.swift" "$dir/PrivacyDevnetFigure.swift" \
        "$dir/PrivacyDevnetMoments.swift" "$dir/Keccak256.swift" "$work/main.swift" 2>/dev/null && "$dir/pv" >/dev/null 2>&1; then
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
# **THIS MUTATION HAD NEVER RUN (found by prd §593d).** A trailing space after
# the empty replacement broke the line continuation, so zsh executed the next
# line as a command — "command not found: static func isNullifier…" scrolled
# past in the middle of a passing run, and the check it names has been inert
# since it was written. A guard that cannot fail certifies nothing, which is
# this repo's own standing rule turned on its own harness.
mutate "the nullifier floor measured on RAW bytes (a stripped leading zero drops a real key)" \
  "$ROOTS" 'while significant.first == 0 { significant.removeFirst() }' ''
# The figures' own mutations, from the session that wrote them. Each is a
# silent wrong drawing: an ordinary-looking ring, strip or tally that says
# something the chain does not.
mutate "an aged root placed at the far edge rather than nowhere" \
  "$FIG" "return Mark(slot: key.slot, position: nil, agedBy: by," \
  "return Mark(slot: key.slot, position: 0, agedBy: by,"
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

# ── prd §593d ──────────────────────────────────────────────────────────
# The predeploy derivation and the mark spacing. Each of these renders as an
# ordinary probe or an ordinary figure while saying something the chain does not.
mutate "the storage key hashing the RAW SLOT instead of the ring index" \
  "$ROOTS" "pre.append(bigEndian64(ringIndex(slot: slot)))" "pre.append(bigEndian64(slot))"
mutate "the stored VALUE hashing the ring index instead of the raw slot" \
  "$ROOTS" "pre.append(bigEndian64(slot))
        pre.append(padded32(root))" "pre.append(bigEndian64(ringIndex(slot: slot)))
        pre.append(padded32(root))"
mutate "the two domain constants swapped (both are 32 bytes, so nothing else notices)" \
  "$ROOTS" "var pre = bytes(hex: registrationSlotDomain)" "var pre = bytes(hex: registrationHashDomain)"
mutate "a slot written as a full WORD, so the preimage is 128 bytes not 104" \
  "$ROOTS" "var out = Data(count: 8)" "var out = Data(count: 32)"
mutate "a slot written little-endian" \
  "$ROOTS" "out[7 - i] = UInt8((v >> (8 * UInt64(i))) & 0xff)" \
  "out[i] = UInt8((v >> (8 * UInt64(i))) & 0xff)"
mutate "a short value padded on the RIGHT, which is what a quantity-encoded root needs least" \
  "$ROOTS" "return Data(repeating: 0, count: 32 - d.count) + d" \
  "return d + Data(repeating: 0, count: 32 - d.count)"
mutate "an odd-length hex string read as a partial key instead of refused" \
  "$ROOTS" "guard s.count % 2 == 0 else { return Data() }" "guard true else { return Data() }"
# **ANCHORED TO THE BODY, because the doc above it quotes the expression
# verbatim.** The first cut matched the COMMENT — `mutate` replaces the first
# occurrence — so it edited the prose explaining the rule and left the rule
# alone, and survived. The Obsidian/Cursor lesson arriving through a mutation
# rather than through a grep guard.
mutate "the ring mask widened, so a wrapped slot never collides with its own index" \
  "$ROOTS" "-> UInt64 { slot & (windowSlots - 1) }" "-> UInt64 { slot & (windowSlots * 2 - 1) }"

mutate "marks allowed to overlap again — the collapse the Activity figure shipped with" \
  "$FIG" "for i in 1..<out.count where out[i] - out[i - 1] < mark {" \
  "for i in 1..<out.count where false {"
mutate "a lone mark drawn at the left edge instead of centred" \
  "$FIG" "guard values.count > 1 else { return [usable / 2] }" \
  "guard values.count > 1 else { return [0] }"
mutate "marks re-ranked to fit, which is a worse lie than the crowding" \
  "$FIG" "var out = sorted.map" "var out = values.map"
mutate "the right-hand sweep dropped, so the last mark is pushed off the track" \
  "$FIG" "if out[out.count - 1] > usable {" "if false {"
mutate "a track too narrow stacking every mark on one point" \
  "$FIG" "guard usable >= mark * Double(out.count - 1) else {" "guard true else {"

# ── prd §598: the ring, the estimate, the moments ─────────────────────
mutate "two SOURCES folded onto one slot, drawing two anonymity sets as one point" \
  "$FIG" "counts[Key(set: setOf[r.sourceID] ?? 0, slot: r.slot), default: 0] += 1" \
  "counts[Key(set: 0, slot: r.slot), default: 0] += 1"
mutate "the ring closed, so the exit gap that replaced the axis caption is gone" \
  "$FIG" "static let ringSweep: Double = 300" "static let ringSweep: Double = 360"
mutate "an aged mark placed on the arc among the live ones rather than in the gap" \
  "$FIG" "static let ringAgedAngle: Double = 316" "static let ringAgedAngle: Double = 150"
mutate "the arc's crowding nudge dropped — proofs minutes apart draw as one diamond" \
  "$FIG" "for i in 1..<angles.count where angles[i] - angles[i - 1] < gap {" \
  "for i in 1..<angles.count where false {"
mutate "a LIVE mark pushed into the exit gap, reading as one that already left" \
  "$FIG" "if let last = angles.last, last > ringSweep {" "if false {"
mutate "aged marks spread along the gap, inventing a scale where there is none" \
  "$FIG" "out.append(contentsOf: aged.map { Placement(mark: \$0, angle: ringAgedAngle) })" \
  "out.append(contentsOf: aged.enumerated().map { Placement(mark: \$0.1, angle: ringAgedAngle + Double(\$0.0) * 6) })"
# THE SHARPEST ONE. The drift is an ESTIMATE; letting it reach the rim means
# the app decides a proof expired on an assumed slot cadence, and the row it
# feeds says so in words.
mutate "the drift allowed to age a snapshot out — an estimate deciding a proof expired" \
  "$FIG" "return max(moved, min(position, driftFloor))" "return max(moved, 0)"
mutate "the drift running forever instead of freezing — inventing unobserved chain" \
  "$FIG" "let elapsed = min(secondsSinceRead, driftCap)" "let elapsed = secondsSinceRead"
mutate "one source numbered as if it were the first of several" \
  "$ROOTS" "guard total > 1 else { return String(localized: \"The set\") }" \
  "guard total > 0 else { return String(localized: \"The set\") }"
mutate "the conversion dropping its hedge — an assumed cadence stated as a reading" \
  "$ROOTS" "return h == 1 ? String(localized: \"about 1 hour\")" \
  "return h == 1 ? String(localized: \"1 hour\")"
mutate "an unknown source given ordinal 0 rather than none" \
  "$ROOTS" "bySource(references).firstIndex { \$0.source == source }" \
  "bySource(references).firstIndex { \$0.source == source } ?? 0"
# `mutate` replaces the FIRST match, so these anchor on lines whose first
# occurrence is the branch under test — `noteNonce`'s seed and
# `notePoolSight`'s — rather than on the spend functions further down.
mutate "the first moment fired over history — congratulating somebody for last week" \
  "$MOMENTS" "if seeding {" "if false {"
mutate "the pool sighting seeding without recording it, so it fires tomorrow instead" \
  "$MOMENTS" "defaults.set(true, forKey: poolSightKey)" "_ = poolSightKey"
mutate "an UNREAD nonce read as a landing" \
  "$MOMENTS" "guard let nonce, firstSettleOwed(defaults) else { return false }" \
  "let nonce = nonce ?? 1; guard firstSettleOwed(defaults) else { return false }"
mutate "a key that has already sealed sealing again on every open" \
  "$MOMENTS" "return Set(keys.map(hex).filter { !known.contains(\$0) })" \
  "return Set(keys.map(hex))"
mutate "a partial budget sum stated as the transaction's whole allowance" \
  "$FIG" "guard let gas = frame.gasLimit else { return nil }" \
  "let gas = frame.gasLimit ?? 0"
# **THE ZERO TEST IS WHAT ANSWERS THE TRANSFER CASE**, and it is the only
# thing that does — an empty frame list runs the loop zero times and leaves the
# total at 0, so this one line stands between a plain transfer and a
# denominator of zero. The first cut of this block wrote a separate
# empty-list guard as well and the mutation against it SURVIVED, because two
# guards for one case means neither can be shown to matter.
mutate "a transfer given a zero allowance, so it reads as overspending nothing" \
  "$FIG" "return total > 0 ? total : nil" "return total"
mutate "the used bar allowed to run past its own track" \
  "$FIG" "return min(1, Double(gasUsed) / Double(allowed))" \
  "return Double(gasUsed) / Double(allowed)"
mutate "an unread receipt read as nothing spent" \
  "$FIG" "guard let gasUsed, let allowed = allowance(frames), allowed > 0 else { return nil }" \
  "let gasUsed = gasUsed ?? 0; guard let allowed = allowance(frames), allowed > 0 else { return nil }"
mutate "Home promising a few moves and listing none again" \
  "$FIG" "static let homeMoveCap = 3" "static let homeMoveCap = 0"
mutate "the seen cap dropping the NEWEST keys instead of the oldest" \
  "$MOMENTS" "if known.count > seenCap { known.removeFirst(known.count - seenCap) }" \
  "if known.count > seenCap { known.removeLast(known.count - seenCap) }"

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
# **THE SEAT SIGNS AND SENDS SINCE prd §593d, so this guard changed shape
# rather than being retired.** It used to assert that the whole seat was
# watch-only and that the catalog said so; both stopped being true the day the
# room got its acts. What still holds — and is worth more — is that the READ
# FILE stays a read file: `PrivacyDevnetBridge` is what every room open drives,
# on a timer, with no tap behind it, and a signing verb reaching it would mean
# the seat can act without anybody asking. The signing lives in
# `PrivacyDevnetSend`, which the room calls from a button and nowhere else.
for verb in 'eth_sendRawTransaction' 'eth_sendTransaction' 'eth_sign' 'personal_sign' \
            'eth_signTransaction' 'postJSONBody' 'PrivacyDevnetSend' 'PrivacyDevnetKey' \
            'SecItemAdd' 'secp256k1' 'signingPreimage'; do
  grep -qF -- "$verb" "$work/bridge.bare" \
    && fail "PrivacyDevnetBridge names $verb — the sweep runs on a timer with no tap behind it, so signing must stay in PrivacyDevnetSend"
done
# **AND NEITHER MAY THE SEAT'S OWN CARD (prd §602).** The guard below has
# checked the CATALOG's promise since §593d and the connected card's `can:`
# line was never checked at all — so the app went on telling anybody who opened
# the seat that it "makes no key, signs nothing and sends nothing" for eight
# builds after it started doing all three. Both halves are guarded now, which
# is what `registerBridge`'s own comment always said the rule was.
grep -qF 'it makes no key, signs nothing and sends nothing' "$BRIDGE" \
  && fail "the seat's connected card still promises it never signs, and it has signed and sent since §593d — the promise and the acts retire together, never one without the other"
grep -qF 'Sending signs with a key held on this device' "$BRIDGE" \
  || fail "the seat's card stopped saying where the signing key lives — that clause is what somebody reads while deciding whether a privacy devnet is safe to try"

# And the catalog must no longer make the promise the seat has outgrown.
grep -qF 'Watching only — nothing is signed and nothing is sent' \
  "Casberi/Casberi/Model/BridgeCatalog.swift" \
  && fail "the catalog still promises this seat only watches, and it now signs and sends (§593d) — a promise the app has outgrown is §83 pointed at ourselves"

# THE FAUCET HOST IS DISCLOSED (§531's lesson, one seat over, where a faucet the
# app really posted to sat in the reach audit's denylist for a day and the
# privacy screen omitted it).
grep -qF 'faucet.privacy.ethrex.xyz' "Casberi/Casberi/Model/NetworkReach.swift" \
  || fail "faucet.privacy.ethrex.xyz is not in the reach registry, and the seat now posts to it"

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
# **THE TWO ONCE-FABRICATED VALUES ARE NOW REAL ON ACCOUNT `b` (prd §593d).**
# They were called fabricated because they appear on NEITHER of account `a`'s
# transactions. They ARE byte-real on the second pool participant's — blocks
# 2787/2792 — and the §593d demo seeds that account, so they live here now,
# correctly attributed. The guard flips: it fails if either reappears on `a`'s
# hashes (the misattribution it was written to catch) but must find them on
# `b`'s. `b`'s two hashes are read back off the chain the same as everything
# else here.
for v in '055b6c2720e71fbe4d5fa4ad130f4f7b68879ee7d062d0e21af30c5e8ce5839c' \
         '08cda6582e3ed667ed4b907d27093659da30882f1d1437ee86125664ecf6f9ce'; do
  grep -qF -- "$v" "$work/bridge.bare" \
    || fail "a once-fabricated nullifier vanished ($v) — it belongs on account b's real transactions now (§593d)"
done
grep -qF '0x5ad114d29ed7e9326bbc300b951c6ee9a59c648985dbba9497dfea454cccaa4a' "$work/bridge.bare" \
  || fail "account b's block-2787 transaction hash is gone — the two once-fabricated keys ride it"
grep -qF '0xb17e6a8292d3ed1f559d7e78f85b62fad2962b589e51ce90eb6462440b6d2a66' "$work/bridge.bare" \
  || fail "account b's block-2792 transaction hash is gone"

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

# ── prd §593d: the room split, the acts, the notification ─────────────
CARD="Casberi/Casberi/Screens/PrivacyDevnetRoomCard.swift"
strip_comments "$CARD" > "$work/card.bare"

# **THE LIST LIVES OUTSIDE THE CLIPPED SLOT.** `DSRoomSlot` is a hard 300pt box
# that clips, and this card drew the figure AND the scope's rows inside it — so
# everything past the third or fourth row was cut off the bottom with no scroll
# and no sign it had been. Reported as the lists not showing at all. The fix is
# `FramesRoomList`'s split, one seat over, and putting the rows back inside the
# box would look like an ordinary tidy-up.
grep -qF 'struct PrivacyDevnetRoomList' "$work/card.bare"   || fail "PrivacyDevnetRoomList is gone — the rows would be back inside DSRoomSlot's 300pt box, which clips them away with no scroll"
# The card's `content` — everything DSRoomSlot's 300pt box draws — must reach
# the figure and never the rows.
python3 - "$work/card.bare" <<'PY2' || fail "the card's slot content draws a scope list again — DSRoomSlot clips at 300pt, so the rows vanish with no scroll"
import sys, io, re
s = io.open(sys.argv[1], encoding="utf-8").read()
i = s.index("private var content: some View {")
j = s.index("\n    }\n", i)
body = s[i:j]
if "scopeList" in body or "withFigure" in body: sys.exit(1)
if "figure(for: section)" not in body: sys.exit(1)
sys.exit(0)
PY2

# **THE ACTS ARE ON HOME AND ONLY ON HOME** (§594's line: an act that WRITES to
# the chain moves to Home; an act that changes what you are LOOKING AT stays
# with the view). A send panel repeated under every scope is one control four
# times.
grep -qF 'if section == .home, let onSend' "$work/card.bare"   || fail "the send panel is no longer scoped to Home — repeated under every scope it is the same control four times (§594)"

# The connect screen keeps the WATCH and hands the writes to the room.
grep -qE 'PrivacyDevnetSend|PrivacyDevnetKey'   "Casberi/Casberi/Screens/PrivacyDevnetScreen.swift"   && fail "an act that writes to the chain came back to the connect screen — §594 puts those on Home, and a door in both places makes three places"

# **THE RELAUNCH REACHES THE LOCK SCREEN (§593d).** §593's ruling that this seat
# raises no notification was about the ROOT WINDOW — a deadline nobody can act
# on — and that ban is still enforced against `PrivacyDevnetRoots` above. A
# relaunch is the opposite: it is the one fact that makes every reading in the
# room describe a chain that no longer exists.
grep -qF 'case vibenet, hegota, privacy' "Casberi/Casberi/Model/NotifyPlan.swift"   || fail "the Privacy seat left NotifyDevnet — a relaunch would again be discoverable only by opening the room (§522's report)"
grep -qF 'out.append(.init(seat: .privacy, key: seen.key, observedAt: seen.at,' "Casberi/Casberi/Model/DevnetNotify.swift"   || fail "nothing gathers the Privacy relaunch into resets(), so its NotifyDevnet seat can never fire"
grep -qF 'nonisolated static func observedRelaunch()'   "Casberi/Casberi/Model/PrivacyDevnetBridge.swift"   || fail "the relaunch is no longer recorded across launches — an in-memory genesis cannot be read by a notify sweep"

# **ONE SPELLING OF A BALANCE.** The rail carried a private copy of this
# arithmetic and the send sheet needed the same sentence.
grep -qF 'PrivacyDevnetMoney.line' "Casberi/Casberi/Shell/FaceScopeRail.swift"   || fail "the face rail formats a Privacy balance itself again — two formatters of one number is how a rail and a form disagree about what an account holds"

# **THE WALK SAYS WHAT IT DID NOT READ (§307, §309).** A truncated room and a
# complete one look identical from outside.
grep -qF 'cut.unread = max(0, ranked.count - Self.walkCap)' "$work/bridge.bare"   || fail "the walk no longer counts what the cap dropped — a truncated room reads as a quiet one"
grep -qF 'walkCeiling' "$work/card.bare"   || fail "the Activity list stopped stating the walk's ceiling — a room found by following logs must say so"

# ── prd §596: rows are doors, headlines are counts, figures fill the slot ──

# **EVERY MOVE ROW OPENS ITS SHEET.** The rows shipped as `WalletRow`'s
# deliberately-terminal form (reported: "none of the lists open thing sheets")
# — and the moment they became Buttons, an empty closure would be Frames' own
# 2026-09-02 defect ("rows wired to nothing"), a dead control per transaction.
grep -qF 'onOpenMove(move, owner)' "$work/card.bare" \
  || fail "the move rows no longer open their sheet — a row that highlights and does nothing is §83's dead control per transaction (prd §596)"
grep -qF 'case .privacyDevnetMove(let move, let owner):' "Casberi/Casberi/Screens/FeedScreen.swift" \
  || fail "FeedScreen no longer dispatches .privacyDevnetMove — every row's tap goes nowhere (prd §596)"
grep -qF 'struct PrivacyDevnetMoveSheet' "Casberi/Casberi/Screens/PrivacyDevnetSheets.swift" \
  || fail "PrivacyDevnetMoveSheet is gone — the rows' route opens nothing (prd §596)"

# **THE SCOPE HEADLINE IS A COUNT DRAWN BY THE CHASSIS, NEVER THE SUMMARY
# SENTENCE OVER THE CHART** (reported: "Charts have sentences over them").
grep -qF 'DSRoomSlot(headline: slotHeadline' "$work/card.bare" \
  || fail "the card stopped handing its headline to the chassis — the scope line drifts back into the slot, over the figure (prd §596)"
grep -qF 'section.summary' "$work/card.bare" \
  && fail "the summary sentence is back on the card — a sentence standing on a chart is the jam §596 removed; the chassis headline carries a COUNT"

# **THE 84pt FIGURE CEILING MUST NOT RETURN.** Every figure was pinned to an
# 84pt band centred in the 300pt slot — the "tiny and top justified" defect
# §588 fixed on Frames — and restoring a shared height constant would look
# like an ordinary tidy-up.
grep -qF 'figureHeight' "$work/card.bare" \
  && fail "a shared figure height constant is back — the figures must fill DSRoomChassis.figureSlot, not centre an 84pt band in it (prd §596)"
grep -qF '.padding(.trailing, DSRoomChassis.gearColumn)' "$work/card.bare" \
  || fail "the drawings no longer end at the gear's x — Frames' rule, or every chart runs under the settings cog (prd §596)"

# **THE WALK READS THE FRAME'S OWN FIELDS OFF THE PAYLOAD IT ALREADY HAS.**
# Mode/target/value cost zero requests; dropping the reads makes every step in
# the move sheet a budget with no verb, silently.
grep -qF 'target: f["to"] as? String' "$work/bridge.bare" \
  || fail "the walk stopped reading a frame's target — the move sheet's steps lose their addresses with no error anywhere (prd §596)"

# This harness must stay in verify.sh's hand list (that guard fails the build
# until it is named WITH its reason, which is the part that gets skipped).
grep -q "privacy-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

# ── prd §598: the chips, the ring, the components, the moments ────────
CARD="Casberi/Casberi/Screens/PrivacyDevnetRoomCard.swift"
FIGV="Casberi/Casberi/Screens/PrivacyDevnetFigures.swift"
SHEETS="Casberi/Casberi/Screens/PrivacyDevnetSheets.swift"
for f in "$CARD" "$FIGV" "$SHEETS"; do [[ -f "$f" ]] || fail "$f not found"; done
strip_comments "$CARD" > "$work/card.bare"
strip_comments "$FIGV" > "$work/figv.bare"
strip_comments "$SHEETS" > "$work/sheets.bare"

# **THE CHIPS WEAR THE PLAIN WORDS.** The room taught "spend keys" and
# "snapshots" in the lede, every headline, every meta line, both sheets and
# both accessibility labels — and said "Nullifiers" and "Roots" in the one
# place a person meets the strip FIRST. Renaming them back would look like a
# tidy-up toward the mechanism's real name.
grep -qF 'case .nullifiers: return String(localized: "Spend keys")' "$SECTION"   || fail "the Nullifiers chip lost its plain words — the strip is the room's table of contents, not its glossary"
grep -qF 'case .roots:      return String(localized: "Snapshots")' "$SECTION"   || fail "the Roots chip lost its plain words"
# The RAW VALUES must not move with the labels: they are the persisted pick and
# the deep link's own word, so renaming a case silently resets every stored
# scope and breaks a saved link.
grep -qE '^\s+case nullifiers$' "$SECTION"   || fail "the nullifiers CASE was renamed — the raw value is the persisted scope and a deep link's word"
grep -qE '^\s+case roots$' "$SECTION"   || fail "the roots CASE was renamed — same reason"

# **THE TRACK IS GONE AND MUST NOT COME BACK.** The straight bar needed a
# caption at each end to say which way time ran, printed once on Home and again
# under every lane in the Snapshots scope; the arc's gap says it with nothing to
# read. Restoring either would look like an ordinary revert.
grep -qF 'PrivacyDevnetTrack' "$work/card.bare" \
  && fail "the straight track is back in the room — the ring replaced it, and its duplicated axis caption with it"
grep -qF 'struct PrivacyDevnetTrack' "$work/figv.bare" \
  && fail "the straight track view is back — one drawing of the window, and it is a ring"
grep -qF 'leaves the chain'"'"'s memory' "$work/card.bare" \
  && fail "the axis caption is back — the exit gap is what carries it now, and it was printed twice"
grep -qF 'PrivacyDevnetRing' "$work/card.bare" \
  || fail "the room stopped drawing the ring at all"

# **THE RING IS ALIVE, AND ITS DRIFT IS THE MODEL'S.** A view that recomputed
# a position itself would put the clamp — the whole safety argument — outside
# anything a harness can prove.
grep -qF 'TimelineView' "$work/figv.bare" \
  || fail "the ring stopped ticking — a window that only moves on a sweep is a clock that ticks twice an hour"
grep -qF 'PrivacyDevnetFigure.drifted' "$work/figv.bare" \
  || fail "the ring drifts by its own arithmetic — the clamp that stops an estimate aging a proof out lives in the model"

# **THE SEAL IS ONCE, AND ONLY FOR A KEY THIS DEVICE HAS NEVER SEEN.** Sealing
# every ring on every open is a room celebrating its own contents, and on an
# install'"'"'s first read it would seal forty at once.
grep -qF 'PrivacyDevnetMoments.unseen' "$work/card.bare" \
  || fail "the spend keys stopped asking which are new — every ring would seal on every open"
grep -qF 'PrivacyDevnetMoments.hasSeenAnyKey' "$work/card.bare" \
  || fail "the first-read seed is gone — somebody arriving would watch forty rings seal at once"

# **THE SWEEP IS TOLD THIS PHONE'"'"'S ADDRESS, NEVER LOOKS IT UP.** The guard
# above bans `PrivacyDevnetKey` from the bridge outright; this is the other
# half, so the moment cannot be restored by weakening that ban.
grep -qF 'PrivacyDevnetLiveState.shared.setMine' "$work/card.bare" \
  || fail "nothing publishes this phone'"'"'s address, so the first-transaction moment can never fire"

# **THE SHEETS USE THE APP'"'"'S OWN COMPONENTS.** Frames'"'"' sheets, one chip
# away, use `DSSpecRow` ten times and `DSStamp` six; this seat used neither and
# hand-rolled both — which is exactly how `DSSpecRow` came to be written three
# times at three column widths in the first place.
grep -qF 'DSSpecTable' "$work/sheets.bare" \
  || fail "the move sheet hand-rolls its facts again — DSSpecRow exists because that shape was written three times at three widths"
grep -qF 'DSStamp' "$work/sheets.bare" \
  || fail "the sheet hand-places its state word again — DSStamp exists because that word was drawn twice at two weights"
grep -qF 'WalletRow(' "$work/sheets.bare" \
  || fail "the sheet's key and snapshot rows left the app's one row shape"
# ONE hex shortener for the seat. It was written twice at two elision lengths,
# so a key and the transaction that spent it were cut differently on one sheet.
[[ "$(grep -c 'prefix(8) + "…"' "$work/sheets.bare" "$work/card.bare" | awk -F: '{t+=$2} END {print t}')" == "1" ]] \
  || fail "the seat has more than one hex shortener again — a key and its transaction were once elided differently on the same sheet"

# **THE SET WEARS AN ORDINAL, NOT ITS BYTES.** A 32-byte source id in an 84pt
# mono column names nothing a reader can hold across a figure, a row and a sheet.
grep -qF 'PrivacyDevnetRoots.setLabel' "$work/card.bare" \
  || fail "the snapshot rows stopped naming their set — the ring'"'"'s ordinals then point at nothing"
grep -qF 'PrivacyDevnetRoots.setLabel' "$work/sheets.bare" \
  || fail "the move sheet stopped naming the set, so the identity dies between the room and the sheet"

# **THE LEDE STATES THE STATE; THE RING STATES THE CLOCK.** The sentence carried
# both, and the second in a unit nobody outside this devnet can size.
# Read from a COMMENT-STRIPPED copy — the source documents this rule by
# QUOTING the sentence it replaced, so a guard over raw text fires on the prose
# explaining it. That is the Obsidian/Cursor lesson, and it caught this guard on
# its own first run.
strip_comments "$ROOM" > "$work/room.bare"
grep -qF 'for another' "$work/room.bare" \
  && fail "the head sentence is counting slots again — the ring carries the clock, in words, with the measured count beneath it"

# ── prd §602: the ceiling once, the moves back, the key's own account ──

# **THE STANDING CEILING IS SAID ONCE.** All three sentences printed under
# every list that drew rows — Activity, Frames and Sponsors — so the room's own
# explanation of itself appeared three times on one screen in its quietest ink.
# The two CUTS stay with the rows they truncated (they are what happened on
# this pass); the FLOOR moved to Home (it is how the room works, forever).
grep -qF 'walkFloor' "$work/card.bare" \
  || fail "the walk's standing ceiling is gone entirely — every count in this room is a floor and nothing says so"
python3 - "$CARD" <<'PYX' || exit 1
import re, sys
src = re.sub(r'//.*', '', open(sys.argv[1], encoding="utf-8").read())
# The sentence must appear in exactly ONE view, and that view must be the one
# Home draws — not in `list(...)`, which three scopes reach.
body = src[src.index('var walkCeiling'):src.index('var walkFloor')]
if "logs, so a transaction that emitted none" in body:
    print("  ✗ the standing floor is back inside walkCeiling, which three scopes draw")
    sys.exit(1)
print("  ✓ the standing ceiling is said once, on Home")
PYX

# **HOME LISTS ITS MOVES AGAIN.** The scope's summary promises "the last few
# moves" and it showed none whenever a proof was live, which is whenever the
# room has anything to say.
grep -qF 'case .home:       list(Array(pairs.prefix(homeMoveCount))' "$work/card.bare" \
  || fail "Home stopped listing its moves — its own summary promises them, and drawing none is the §83 gap that ruling created"
# And they must NOT come back inside the clipped slot, which is what cut a row
# mid-line on a device twice.
grep -qF 'ForEach(pairs.prefix(homeMoveCount)' "$work/card.bare" \
  && fail "Home's moves are back inside DSRoomSlot's 300pt box — that box clips, and it cut a row mid-line twice"

# **THE KEY'S OWN ACCOUNT IS WATCHED AND NAMED.** Creating a key did not watch
# its address, so the balance you had just claimed appeared nowhere in the room
# that made the account.
SEND="Casberi/Casberi/Screens/PrivacyDevnetSendCard.swift"
[[ -f "$SEND" ]] || fail "$SEND not found"
strip_comments "$SEND" > "$work/send.bare"
grep -qF 'PrivacyDevnetWatch.shared.add(made)' "$work/send.bare" \
  || fail "making a key no longer watches its address — every reading in this room is per watched address, so the account the app just made would have no face, no row and no balance"
grep -qF 'This phone' "$work/sheets.bare" \
  || fail "this phone's own account lost its name — it is watched now, so without it the room shows the account it created as a stranger's hex"

# **THE SPEND IS DRAWN AND STATED, off a receipt already fetched.**
grep -qF 'usedShare: PrivacyDevnetFigure.usedShare' "$work/card.bare" \
  || fail "the Frames scope stopped drawing what was spent — it would state every transaction's budget and no transaction's cost"
grep -qF 'gasUsed: moveGasUsed' "$work/bridge.bare" \
  || fail "the walk stopped keeping the receipt's own total — a number already in memory, thrown away"
# It must stay TRANSACTION level: no per-frame breakdown exists on this chain,
# so a weighted or failed segment off a usage figure would be invented.
grep -qE 'gasUsed: PrivacyDevnetRPC|gasUsed: PF?\.?hexInt\(f\[' "$work/bridge.bare" \
  && fail "a per-frame gasUsed is being read — this chain serves none (§593a), so any figure built on it is invented"

print "  ok   drift guards: no price, no notification, slots not blocks, no coins scope, the ring, the components, the moments"
# **COUNTED, NOT CLAIMED (prd §602).** This line carried "38 mutations, 25
# drift guards" while the file held 59 and 83 — a hardcoded tally that nobody
# updates and that therefore understates the suite by more every pass, which is
# a summary saying something false about the very thing it summarises.
print "✓ privacy: 7 scopes, the 8272 window, the room head, the figures, the roots' own storage, the §596 sheets and §602's readings, $(grep -c '^mutate ' "$0") mutations, $(grep -c 'fail \"' "$0") drift guards"
