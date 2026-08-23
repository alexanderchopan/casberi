#!/bin/zsh
# Casberi address-spine self-test — the SHIPPED derivation behind the address
# card's one dated spine (prd §446, 2026-08-22):
#
#   Casberi/Casberi/Model/AddressSpine.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Every failure here renders as a perfectly ordinary card, on the
# screen where you decide whether to trust somebody:
#
#   · a fold saying "9 more" over a preview that hid eight, so the door beside
#     it promises a screen with a different number on it
#   · the fold's span read off the SHOWN rows rather than the hidden ones —
#     which reprints the two dates already on screen and says nothing about how
#     far back you two go, the one reading the fold exists for
#   · a root dating an address to the day you opened its card, because the
#     entry was invented for the trip and was never in your book (§295's
#     connections nodes became doors, so this is the ordinary case, not a
#     corner)
#   · a root telling you that you named an address that is still standing under
#     a placeholder the app minted
#   · an address chunked so that a character is dropped or a group is padded —
#     on the ONE screen where a wrong character is a different address, and the
#     one whose whole argument is that it shows every character the truncated
#     capsule hid
#   · a month rendered in the system zone while the year that CHOSE the format
#     was compared in the calendar's, so an instant at midnight UTC on January
#     1st prints last year's month as though it were this one (the bug
#     `AddressBookShape.lastPhrase`'s own harness found at exactly this
#     boundary — the same trap, in a second file)
#   · an unpriceable grant dropped out of the caption, leaving a figure that
#     looks complete over a permission it does not cover
#   · the reveal running middle-first, which inverts the whole reading the
#     ends-first order exists to teach
#
# Nothing in a build, a screen sweep or any static audit can see one of these.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SPINE="Casberi/Casberi/Model/AddressSpine.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
REVEAL="Casberi/Casberi/Screens/AddressReveal.swift"
for f in "$SPINE" "$VIEWS" "$REVEAL"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. All three files DOCUMENT
# what they must never do — `AddressSpine`'s header names the truncated capsule
# it replaced, and the card's header names every block it collapsed — so a
# guard grepping raw source fires against the prose explaining it (the
# Obsidian/Cursor lesson, earned on several harnesses' own first runs).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*///?.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$VIEWS"  > "$TMP/views-bare.swift"
strip_comments "$SPINE"  > "$TMP/spine-bare.swift"
strip_comments "$REVEAL" > "$TMP/reveal-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect derivation is
# worthless if the card never calls it, draws it twice, or walks the corpus
# once per reader to feed it.

grep -q 'AddressSpine.events(standing: standing(),' "$VIEWS" \
  || { echo "✗ the card no longer assembles its spine through AddressSpine.events — the ordering would be the view's own and nothing could test it"; exit 1; }
grep -q 'spine(things)' "$VIEWS" \
  || { echo "✗ the card body no longer draws the spine"; exit 1; }

# §8 HAS NO ALL-CAPS EYEBROW, and this spine wore one on every event until
# 2026-08-22: `eyebrow` ran every day stamp through `localizedUppercase`, so it
# printed TODAY — and its own doc argued an exemption ("only a date stamp,
# three characters of month and a number") that was false for the two commonest
# inputs `dayText` returns. It also set the house style beside it, which is how
# `FIRST` and `STANDING · NOW` came to be written in caps.
#
# The six root fixtures below pin the resulting CASE, so re-adding the
# uppercasing fails them by name. These two guard the spelling directly,
# because a caller can shout without touching `eyebrow` at all. Read from the
# comment-stripped copies: both files now DOCUMENT this rule by naming the API
# and the literals it bans (the Obsidian/Cursor lesson).
grep -q 'localizedUppercase' "$TMP/spine-bare.swift" \
  && { echo "✗ the spine is upper-casing its eyebrows again — §8 has no ALL-CAPS eyebrow, and the carve-out that allowed this was measured wrong"; exit 1; }
grep -qE '"(STANDING · NOW|FIRST)"' "$TMP/views-bare.swift" "$TMP/spine-bare.swift" \
  && { echo "✗ an ALL-CAPS eyebrow literal is back beside the day stamps (§8)"; exit 1; }

