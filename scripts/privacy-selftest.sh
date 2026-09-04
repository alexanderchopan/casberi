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
VERIFY="scripts/verify.sh"
for f in "$SECTION" "$ROOTS"; do [[ -f "$f" ]] || fail "$f not found"; done

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

check(!PrivacyDevnetRoots.present([]), "no references means no roots scope")
check(PrivacyDevnetRoots.present(refs), "references mean the scope draws")

if failures == 0 { print("  ok   \(0) failures") } else { exit(1) }
SWIFT

print "  building…"
xcrun swiftc -Onone -o "$work/pv" "$SECTION" "$ROOTS" "$work/main.swift" 2>"$work/build.log" \
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
  local target="$dir/$(basename $file)"
  grep -qF -- "$from" "$target" || fail "mutation '$name' matches nothing — it is stale and tests the shipped code"
  python3 - "$target" "$from" "$to" <<'PY'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if xcrun swiftc -Onone -o "$dir/pv" "$dir/PrivacyDevnetSection.swift" "$dir/PrivacyDevnetRoots.swift" \
        "$work/main.swift" 2>/dev/null && "$dir/pv" >/dev/null 2>&1; then
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
for verb in 'eth_sendRawTransaction' 'eth_sendTransaction' 'eth_sign' 'personal_sign' \
            'httpMethod' 'postJSON' 'PrivacySend' 'PrivacyKey' 'SecItemAdd'; do
  grep -qF -- "$verb" "$work/bridge.bare" \
    && fail "PrivacyDevnetBridge names $verb — the seat is watch-only until the envelope is reproduced (§593a); retire this guard and the catalog bullet in the same commit"
done
# And the copy must keep SAYING it, or the guard protects a promise nobody made.
grep -qF 'Watching only — nothing is signed and nothing is sent' \
  "Casberi/Casberi/Model/BridgeCatalog.swift" \
  || fail "the catalog no longer says this seat only watches, but nothing here signs — restore the bullet or land the write with it"

# THE COINS BAN, mechanically. A `coins` case added later compiles fine.
grep -qE "case +coins" "$work/section.bare" \
  && fail "a coins scope reappeared — the UTXO vault has no code on 8141, so the chip could never light"

# This harness must stay in verify.sh's hand list (that guard fails the build
# until it is named WITH its reason, which is the part that gets skipped).
grep -q "privacy-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

print "  ok   drift guards: no price, no notification, slots not blocks, no coins scope"
print "✓ privacy: 7 scopes, the 8272 window, boundaries, grouping, 11 mutations, 6 drift guards"