# THE FOUR BLOCKS THE SPINE REPLACED MUST STAY GONE (prd §446). Each was a
# separate treatment of one shape — a dated fact about this address — and any
# one of them returning beside the spine states the same fact twice, in two
# voices, on one screen.
for gone in 'private func lede(' 'private func exposureLede(' \
            'private func relationshipLede(' 'private func reachedWallets(' \
            'private func historySection(' 'private var detailsList'; do
  if grep -qF -- "$gone" "$TMP/views-bare.swift"; then
    echo "✗ \`$gone\` is back beside the spine — the card would state one fact in two treatments again (§446)"; exit 1
  fi
done

# ONE FETCH PER BODY PASS (§444). `history` walks the corpus; the spine has
# more readers than the old card did, and letting it become three walks is the
# §441 cost arriving a third time.
python3 - "$TMP/views-bare.swift" <<'PY2'
import re, sys
src = open(sys.argv[1]).read()
card = src[src.index("struct AddressCard: View {"):]
card = card[:card.index("\nstruct ")] if "\nstruct " in card else card
uses = len(re.findall(r'(?<!func )\bhistory\b(?!\()', card))
# One declaration (`private var history`), one read (`let things = history`).
if uses > 2:
    sys.stderr.write("✗ the card reads `history` %d times — one corpus walk per body pass (§444)\n" % uses); sys.exit(1)
PY2

# THE LOOK-ALIKE CONDITION STILL HAS ITS HOME, above the spine. It is a
# full-width CONDITION of the screen rather than a card in the stack, and the
# spine redesign explicitly did not take it.
grep -q 'lookalikeBand' "$VIEWS" \
  || { echo "✗ the look-alike band is gone — the poisoning warning is the one thing on this sheet that cannot be a widget in a list (§444)"; exit 1; }
python3 - "$TMP/views-bare.swift" <<'PY3'
import sys
src = open(sys.argv[1]).read()
try:
    band = src.index("lookalikeBand\n")
    spine = src.index("spine(things)")
except ValueError:
    sys.stderr.write("✗ the card body no longer stacks lookalikeBand then spine\n"); sys.exit(1)
if band > spine:
    sys.stderr.write("✗ the look-alike band draws BELOW the spine — a security condition under the history it warns about\n"); sys.exit(1)
PY3

# THE §374 GATE IS AT THE CALL SITE, never inside the Foundation-only model —
# the same reason `AddressHistoryRow` takes `hidden`/`mask` as parameters.
grep -q 'WalletValue.exactMoney(exposure.total)' "$VIEWS" \
  || { echo "✗ the standing figure no longer routes through WalletValue.exactMoney — the §374 gate would be off the one dollar figure on this screen"; exit 1; }
for leak in 'BalancePrivacy' 'TokenStats.compact' 'WalletValue'; do
  if grep -qF -- "$leak" "$TMP/spine-bare.swift"; then
    echo "✗ AddressSpine reaches for $leak — the money gate must stay at the call site where hide-balances-audit.py can see it"; exit 1
  fi
done

# NEVER 0 FOR UNKNOWN. The figure is withheld when nothing could be priced;
# `$0.00` over unpriceable grants is the fake status §83 bans, on the screen
# where believing it is most expensive.
grep -q 'exposure.priced.isEmpty ? nil : WalletValue.exactMoney(exposure.total)' "$VIEWS" \
  || { echo "✗ the standing figure is no longer withheld when nothing could be priced — \$0 would stand in for unknown (§83/§292)"; exit 1; }

# THE WHOLE ADDRESS, WRAPPED — never truncated. The capsule this replaced could
# not show 42 characters at 390pt, which is what made it the wrong control on
# the one screen that exists to tell two look-alike addresses apart.
grep -q 'AddressSpine.chunks(current.address)' "$VIEWS" \
  || { echo "✗ the address is no longer chunked through AddressSpine.chunks — a second chunking rule could drop a character with nothing to test it"; exit 1; }
python3 - "$TMP/views-bare.swift" <<'PY4'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'private var addressBlock:.*?\n    \}\n', src, re.S)
if not m:
    sys.stderr.write("✗ addressBlock no longer exists — the address's own view moved\n"); sys.exit(1)
body = m.group(0)
for bad in ("truncationMode", "lineLimit"):
    if bad in body:
        sys.stderr.write("✗ the address block uses %s — a hidden character on this screen is a different address (§446)\n" % bad); sys.exit(1)
PY4

# ENDS FIRST, and per CHUNK. A horizontal mask over a WRAPPING block uncovers
# the left and right of each LINE, which over two lines reveals the middle of
# the address first — the exact inversion of the reading.
grep -q 'AddressSpine.revealRank' "$TMP/reveal-bare.swift" \
  || { echo "✗ the chunk reveal no longer takes its order from AddressSpine.revealRank — the ends-first reading would be the view's own and untestable"; exit 1; }
grep -q 'accessibilityReduceMotion' "$TMP/reveal-bare.swift" \
  || { echo "✗ the chunk reveal no longer honours Reduce Motion (§299)"; exit 1; }

# THE DOOR STILL GOES SOMEWHERE, and the count beside it is the WHOLE history.
grep -q 'AddressHistoryScreen(entry: current)' "$VIEWS" \
  || { echo "✗ the fold's \"See all\" no longer pushes AddressHistoryScreen — a dead control (§83)"; exit 1; }
grep -q 'Text("See all \\(total)")' "$VIEWS" \
  || { echo "✗ \"See all\" no longer states the spine's own total — the door would promise a different number than it opens"; exit 1; }

# NO HAIRLINES (§8, zero exceptions). The rail is structural — it connects the
# dots of one sequence — and the bar separates by material alone.
python3 - "$TMP/views-bare.swift" <<'PY5'
import re, sys
src = open(sys.argv[1]).read()
card = src[src.index("struct AddressCard: View {"):]
if "Divider()" in card:
    sys.stderr.write("✗ the address card draws a Divider — §8's no-lines law has zero exceptions\n"); sys.exit(1)
m = re.search(r'private var bottomBar:.*?\n    \}\n', card, re.S)
if not m:
    sys.stderr.write("✗ bottomBar no longer exists — the pinned verb moved\n"); sys.exit(1)
# INK, not material (2026-08-22, user ruling). `.ultraThinMaterial` over a dark
# sheet renders as a lighter grey slab, so on a device the bar announced itself
# with a hard edge against the black above it — §8's no-lines law broken by a
# material rather than by a stroke. The guard is inverted rather than deleted:
# the bar must keep having NO separator, and a material coming back is exactly
# how the line would return.
if "DS.themedPage" not in m.group(0):
    sys.stderr.write("\u2717 the verb bar no longer paints the page's own ink \u2014 it drew a grey edge against the sheet\n"); sys.exit(1)
if "Material" in m.group(0):
    sys.stderr.write("\u2717 the verb bar is back on a material \u2014 that is the grey hard line \u00a78 forbids, wearing a blur\n"); sys.exit(1)
PY5

# THE UNNAMED CARD'S VERB. Naming is the act this screen exists for and the
# watch list is capped at five, so an unnamed address's bar names it — and
# watching moves to the menu rather than disappearing (§83: no verb is lost).
grep -q 'Name this address' "$VIEWS" \
  || { echo "✗ the unnamed card no longer offers to name the address (§446)"; exit 1; }
grep -q 'if unnamed, watchPillShown { watchMenuItem }' "$VIEWS" \
  || { echo "✗ watching did not move to the overflow menu on the unnamed card — the verb the bar gave up would simply be gone (§83)"; exit 1; }

# --- fixtures ---------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ got: String, _ want: String) {
    if got != want {
        FileHandle.standardError.write("FAIL \(label): got [\(got)] want [\(want)]\n".data(using: .utf8)!)
        failures += 1
    }
}
func check(_ label: String, _ got: Int, _ want: Int) {
    check(label, String(got), String(want))
}
func check(_ label: String, _ got: Bool, _ want: Bool) {
    check(label, String(got), String(want))
}

// A fixed clock and a fixed zone: every date phrase below is compared against
// a literal, and a harness that drifts with the machine's calendar is one that
// fails on a plane.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
cal.locale = Locale(identifier: "en_US_POSIX")
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
let now = day(2026, 8, 22)

func t(_ n: Int, _ date: Date, lead: String = "Received",
       amount: String? = "1 ETH", wallet: String? = nil) -> AddressSpine.Transfer {
    AddressSpine.Transfer(id: "t\(n)", date: date, lead: lead,
                          amount: amount, walletName: wallet, cascadeStep: n)
}
func kinds(_ events: [AddressSpine.Event]) -> String {
    events.map { e -> String in
        switch e {
        case .standing: return "S"
        case .transfer: return "T"
        case .fold:     return "F"
        case .root:     return "R"
        }
    }.joined()
}
func foldText(_ events: [AddressSpine.Event]) -> String {
    for case .fold(let line, _) in events { return line }
    return "nil"
}
func foldTotal(_ events: [AddressSpine.Event]) -> Int {
    for case .fold(_, let total) in events { return total }
    return -1
}
func rootText(_ events: [AddressSpine.Event]) -> String {
    for case .root(let eyebrow, let sentence) in events { return eyebrow + " | " + sentence }
    return "nil"
}

// ── The preview is three, and the fold describes what it HID ──────────────
let twelve = (0..<12).map { t($0, day(2026, 8, 20 - $0)) }
let full = AddressSpine.events(standing: AddressSpine.Standing(figure: "$8,924.10",
                                                               caption: "Unlimited USDC."),
                               transfers: twelve, total: 12,
                               root: .named(at: day(2026, 3, 3), provenance: nil),
                               now: now, calendar: cal)
check("full spine order", kinds(full), "STTTFR")
check("preview is three", AddressSpine.preview, 3)
check("fold counts the hidden", foldText(full), "9 more, Aug")
check("fold door states the whole history", foldTotal(full), 12)

// The fold's SPAN comes off the hidden rows. A run that ends in a different
// month from the preview is the case that separates the two readings — read
// off the shown rows this would say "Aug – Aug" and describe nothing.
let spanning = [t(0, day(2026, 8, 18)), t(1, day(2026, 8, 2)), t(2, day(2026, 7, 30))]
    + (0..<9).map { t(10 + $0, day(2026, 7, 20 - $0)) }
    + [t(30, day(2026, 3, 4))]
let spanEvents = AddressSpine.events(standing: nil, transfers: spanning,
                                     total: spanning.count, root: .none,
                                     now: now, calendar: cal)
check("fold spans the hidden run", foldText(spanEvents), "10 more, Jul – Mar")

// One month across the whole hidden run is one fact, not a range.
let oneMonth = (0..<6).map { t($0, day(2026, 6, 20 - $0)) }
check("fold single month",
      AddressSpine.foldLine(hidden: Array(oneMonth.dropFirst(3)), now: now, calendar: cal),
      "3 more, Jun")

// Across a year boundary the year appears on BOTH ends — "Jul – Mar" reads as
// seven months when it is nineteen.
let crossYear = [t(0, day(2026, 7, 4)), t(1, day(2024, 12, 1))]
check("fold crosses a year",
      AddressSpine.foldLine(hidden: crossYear, now: now, calendar: cal),
      "2 more, Jul 2026 – Dec 2024")

// ── No fold below the preview, and none AT the preview ────────────────────
let three = (0..<3).map { t($0, day(2026, 8, 20 - $0)) }
check("no fold at exactly the preview",
      kinds(AddressSpine.events(standing: nil, transfers: three, total: 3,
                                root: .none, now: now, calendar: cal)), "TTT")
check("no fold below the preview",
      kinds(AddressSpine.events(standing: nil, transfers: Array(three.prefix(1)),
                                total: 1, root: .none, now: now, calendar: cal)), "T")
check("fold at preview + 1",
      kinds(AddressSpine.events(standing: nil, transfers: (0..<4).map { t($0, day(2026, 8, 20 - $0)) },
                                total: 4, root: .none, now: now, calendar: cal)), "TTTF")

// The preview does NOT widen when the standing event is absent — a preview
// whose length changes with an unrelated condition makes "See all 12" mean two
// different amounts of hidden history on two cards.
check("preview is the same with and without a standing event",
      kinds(AddressSpine.events(standing: nil, transfers: twelve, total: 12,
                                root: .none, now: now, calendar: cal)), "TTTF")

// ── An absent exposure draws NOTHING, never a "you're safe" panel ─────────
check("no standing event when there is no exposure",
      kinds(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                root: .none, now: now, calendar: cal)), "")

// §8 bans the ALL-CAPS eyebrow, and `eyebrow` used to run every stamp through
// `localizedUppercase` — which printed TODAY, and set the house style that put
// `FIRST` and `STANDING · NOW` in caps beside it. The six root fixtures below
// pin the case, so re-adding the uppercasing fails them; this guards the
// source directly as well, since a caller could re-add it one level up.
// ── The root, and the four things it must not claim ───────────────────────
check("named root",
      rootText(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                   root: .named(at: day(2026, 3, 3), provenance: nil),
                                   now: now, calendar: cal)),
      "Mar 3 | You named this address")
check("named root with provenance",
      rootText(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                   root: .named(at: day(2026, 3, 3),
                                                provenance: "Farcaster · @jesse"),
                                   now: now, calendar: cal)),
      "Mar 3 | You added this from Farcaster · @jesse and named it")
// An empty provenance string is an absent one, not a sentence with a hole.
check("named root with empty provenance",
      rootText(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                   root: .named(at: day(2026, 3, 3), provenance: ""),
                                   now: now, calendar: cal)),
      "Mar 3 | You named this address")
check("appeared root",
      rootText(AddressSpine.events(standing: nil, transfers: [t(0, day(2026, 8, 21))],
                                   total: 1,
                                   root: .appeared(at: day(2026, 8, 21), walletName: "Main"),
                                   now: now, calendar: cal)),
      "Yesterday · First | They appeared in a transfer to Main. You have not named them.")
// Below the two-wallet floor there is no wallet to name, and the sentence must
// not grow a hole where one would have gone.
check("appeared root with no wallet named",
      rootText(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                   root: .appeared(at: day(2026, 8, 21), walletName: nil),
                                   now: now, calendar: cal)),
      "Yesterday · First | They appeared in a transfer. You have not named them.")
// In the book, never named, and nothing to point at — it must NOT claim a
// transfer happened, and must NOT claim you named it.
check("unnamed root claims neither",
      rootText(AddressSpine.events(standing: nil, transfers: [], total: 0,
                                   root: .unnamed(at: day(2026, 8, 1)),
                                   now: now, calendar: cal)),
      "Aug 1 | You have not named this address")
// Not in the book and no history: nothing at all, rather than a root dating
// the address to the day you opened its card.
check("no root at all",
      kinds(AddressSpine.events(standing: nil, transfers: [t(0, day(2026, 8, 21))],
                                total: 1, root: .none, now: now, calendar: cal)), "T")

// The root is always LAST — it is the oldest thing known, and a spine that
// puts it anywhere else is a timeline reading in two directions.
check("root is last", full.last?.isRoot ?? false, true)
check("nothing else is root", full.dropLast().contains { $0.isRoot }, false)

// ── The event meta: the day, and which of YOUR wallets ────────────────────
check("meta with a wallet",
      AddressSpine.meta(day(2026, 8, 18), walletName: "Main", now: now, calendar: cal),
      "Aug 18 · Main")
check("meta without a wallet",
      AddressSpine.meta(day(2026, 8, 18), walletName: nil, now: now, calendar: cal),
      "Aug 18")
check("meta with an empty wallet name",
      AddressSpine.meta(day(2026, 8, 18), walletName: "", now: now, calendar: cal),
      "Aug 18")
check("meta today", AddressSpine.meta(now, walletName: "Cold", now: now, calendar: cal),
      "Today · Cold")

// ── Dates ─────────────────────────────────────────────────────────────────
check("today",     AddressSpine.dayText(now, now: now, calendar: cal), "Today")
check("yesterday", AddressSpine.dayText(day(2026, 8, 21), now: now, calendar: cal), "Yesterday")
check("this year", AddressSpine.dayText(day(2026, 3, 3), now: now, calendar: cal), "Mar 3")
check("older",     AddressSpine.dayText(day(2024, 3, 3), now: now, calendar: cal), "Mar 3, 2024")
// A future stamp is a bridge's bad timestamp — it still prints its day rather
// than being given a relative phrase that reads as nonsense.
check("future",    AddressSpine.dayText(day(2027, 1, 5), now: now, calendar: cal), "Jan 5, 2027")

// THE ZONE BOUNDARY. An instant at midnight UTC on January 1st is still
// December where this calendar lives. A formatter left on the SYSTEM zone
// renders "Jan 1" while the year comparison that chose the format said
// "different year" — the two halves disagreeing about which day it is.
// `AddressBookShape.lastPhrase`'s own harness found this at exactly this
// boundary; the same trap lives in this file.
let midnightUTC = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z
check("zone boundary", AddressSpine.dayText(midnightUTC, now: now, calendar: cal),
      "Dec 31, 2025")

// ── The standing caption ──────────────────────────────────────────────────
check("caption, priced and dated",
      AddressSpine.standingCaption([("Unlimited USDC", day(2026, 7, 29), true)],
                                   now: now, calendar: cal),
      "Unlimited USDC, granted Jul 29.")
// An unpriceable grant is STATED, never dropped — a figure that omits it looks
// complete over a permission it does not cover.
check("caption names the unpriced",
      AddressSpine.standingCaption([("Unlimited USDC", day(2026, 7, 29), true),
                                    ("2.00 WETH", nil, false)],
                                   now: now, calendar: cal),
      "Unlimited USDC, granted Jul 29. 2.00 WETH, not priced.")
// No block timestamp: the grant is named and NOT dated. §253's rule — a nil
// `grantedAt` must never be dated to today.
check("caption with no grant date",
      AddressSpine.standingCaption([("Manages all Doodles", nil, true)],
                                   now: now, calendar: cal),
      "Manages all Doodles.")
// Past the cap it counts rather than writing a paragraph at callout15.
// The overflow clause is asserted as its RAW inflection markup: this harness
// runs outside an app bundle, so `String(localized:)` has no catalog to
// resolve `^[…](inflect: true)` against and hands the markup straight back.
// Asserting the resolved English would make the fixture pass only inside the
// app — which is the one place it cannot run.
check("caption caps and counts",
      AddressSpine.standingCaption([("A", nil, true), ("B", nil, true),
                                    ("C", nil, true), ("D", nil, true),
                                    ("E", nil, true)],
                                   now: now, calendar: cal),
      "A. B. C. ^[2 more grant](inflect: true).")
check("caption cap", AddressSpine.captionCap, 3)

// ── The address, in chunks: EVERY character, and no invented ones ─────────
let evm = "0x9a2E4c81b3d7f6a05c19e8724ab3910d6f2c44b1"
let evmChunks = AddressSpine.chunks(evm)
check("evm chunk count", evmChunks.count, 10)
check("evm first chunk carries the 0x", evmChunks.first ?? "nil", "0x9a2E")
check("evm last chunk", evmChunks.last ?? "nil", "44b1")
// THE ONE THAT MATTERS: nothing is lost and nothing is invented.
check("evm round-trips", evmChunks.joined(), evm)

// Base58 has no prefix and no fixed length; its last group may be short, and
// padding it would print characters the address does not have.
// 43 characters, so the last group is SHORT — which is the case that
// separates "chunk through" from "pad to four".
let sol = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAs"
let solChunks = AddressSpine.chunks(sol)
check("solana round-trips", solChunks.joined(), sol)
check("solana takes no prefix", solChunks.first ?? "nil", "7xKX")
check("solana short tail kept", solChunks.last ?? "nil", "gAs")
check("solana chunk count", solChunks.count, 11)

// An uppercase prefix is the same prefix.
check("0X prefix", AddressSpine.chunks("0X1234abcd").first ?? "nil", "0X1234")
// Degenerate inputs still round-trip rather than returning nothing.
check("empty address", AddressSpine.chunks("").joined(), "")
check("bare prefix", AddressSpine.chunks("0x").joined(), "0x")
check("shorter than one chunk", AddressSpine.chunks("abc").joined(), "abc")

// ── Ends first ────────────────────────────────────────────────────────────
check("first chunk is rank 0",  AddressSpine.revealRank(index: 0, count: 10), 0)
check("last chunk is rank 0",   AddressSpine.revealRank(index: 9, count: 10), 0)
check("middle is the deepest",  AddressSpine.revealRank(index: 4, count: 10), 4)
check("second from each end agree",
      AddressSpine.revealRank(index: 1, count: 10),
      AddressSpine.revealRank(index: 8, count: 10))
check("single chunk", AddressSpine.revealRank(index: 0, count: 1), 0)
check("empty", AddressSpine.revealRank(index: 0, count: 0), 0)

// ── Identity is stable, so SwiftUI does not churn the spine on a re-render ─
check("ids are distinct", Set(full.map(\.id)).count, full.count)
check("transfer id carries the row", full[1].id, "t:t0")

// ── Determinism ───────────────────────────────────────────────────────────
check("stable", kinds(AddressSpine.events(standing: nil, transfers: twelve, total: 12,
                                          root: .none, now: now, calendar: cal)),
      kinds(AddressSpine.events(standing: nil, transfers: twelve, total: 12,
                                root: .none, now: now, calendar: cal)))

if failures > 0 {
    FileHandle.standardError.write("\(failures) assertion(s) failed\n".data(using: .utf8)!)
    exit(1)
}
print("  52 assertions pass")
SWIFT

echo "Compiling the shipped source WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$SPINE" "$TMP/main.swift" 2>&1 | sed 's/^/  /'
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each of these renders as a perfectly
# ordinary card.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$SPINE" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is a card that looks completely normal:"

# The fold describing the rows above it instead of the ones it hid: it reprints
# the two dates already on screen and says nothing about how far back you go.
mutate "the fold reads the shown rows" \
  'let hidden = transfers.dropFirst(preview)' \
  'let hidden = transfers.prefix(preview)'
# "9 more" over a preview that hid eight — the door beside it opening a screen
# with a different number on it.
mutate "the fold miscounts by one" \
  'let count = hidden.count' \
  'let count = hidden.count + 1'
# The door promising the preview's length rather than the whole history.
mutate "the door states the preview" \
  'total: total))' \
  'total: preview))'
# A range collapsing to one end, so a nineteen-month relationship reads as one
# month — the fold's whole reading, silently gone.
mutate "the span takes one end twice" \
  'let b = monthText(oldest, withYear: !sameYear, calendar: calendar)' \
  'let b = monthText(newest, withYear: !sameYear, calendar: calendar)'
# "Jul – Mar" across two calendar years, which reads as seven months when it is
# nineteen.
mutate "the year stops appearing across a boundary" \
  'let sameYear = calendar.component(.year, from: newest)
            == calendar.component(.year, from: oldest)' \
  'let sameYear = true'
# The standing permission at the FOOT — a timeline reading in two directions
# at once, and the one event on the spine that has to be read first buried
# under the history it outranks.
mutate "the standing permission sinks to the foot" \
  'if let standing { events.append(.standing(standing)) }' \
  'defer { if let standing { events.append(.standing(standing)) } }'
# The OLDEST three shown as the newest — a preview of a relationship's
# beginning presented as its present, which renders immaculately.
mutate "the preview takes the wrong end" \
  'let shown = Array(transfers.prefix(preview))' \
  'let shown = Array(transfers.suffix(preview))'
# An address still standing under a placeholder, told that you named it.
mutate "the unnamed root claims a name" \
  'sentence: String(localized: "You have not named this address")' \
  'sentence: String(localized: "You named this address")'
# An unpriceable grant dropped, leaving a figure that looks complete over a
# permission it does not cover.
mutate "the caption drops the unpriced" \
  'if !grant.priced { return grant.stateLine + ", " + String(localized: "not priced") }' \
  'if !grant.priced { return grant.stateLine }'
# A grant with no block timestamp dated to today (§253).
mutate "an undated grant is dated to now" \
  'guard let granted = grant.granted else { return grant.stateLine }' \
  'let granted = grant.granted ?? now'
# A character of the address gone, on the screen whose whole argument is that
# it shows every one of them.
mutate "the last short chunk is dropped" \
  'while !rest.isEmpty {' \
  'while rest.count >= size {'
# The 0x riding alone, so every group after it sits one position out of step
# with the same address printed anywhere else.
mutate "the 0x prefix is orphaned" \
  'let head = rest.prefix(2 + size)' \
  'let head = rest.prefix(2)'
# The reveal running middle-first — the exact inversion of the reading it
# exists to teach, and invisible in a screenshot.
mutate "the reveal runs middle first" \
  'return min(max(0, index), max(0, count - 1 - index))' \
  'return max(max(0, index), max(0, count - 1 - index))'
# The formatter left on the SYSTEM zone while the year that chose it was
# compared in the calendar's — last year's month printed as this one.
mutate "the date formatter loses its zone" \
  'formatter.timeZone = calendar.timeZone' \
  'formatter.timeZone = TimeZone(identifier: "UTC")'
# A preview that widens, so "See all 12" means two different amounts of hidden
# history on two cards.
mutate "the preview widens" \
  'static let preview = 3' \
  'static let preview = 5'

echo ""
echo "address-spine-selftest: OK — assertions pass and every mutation is caught."
