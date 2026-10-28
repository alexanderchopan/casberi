#!/bin/zsh
# Casberi money-receipt self-test — the SHIPPED pure judgement behind every
# money thing's sheet hero (prd §369, 2026-08-12):
#
#   Casberi/Casberi/Model/MoneyReceipt.swift
#   Casberi/Casberi/Model/MoneyCommentary.swift
#
# Both are Foundation-only BY DESIGN, so both are compiled WHOLE AND UNMODIFIED
# rather than extracted — the strongest form of "the harness ran the shipped
# logic". Everything touching `Thing`/`WalletStore`/`ModelContext` lives in
# `MoneyReceiptSource.swift`, which no harness can compile and which holds no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. This pass replaced a spec table with
# SENTENCES, and that is precisely what nothing else in the tree can check.
# `xcodebuild` is happy either way. A screen sweep photographs a fluent
# paragraph and cannot tell whether it is true. And every failure here is a
# silent wrong answer that renders beautifully:
#
#   · a received transfer wearing a minus, or a send wearing gain green
#   · a PENDING card authorization drawn with a torn edge — a claim of
#     finality made over an amount that can still change
#   · "Mostly them sending you" printed over a history that is 3–2
#   · "You usually spend about $20" because one outlier dragged a MEAN
#   · "This is the biggest yet" when it isn't
#   · a phishing domain promoted into the currency slot beside the figure,
#     because a spoofed token's "name" was treated as a ticker
#   · a Railgun unshield drawing a monogram, so a privacy guarantee reads as
#     a face we merely failed to load
#   · a deposit still in screening drawn as finished, i.e. as money you can
#     withdraw
#   · a weekday named for a date that hasn't happened yet
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RECEIPT="Casberi/Casberi/Model/MoneyReceipt.swift"
SAYS="Casberi/Casberi/Model/MoneyCommentary.swift"
# The one title seam (prd §915), Foundation-only: a price rise's title is
# its name half (prd §1357.4), read through `TitleSeam.split`, never by hand.
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
SOURCE="Casberi/Casberi/Model/MoneyReceiptSource.swift"
CARD="Casberi/Casberi/Screens/MoneyReceiptCard.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
STAGE="Casberi/Casberi/Screens/ThingStage.swift"
TOKENS="Casberi/Casberi/Design/DesignTokens.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$RECEIPT" "$SAYS" "$SEAM" "$SOURCE" "$CARD" "$SHEET" "$STAGE" "$TOKENS" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled types cannot prove about themselves. A perfect
# `compose` is worthless if the sheet never draws it, or if a `Thing` gets held
# where it can be read after a delete.

# The receipt must actually be the sheet's hero. Before this pass the gate was
# `kind == .transaction && source == "Wallet"`, which is why eleven families had
# no hero at all — if this reverts, the whole feature is invisible while every
# assertion below still passes.
grep -q 'if let moneyReceipt {' "$SHEET" \
  || { echo "✗ ThingSheetView no longer draws the money receipt as its hero"; exit 1; }
# The receipt is ONE head since prd §1394 (`MoneySheetHead`: party row, figure,
# line, state, in the lead's column); it asserts the CALL, not one spelling
# of its argument list.
grep -q 'MoneySheetHead(receipt: moneyReceipt' "$SHEET" \
  || { echo "✗ ThingSheetView's hero branch no longer builds MoneySheetHead"; exit 1; }

# --- the §369 amendment (2026-08-16) ----------------------------------------
# Four changes whose failure mode is, in every case, that the card looks
# EXACTLY as it does today. None of them can be seen by a build, a screen
# sweep, or any assertion below.

# 1. The card is ONE spoken element carrying finality. Without this the paper's
#    torn edge — the sharpest thing this card says — reaches nobody using
#    VoiceOver, and the receipt reads out as eight loose fragments.
grep -q 'accessibilityLabel(Text(receipt.spokenLabel))' "$CARD" \
  || { echo "✗ the receipt is no longer composed into one spoken label"; exit 1; }
# §1025 joins the first transfer after it, so the value may be a list that
# LEADS with `receipt.spokenValue`; finality still has to be what is spoken first.
grep -qE 'accessibilityValue\(Text\((verbatim: \[?)?receipt\.spokenValue' "$CARD" \
  || { echo "✗ finality is no longer spoken as the receipt's accessibility value"; exit 1; }
# Both strips play as Audio Graphs. A chart with no descriptor is not silent —
# it is WORSE: Swift Charts falls back to one element per mark, so a 14-bar
# history reads out as fourteen coordinate pairs.
[[ $(grep -c 'accessibilityChartDescriptor(self)' "$CARD") -eq 2 ]] \
  || { echo "✗ ReceiptFlowStrip/ReceiptBars no longer carry an AXChartDescriptor"; exit 1; }

# 2. THERE IS NO PAPER AND NO TEAR (prd §583, 2026-09-03). This block used to
#    assert the opposite — that `ReceiptPaper.tear` stayed an animatable
#    fraction, that it ran on `DS.Motion.tear`, and that Reduce Motion was
#    honoured. All three are now inverted rather than deleted, because the
#    treatment they guarded is exactly the kind that creeps back: a paper is
#    easy to re-add one head at a time, and §495 is still in the ledger arguing
#    for it.
! grep -q 'dsReceiptPaper\|ReceiptPaper(tear:' "$CARD" \
  || { echo "✗ the receipt paper is back (prd §583 removed it)"; exit 1; }
! grep -q 'DS.Motion.tear' "$CARD" \
  || { echo "✗ the tear animation is back (prd §583 removed the edge it cut)"; exit 1; }
! grep -q 'static let tear = Animation' "$TOKENS" \
  || { echo "✗ DS.Motion.tear is back — a motion token nothing animates"; exit 1; }
# Since prd §1394 the head is content-sized in the lead's column (no box: the
# air a fixed box held under a three-line receipt was the complaint), and the
# state is the head's word, never a Details row.
grep -q 'padding(.horizontal, DSRoomChassis.leadInset)' "$CARD" \
  || { echo "✗ MoneySheetHead no longer stands in the lead's column (prd §1394)"; exit 1; }
! grep -q 'label: String(localized: "Status"),$' "$SHEET" \
  || { echo "✗ the state is a Details row again — the head says it once (prd §1394)"; exit 1; }
grep -q 'case .settled, .filled: return nil' "$CARD" \
  || { echo "✗ a settled receipt draws a state word — it says so by saying nothing (prd §1394)"; exit 1; }
# WHAT THE TEAR SAID, THE STAMP MUST GO ON SAYING. This is the load-bearing
# half of §583: the edge carried finality, and deleting it was only safe
# because every state that resolves to `.open` also stamps a word in a
# NON-QUIET ink. `refund` is the only case allowed in the quiet arm — it is the
# one stamp that pairs with `.torn`. Put `pending` (or any other open state)
# in there and the receipt goes silent about being unfinished, with nothing
# left on screen to say so.
MODEL="Casberi/Casberi/Model/MoneyReceipt.swift"
quiet_arm=$(grep -o 'case \.refund: *return \.quiet' "$MODEL" | head -1)
[[ -n "$quiet_arm" ]] \
  || { echo "✗ the quiet stamp arm changed — an unfinished receipt may now stamp quietly (prd §583)"; exit 1; }
grep -qE 'case \.pending, \.settling, \.screening: *return \.waiting' "$MODEL" \
  || { echo "✗ pending/settling/screening no longer stamp in attention ink (prd §583)"; exit 1; }
grep -qE 'case \.yourTurn, \.needsProof, \.openPosition: *return \.urgent' "$MODEL" \
  || { echo "✗ yourTurn/needsProof/openPosition no longer stamp urgent (prd §583)"; exit 1; }
# The haptic has somewhere to land. The bus is global but the MAPPING is a view
# modifier, and a `.sheet` covers the one RootShell attaches — so without this
# every DSHaptic call in the thing sheet bumps a counter nothing listens to,
# which is exactly how six of them shipped silent (2026-08-16).
grep -q 'SheetHaptics(active:' "$SHEET" \
  || { echo "✗ ThingSheetView no longer attaches its own haptic listener — its DSHaptic calls are silent"; exit 1; }

# 3. The subject face is a door, and only ever onto a real address.
grep -q 'onSubject: openAddressCard' "$SHEET" \
  || { echo "✗ the receipt's subject face is no longer a door"; exit 1; }
# A FOURTH sibling `.sheet` on this view is the one-screen-one-sheet failure
# the file's own `fullScreenCover` comment went out of its way to avoid, so the
# address card shares the face route rather than adding one.
[[ $(grep -c '^\s*\.sheet(item:' "$SHEET") -le 3 ]] \
  || { echo "✗ ThingSheetView grew a fourth sibling .sheet (one-screen-one-sheet)"; exit 1; }

# 4. The figure counts rather than blinking.
grep -q 'amount.numeric.map { .numericText' "$CARD" && grep -q 'contentTransition(roll)' "$CARD" \
  || { echo "✗ the figure no longer rolls when a pending amount settles"; exit 1; }

# 5. The flat edge on the lock screen. Every failure here is a lock screen that
#    looks completely normal while overclaiming — the hardest kind to notice,
#    because the person who would notice is not holding the phone.
ACTATTR="Casberi/Shared/MoneyActivityAttributes.swift"
ACTDRV="Casberi/Casberi/Model/MoneyActivityDriver.swift"
ACTVIEW="Casberi/CasberiWidgets/MoneyActivity.swift"
BUNDLE="Casberi/CasberiWidgets/CasberiWidgets.swift"
for f in "$ACTATTR" "$ACTDRV" "$ACTVIEW"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
# It is registered, or none of the rest of this exists at runtime.
grep -q 'MoneyActivity()' "$BUNDLE" \
  || { echo "✗ MoneyActivity is not in the widget bundle — it would never appear"; exit 1; }
# The age is on screen. This is the entire honesty rail: a Live Activity's
# grammar implies "now", and the app only knows what the last sweep told it.
grep -q 'checkedAt' "$ACTVIEW" \
  || { echo "✗ the activity no longer shows when the state was last checked"; exit 1; }
grep -q 'staleDate: .now + staleAfter' "$ACTDRV" \
  || { echo "✗ the activity no longer goes stale — it would state old news in the present tense"; exit 1; }
# Only an UNFINISHED record earns the control. (This used to read "and the
# tear is what ends it"; §583 removed the tear, and `finality` itself is
# untouched — it was always the more useful half.)
grep -q 'moneyReceipt.finality == .open' "$SHEET" \
  || { echo "✗ the lock-screen control is no longer gated on an unfinished record"; exit 1; }
# `sync` runs off the pass that really re-read the sources. The background
# sweep deliberately does not drive a bridge refresh, so moving `checkedAt`
# there would claim a check that never happened.
grep -q 'MoneyActivityDriver.sync(context:' "Casberi/Casberi/Shell/RootShell.swift" \
  || { echo "✗ tracked records are no longer synced after the foreground bridge sweep"; exit 1; }
if grep -q 'MoneyActivityDriver' "Casberi/Casberi/Model/WalletBackgroundRefresh.swift"; then
  echo "✗ the background sweep moves checkedAt — it does not re-read the sources (see MoneyActivityDriver.sync)"; exit 1
fi

# A receipt suppresses the content area. Without this the sheet draws the
# receipt AND the old `default:` branch under it — which for ten families is a
# block-explorer URL rendered as a paragraph, the exact thing this pass removed.
# Spelled in two typed steps since prd §1187 (the body sits at the type
# checker's budget): the shape gate leads with the receipt, and the content
# flag is built on it.
grep -q 'let shapeHasBody: Bool = moneyReceipt == nil' "$SHEET" \
  && grep -q 'let contentShown: Bool = shapeHasBody' "$SHEET" \
  || { echo "✗ the content area is no longer suppressed under a receipt"; exit 1; }

# The commentary FETCHES. Computing it per body evaluation would walk a source's
# rows on every re-render of an open sheet.
grep -q '@State private var moneySays' "$SHEET" \
  || { echo "✗ commentary is no longer held in state (it fetches — see loadReceipt)"; exit 1; }

# Liveness: the receipt views take VALUES, never a Thing, so no view here can
# hold a tombstoned model across a re-render (the build-188 leaf rule).
if grep -qE '^\s*(let|var) thing: Thing' "$CARD"; then
  echo "✗ a receipt view stores a Thing — it must take values only (build 188)"; exit 1
fi

# The pour is a TOKEN. §8 is law: components hold zero raw hex.
grep -q 'static func receiptPour' "$TOKENS" \
  || { echo "✗ DS.receiptPour is gone — the pour would be raw hex in a view"; exit 1; }
if grep -qE '#[0-9a-fA-F]{6}' "$CARD"; then
  echo "✗ the receipt file holds raw hex (§8: every value routes through a token)"; exit 1
fi

# The two parsers that survived the stage retirement, and the two readers that
# depend on them. Deleting either silently drops a swap's rate line and turns a
# self-move's Name disc back on, both of which render as "fine".
grep -q 'struct SwapStage' "$STAGE" \
  || { echo "✗ SwapStage is gone — a swap's rate line has nothing to divide"; exit 1; }
# Since prd §1181 naming is the fourth tile's Save (`moneyKeep`), offered only
# with a person on the other side — `moneyHasPerson`, the SAME `MovedStage`
# gate: a self-move's other side is your own wallet.
grep -q 'thing.source == "Wallet" && MovedStage(thing) == nil' "$SHEET" \
  || { echo "✗ Save no longer stands down on a self-move"; exit 1; }

# The probe. An absent receipt has six causes and only two are bugs; without
# this hook there is no way to tell them apart on a device.
grep -q 'Hook(key: "receiptProbe")' "$PROBES" \
  || { echo "✗ -receiptProbe is gone"; exit 1; }

# NEGATIVE guards read a COMMENT-STRIPPED copy — these files DOCUMENT the things
# they must never do, by naming them, so a guard grepping raw source fires on
# the prose explaining it (the Obsidian/Cursor lesson, earned a fourth time).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = "\n".join(l for l in src.splitlines() if not l.strip().startswith("//"))
sys.stdout.write(src)
PY
}
strip_comments "$SOURCE" > "$TMP/source-bare.swift"

# The source half must not re-derive facts from prose. The whole point of the
# pass: a title is a localized sentence, and a receipt built by parsing one is a
# receipt that changes meaning in another language.
if grep -qE 'title\.(hasPrefix|contains|range\(of:)' "$TMP/source-bare.swift"; then
  echo "✗ MoneyReceiptSource parses the title — facts come off stamped fields"; exit 1
fi

# NO FIGURE ON THE LOCK SCREEN (§374). Comment-stripped, because all three of
# these files explain the rule by naming exactly what they must not carry — the
# Obsidian/Cursor lesson, earned a fifth time.
for f in "$ACTATTR" "$ACTVIEW"; do
  strip_comments "$f" > "$TMP/act-bare.swift"
  if grep -qE '\b(amount|figure|priceValue|balance)\b' "$TMP/act-bare.swift"; then
    echo "✗ $f carries a money figure — the lock screen is the one surface §374 is about"; exit 1
  fi
done

# --- every Wallet app opens a receipt (prd §1341) ---------------------------
# "they all look like that" (user, 2026-10-16): a Lightning payment and an
# Acorns account under Home's Transactions opened the GENERIC sheet, because
# `MoneyReceipt.sources` was a hand list nothing held to the Wallet's apps.
# The Wallet's apps are read out of `RoomAccounts.wallet` (each seat's
# `source:` resolved to the literal its type declares), plus the Wallet's own
# rows, and each must be in `sources` or `elsewhere` (with its reason).
ROOMS="Casberi/Casberi/Model/RoomAccounts.swift"
coverage_check() {
  python3 - "$1" "$ROOMS" <<'PY'
import re, sys, glob
receipt, rooms = open(sys.argv[1]).read(), open(sys.argv[2]).read()
m = re.search(r'private static let wallet: \[Seat\] = \[(.*?)\n    \]', rooms, re.S)
if not m:
    print("✗ RoomAccounts.wallet not found — the Wallet's apps cannot be read"); sys.exit(1)
files = {p: open(p).read() for p in glob.glob("Casberi/Casberi/Model/*.swift")}
def resolve(expr, depth=0):
    expr = expr.strip()
    if expr.startswith('"'): return expr.strip('"')
    if depth > 3 or "." not in expr: return None
    typ, name = expr.split(".", 1)
    for src in files.values():
        t = re.search(r'\b(enum|struct|class) ' + re.escape(typ) + r'\b', src)
        if not t: continue
        v = re.search(r'static let ' + re.escape(name) + r'\s*=\s*([^\n]+)', src[t.start():])
        if v: return resolve(v.group(1), depth + 1)
    return None
sources = set(re.findall(r'"([^"]+)"', re.search(r'static let sources: Set<String> = \[(.*?)\]', receipt, re.S).group(1)))
elsewhere = set(re.findall(r'^\s*"([^"]+)":', re.search(r'static let elsewhere: \[String: String\] = \[(.*?)\n    \]', receipt, re.S).group(1), re.M))
seats = re.findall(r'source: ([^,\n]+),', m.group(1))
wallet = {"Wallet"}
for expr in seats:
    if expr.strip() == "nil": continue
    lit = resolve(expr)
    if lit is None:
        print(f"✗ could not resolve the Wallet seat source {expr.strip()} to a literal"); sys.exit(1)
    wallet.add(lit)
if len(wallet) < 15:
    print(f"✗ only {len(wallet)} Wallet sources read — the seat table moved"); sys.exit(1)
missing = sorted(wallet - sources - elsewhere)
if missing:
    print("✗ Wallet apps with no receipt arm and no stated elsewhere: " + ", ".join(missing)); sys.exit(1)
both = sorted(sources & elsewhere)
if both:
    print("✗ in both sources and elsewhere: " + ", ".join(both)); sys.exit(1)
print(f"  every Wallet app opens a receipt or says where it opens ({len(wallet)} sources)")
PY
}
coverage_check "$RECEIPT" || exit 1
# The check bites: a copy without Lightning's entry must fail it.
sed 's/"Lightning", "Privy",/"Privy",/' "$RECEIPT" > "$TMP/no-lightning.swift"
grep -q '"Lightning"' "$TMP/no-lightning.swift" && ! grep -q '"Lightning", "Privy"' "$TMP/no-lightning.swift" \
  || { echo "✗ the coverage mutation did not apply"; exit 1; }
if coverage_check "$TMP/no-lightning.swift" > /dev/null 2>&1; then
  echo "✗ the coverage check passed with Lightning's arm gone — it checks nothing"; exit 1
fi

# The literals `MoneyReceipt` (Foundation-only, compiled alone) spells for
# the bridges' own refs and tags must stay the bridges' own.
grep -q 'static let refPrefix = "privy:app:"' "Casberi/Casberi/Model/PrivyHomeFeed.swift" \
  || { echo "✗ PrivyHomeFeed.refPrefix moved — MoneyReceipt.isState spells it"; exit 1; }
grep -q 'static let accountPrefix = "splits:account:"' "Casberi/Casberi/Model/SplitsShape.swift" \
  && grep -q 'static let waitingTag = "Waiting"' "Casberi/Casberi/Model/SplitsShape.swift" \
  || { echo "✗ SplitsShape's account prefix or waiting tag moved — MoneyReceipt spells them"; exit 1; }
grep -q 'static let source = "Acorns"' "Casberi/Casberi/Model/AcornsLive.swift" \
  && grep -q 'static let source = "Rocket Money"' "Casberi/Casberi/Model/RocketMoneyLive.swift" \
  || { echo "✗ the reading seats' source names moved — MoneyReceipt.isReading spells them"; exit 1; }
# A reading is drawn: the source half lets one through its kind gate…
grep -q 'MoneyReceipt.isReading(source: thing.source, ref: thing.sourceRef)' "$SOURCE" \
  || { echo "✗ MoneyReceiptSource no longer lets a reading through — an Acorns balance falls to the generic sheet"; exit 1; }
# …and the sheet ends a reading at its box: no tiles, no history.
grep -q 'if moneyReceipt.form == .record {' "$SHEET" \
  || { echo "✗ a reading draws the record's tiles and history again"; exit 1; }
# A balance is never a transaction: Activity's list and its history share one
# filter (Activity's stream left Home for its own page in prd §1480).
grep -q 'let moves = Self.walletMoves(all)' "Casberi/Casberi/Screens/FeedScreen+WalletPages.swift" \
  && grep -q 'walletSeeAllSection(older:' "Casberi/Casberi/Screens/FeedScreen+WalletPages.swift" \
  && grep -q 'FeedScreen.walletMoves(all.live)' "Casberi/Casberi/Screens/WalletHistoryScreen.swift" \
  || { echo "✗ Transactions or its history lists states again (prd §1341)"; exit 1; }
# They stand on Holdings › Apps since prd §1503 (§1480 put them behind a door).
grep -q 'walletAccountsSection(appAccounts, nextEventID: nextEventID)' "Casberi/Casberi/Screens/FeedScreen+WalletPages.swift" \
  || { echo "✗ Holdings no longer lists the accounts Transactions left out — they would vanish"; exit 1; }
# No Lightning row's content is its hash, the demo's included.
! grep -q 'content: "lightning:' "Casberi/Casberi/Model/LightningBridge.swift" "Casberi/Casberi/Model/DemoSeedAll.swift" \
  || { echo "✗ a Lightning row's content is its ref again — the sheet draws it as the card"; exit 1; }

# --- the harness ------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let cal = Calendar(identifier: .gregorian)
let now = Date(timeIntervalSince1970: 1_754_000_000)   // fixed clock

// Dates relative to the FIXED clock — for the `dayPhrase(_:now:)` units
// below, which pass that clock in explicitly and so are fully deterministic.
func at(_ daysAgo: Int, hour: Int = 9) -> Date {
    let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
    return cal.date(bySettingHour: hour, minute: 41, second: 0, of: day)!
}

// Dates relative to the REAL clock — for every fixture that goes through
// `MoneyReceipt.compose`. `compose` calls `dayPhrase(f.capturedAt)` with its
// DEFAULT `now`, i.e. the system clock, so a fixture dated off the fixed
// clock above lands ~a year in the past and every sentence comes out in the
// dated form. That is what made "no chain read means no 'on <chain>' clause"
// fail: with no network the sentence is "Received into Main <dayPhrase>." and
// the dated phrase is itself "on 31 July 2025", so the clause the assertion
// was looking for appeared without any chain being read.
func realAt(_ daysAgo: Int, hour: Int = 9) -> Date {
    let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
    return cal.date(bySettingHour: hour, minute: 41, second: 0, of: day)!
}

// MARK: split — the ticker rule

do {
    check(MoneyReceipt.split("0.9962 ETH").number == "0.9962", "split keeps the number")
    check(MoneyReceipt.split("0.9962 ETH").unit == "ETH", "split reads the ticker")
    check(MoneyReceipt.split("1,240.00 USDC").unit == "USDC", "split reads a grouped amount's ticker")
    check(MoneyReceipt.split("12.4 EURe").unit == "EURe", "a mixed-case ticker still reads")
    // The measured spoof. A phishing domain must never reach the unit slot.
    let spoof = MoneyReceipt.split("4,672 USDT Staked • gitos.org")
    check(spoof.unit == nil, "a spoofed token name yields NO unit")
    check(spoof.number.contains("gitos.org"), "the spoof stays inside the clamped number")
    check(MoneyReceipt.split("317.78 MAG7").unit == "MAG7", "a ticker with a digit reads (prd §1373)")
    check(MoneyReceipt.split("100 2024").unit == nil, "a bare number is not a unit")
    check(MoneyReceipt.split("5 VERYLONGTICKERNAME").unit == nil, "an over-long unit is refused")
    check(MoneyReceipt.split(nil).number == "", "nil amount is empty, not a crash")
    check(MoneyReceipt.split("crypto").unit == nil, "a bare word is not a unit")
}

// MARK: dayPhrase — human time, and no weekday for a date that hasn't happened

do {
    check(MoneyReceipt.dayPhrase(at(0, hour: 9), now: now, calendar: cal) == "this morning",
          "today at 09:41 is this morning")
    check(MoneyReceipt.dayPhrase(at(0, hour: 15), now: now, calendar: cal) == "this afternoon",
          "today at 15:41 is this afternoon")
    check(MoneyReceipt.dayPhrase(at(0, hour: 2), now: now, calendar: cal) == "overnight",
          "today at 02:41 is overnight")
    check(MoneyReceipt.dayPhrase(at(1), now: now, calendar: cal) == "yesterday", "yesterday")
    let threeDays = MoneyReceipt.dayPhrase(at(3), now: now, calendar: cal)
    check(threeDays.count > 3 && !threeDays.contains(","), "three days back names a weekday")
    let far = MoneyReceipt.dayPhrase(at(40), now: now, calendar: cal)
    check(far.rangeOfCharacter(from: .decimalDigits) != nil, "forty days back is a date")
    // A clock skew, or a bridge stamping ahead. A weekday for a day that has
    // not happened is the confident wrong answer.
    let future = cal.date(byAdding: .day, value: 3, to: now)!
    let ahead = MoneyReceipt.dayPhrase(future, now: now, calendar: cal)
    check(ahead.rangeOfCharacter(from: .decimalDigits) != nil,
          "a FUTURE date is dated, never given a weekday")
}

// MARK: currency — never a bare number

do {
    check(MoneyReceipt.currency(nil, code: "USD") == nil, "no value, no figure")
    check(MoneyReceipt.currency(6.75, code: nil) == nil, "no currency, no figure")
    check(MoneyReceipt.currency(6.75, code: "") == nil, "an empty currency is no currency")
    check(MoneyReceipt.currency(6.75, code: "USD")?.contains("6.75") == true, "cents where they matter")
    check(MoneyReceipt.currency(-6.75, code: "USD")?.contains("-") == false,
          "the sign is the receipt's, not the formatter's")
}

// MARK: the wallet transfer

func transfer(_ direction: String, amount: String = "0.9962 ETH",
              usd: Double? = 3480) -> MoneyReceipt.Facts {
    var f = MoneyReceipt.Facts(source: "Wallet", title: "Received 0.9962 ETH from maria.eth")
    f.capturedAt = realAt(0)
    f.direction = direction
    f.amount = amount
    f.usd = usd
    f.counterpartyAddress = "0x4f2a"
    f.walletAddress = "0xmine"
    f.partyLabel = "maria.eth"
    f.myLabel = "Main"
    f.network = "Ethereum"
    return f
}

do {
    guard let r = MoneyReceipt.compose(transfer("received")) else {
        print("  ✗ a received transfer composes nothing"); failures += 1; exit(1)
    }
    check(r.amount?.number == "+0.9962", "a receive wears a plus")
    check(r.amount?.unit == "ETH", "the unit rides beside the figure")
    check(r.amount?.tone == .gain, "a gain is green")
    check(r.finality == .torn, "a settled transfer is torn off")
    check(r.stamp == .settled, "and stamped settled")
    check(r.mine == "0xmine", "your wallet rides as the tucked face")
    check(r.subject == .address("0x4f2a"), "an address beats a name for the disc")
    check(r.sentence.contains("Main"), "the sentence names the wallet")
    check(r.sentence.contains("Ethereum"), "and the network")
    check(r.secondary?.contains("3,480") == true, "worth at landing, not today")

    guard let s = MoneyReceipt.compose(transfer("sent")) else {
        print("  ✗ a sent transfer composes nothing"); failures += 1; exit(1)
    }
    check(s.amount?.number == "−0.9962", "a send wears a minus")
    // Spending is not a loss state; red would editorialize and green would lie.
    check(s.amount?.tone == .plain, "a send is NOT toned as a gain")

    // No price read: nothing rather than a guess.
    let unpriced = MoneyReceipt.compose(transfer("received", usd: nil))
    check(unpriced?.secondary == nil, "an unpriced transfer states no fiat")

    // No network in the content: the clause is dropped, not guessed.
    var noChain = transfer("received"); noChain.network = nil
    check(MoneyReceipt.compose(noChain)?.sentence.contains("on ") == false,
          "no chain read means no 'on <chain>' clause")

    // No stamped direction at all — a swap, a self-move, a Morpho supply.
    var bare = transfer("received"); bare.direction = nil; bare.amount = nil
    let generic = MoneyReceipt.compose(bare)
    check(generic?.amount == nil, "with no stamped figure there is no headline number")
    // Titled by its own sentence (prd §1357.1), never "In your wallet" or the
    // wallet's name, and the box does not say the sentence again (§1360).
    check(generic?.party == "Received 0.9962 ETH from maria.eth", "it is titled by its own sentence")
    check(generic?.titleFallback == nil, "and the box does not restate it")

    // SETTLED ONLY WHEN IT SETTLED (prd §83): a trade with no direction and
    // no figure states no status; one with a stamped direction does.
    var trade = MoneyReceipt.Facts(source: "Wallet", title: "Bought SOL")
    trade.capturedAt = realAt(1)
    check(MoneyReceipt.compose(trade)?.stamp == nil, "a figureless trade is never stamped settled")
    check(MoneyReceipt.compose(trade)?.party == "Bought SOL", "and is titled by its sentence")
    trade.direction = "received"
    check(MoneyReceipt.compose(trade)?.stamp == .settled, "a past move with a direction is settled")
    trade.capturedAt = Date().addingTimeInterval(86_400 * 3)
    check(MoneyReceipt.compose(trade)?.stamp == nil, "a row dated ahead is never settled")

    // Deadlines are moments, not receipts (prd §83).
    for ref in ["hyperliquid:unlock:0xme:0xv", "wallet:ensexpiry:quillmark.eth",
                "aerodrome:vote:0xme:4821", "demo:aerodrome:vote:0xme:1"] {
        var ahead = MoneyReceipt.Facts(source: "Wallet", title: "Staked HYPE unlocks")
        ahead.sourceRef = ref
        ahead.capturedAt = realAt(4)
        check(MoneyReceipt.compose(ahead) == nil, "\(ref) is not a receipt")
    }
    var due = MoneyReceipt.Facts(source: "Wallet", title: "Bitcoin halving")
    due.capturedAt = realAt(4)
    due.dueAt = Date().addingTimeInterval(86_400 * 30)
    check(MoneyReceipt.compose(due) == nil, "a wallet row with a due date ahead is not a receipt")
}

// MARK: Bitcoin

do {
    var f = MoneyReceipt.Facts(source: "Wallet", title: "Received 0.0412 BTC")
    f.capturedAt = realAt(0)
    f.direction = "received"
    f.amount = "0.0412 BTC"
    f.venue = "Block 959,701"
    f.walletAddress = "bc1q"
    f.settling = true
    guard let settling = MoneyReceipt.compose(f) else {
        print("  ✗ bitcoin composes nothing"); failures += 1; exit(1)
    }
    check(settling.hue == .bitcoin, "bitcoin pours its own hue")
    check(settling.stamp == .settling, "short of the bar, it is settling")
    // A transfer that can still be reorganized out of the chain is not history.
    check(settling.finality == .open, "and is NOT torn off")
    check(settling.sentence.contains("Block 959,701"), "the block is the sentence's subject")
    check(settling.secondary == nil,
          "no line narrates the missing dollar figure (prd §1416)")

    f.settling = false
    check(MoneyReceipt.compose(f)?.finality == .torn, "once settled, it tears")
    f.venue = nil
    check(MoneyReceipt.compose(f)?.sentence.contains("Block") == false,
          "no block read means no block claimed")
}

// MARK: card spends

func card(_ source: String, tags: [String], merchant: String? = "Blue Bottle Coffee")
    -> MoneyReceipt.Facts {
    var f = MoneyReceipt.Facts(source: source, title: "Blue Bottle Coffee · $6.75")
    f.capturedAt = realAt(0)
    f.counterparty = merchant
    f.priceValue = 6.75
    f.priceCurrency = "USD"
    f.tags = tags
    f.authorHandle = "Apple Card, ending 4821"
    return f
}

do {
    guard let pending = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card", "Pending"])) else {
        print("  ✗ a card spend composes nothing"); failures += 1; exit(1)
    }
    check(pending.stamp == .pending, "an unsettled authorization is pending")
    // The amount can still change. A torn edge here is a claim of finality
    // over a number that isn't final.
    check(pending.finality == .open, "and is NOT torn off")
    check(pending.amount?.number.hasPrefix("−") == true, "a spend wears a minus")
    check(pending.subject == .named("Blue Bottle Coffee"), "the merchant is the subject")
    check(pending.mine == nil, "a card spend has one party, so no tucked face")
    check(pending.secondary?.contains("4821") == true, "the account is named")
    check(pending.sentence.contains("still change"), "and the sentence says it can change")
    check(pending.hue == .neutral, "Apple Card has no brand hue to borrow")

    let settled = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card"]))
    check(settled?.finality == .torn, "a settled charge tears")
    check(settled?.stamp == .settled, "and is stamped settled")

    let refund = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card", "Refund"]))
    check(refund?.amount?.number.hasPrefix("+") == true, "a refund wears a plus")
    check(refund?.amount?.tone == .gain, "a refund is a gain")
    check(refund?.stamp == .refund, "and is stamped as one")

    // Onchain cards carry NO merchant — a ceiling the copy has always named.
    let onchain = MoneyReceipt.compose(card("ether.fi", tags: ["Card"], merchant: nil))
    check(onchain?.subject == .absent(.merchantOffchain),
          "an onchain card with no merchant draws a VOID, not a monogram")
    check(onchain?.hue == .card, "and pours the card hue")
    // Apple Wallet genuinely knows merchants, so a missing one there is an
    // ordinary gap and must NOT claim to be a designed absence.
    let appleNoMerchant = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card"], merchant: nil))
    if case .absent = appleNoMerchant?.subject {
        check(false, "a missing Apple Wallet merchant must not read as a designed absence")
    }

    var unreadable = card("Apple Wallet", tags: ["Card"])
    unreadable.priceValue = nil
    unreadable.amount = nil
    check(MoneyReceipt.compose(unreadable)?.amount == nil, "no readable amount, no figure")
}

// MARK: Privacy Pools

do {
    var f = MoneyReceipt.Facts(source: "Privacy Pools", title: "Put 0.0700 ETH into Privacy Pools")
    f.capturedAt = realAt(6)
    f.amount = "0.0700 ETH"
    f.tags = ["Shielded", "Pending"]
    f.walletAddress = "0xmine"
    f.myLabel = "Main"
    guard let screening = MoneyReceipt.compose(f) else {
        print("  ✗ a deposit composes nothing"); failures += 1; exit(1)
    }
    check(screening.stamp == .screening, "a pending deposit is screening")
    // The money is not yours to move until screening clears.
    check(screening.finality == .open, "and the paper is NOT torn")
    // The stamp, the ladder ("Clear to withdraw · not yet") and the commentary
    // each say where screening stands, so the sentence carries only the date.
    check(screening.sentence.hasPrefix("In since") && !screening.sentence.contains("withdraw"),
          "the sentence gives the date and leaves the state to the stamp")
    check(screening.subject == .named("Privacy Pools") && screening.mine == nil,
          "the pool's own mark is the subject, with no person badge")
    check(screening.hue == .shield, "and it pours the shield hue")

    f.tags = ["Shielded", "Approved"]
    let cleared = MoneyReceipt.compose(f)
    check(cleared?.stamp == .cleared, "an approved deposit is clear to withdraw")
    check(cleared?.finality == .torn, "and only then does it tear")

    f.tags = ["Shielded", "Proof"]
    check(MoneyReceipt.compose(f)?.stamp == .needsProof, "a proof request is its own state")
    check(MoneyReceipt.compose(f)?.finality == .open, "and is never final")
}

// MARK: Railgun

do {
    var f = MoneyReceipt.Facts(source: "Railgun", title: "Unshielded 1.5 ETH")
    f.capturedAt = realAt(1)
    f.direction = "received"
    f.amount = "1.5000 ETH"
    f.walletAddress = "0xmine"
    f.myLabel = "Main"
    f.network = "Ethereum"
    guard let unshield = MoneyReceipt.compose(f) else {
        print("  ✗ an unshield composes nothing"); failures += 1; exit(1)
    }
    // The privacy IS the feature. A monogram would read as a face we failed to
    // load, which turns a guarantee into a bug report.
    // Railgun's own mark, no person badge (prd §1341 amended): the void drew
    // as an empty disc; the sender's privacy is the line's words.
    check(unshield.subject == .named("Railgun"), "an unshield wears Railgun's mark")
    check(unshield.mine == nil, "and no person badge")
    check(unshield.finality == .torn, "the arrival is final — privacy is not incompleteness")
    check(unshield.stamp == .unshielded, "and it is stamped UNshielded, never shielded (prd §83)")
    check(unshield.secondary?.contains("nothing about where it came from") == true,
          "the second line states the ceiling")

    f.direction = "sent"
    let shield = MoneyReceipt.compose(f)
    if case .absent = shield?.subject {
        check(false, "a SHIELD has a known sender — it must not draw the void")
    }
    check(shield?.stamp == .shielded, "a shield is stamped shielded")
}

// MARK: Wise (prd §1332)

do {
    var f = MoneyReceipt.Facts(source: "Wise", title: "Needs attention · £200.00 → €235.00 · Deposit")
    f.capturedAt = realAt(0)
    f.priceValue = 200
    f.priceCurrency = "GBP"
    f.tags = ["Transfer", "Pending", "Needs attention"]
    guard let stuck = MoneyReceipt.compose(f) else {
        print("  ✗ a Wise transfer composes nothing"); failures += 1; exit(1)
    }
    check(stuck.stamp == .yourTurn, "a stuck Wise transfer says it's your turn")
    check(stuck.lead == "Waiting on you", "it leads with what it waits on")
    check(stuck.party == "Deposit", "it is named by the reference you wrote")
    check(stuck.secondary == "€235.00 arrives", "it says what arrives, off the title's pair")
    check(stuck.amount?.number.hasPrefix("−") == true, "the money that left is a minus")
    check(stuck.finality == .open, "a stuck transfer is never torn")
    f.tags = ["Transfer"]
    f.title = "Sent · £200.00 → €235.00"
    let sent = MoneyReceipt.compose(f)
    check(sent?.stamp == .settled && sent?.finality == .torn, "a sent transfer tears, settled")
    // With no reference, the title is what happened to the money (§1357.1),
    // never the state word alone.
    check(sent?.party?.hasPrefix("Sent ") == true && sent?.party?.contains("200") == true,
          "no reference: titled by what was sent")
    f.title = "Returned · £300 → €351"
    f.priceValue = 300
    f.tags = ["Transfer", "Returned"]
    let back = MoneyReceipt.compose(f)
    check(back?.party?.hasSuffix("came back") == true && back?.party?.contains("300") == true,
          "a returned transfer is titled by the money that came back, never 'Came back'")
}

// MARK: Safe

do {
    var f = MoneyReceipt.Facts(source: "Safe", title: "Treasury · a transfer of 12,500 USDC")
    f.capturedAt = realAt(0)
    f.walletAddress = "0xsafe"
    f.myLabel = "Treasury"
    f.tags = ["Your turn"]
    f.signaturesHave = 2
    f.signaturesNeed = 3
    guard let waiting = MoneyReceipt.compose(f) else {
        print("  ✗ a Safe transaction composes nothing"); failures += 1; exit(1)
    }
    check(waiting.stamp == .yourTurn, "a tagged transaction says it's your turn")
    check(waiting.finality == .open, "an unsigned transaction is never torn")
    // An empty "Receipt —" row reads as a bug; a sentence reads as the truth.
    check(waiting.sentence.contains("no receipt to show"),
          "it says in words that there is no receipt yet")
    check(waiting.secondary?.contains("one more signature") == true,
          "one short is said as one short")
    check(waiting.amount == nil, "a multisig payload's value is never parsed out of prose")

    f.signaturesHave = 1
    check(MoneyReceipt.compose(f)?.secondary?.contains("one more") == false, "two short is not 'one more'")
    // FULLY SIGNED IS NOT EXECUTED (prd §83): a queue row is waiting until the
    // bridge lands its outcome.
    f.signaturesHave = 3
    f.tags = []
    let signed = MoneyReceipt.compose(f)
    check(signed?.stamp == .waiting && signed?.finality == .open, "a fully signed proposal still waits")
    // The demo, and any open before the live check answers: no counts read,
    // so the title's own count says who it waits on — never "Settled".
    var queued = MoneyReceipt.Facts(source: "Safe",
        title: "1 of 3 signatures collected on an approval for Uniswap to spend 0 USDC — waiting on others")
    queued.capturedAt = realAt(6)
    queued.sourceRef = "wallet:safe:eth:demo3"
    let q = MoneyReceipt.compose(queued)
    check(q?.stamp == .waiting, "an unsigned proposal is Waiting, never Settled")
    check(q?.finality == .open, "and never final")
    check(q?.secondary?.contains("2 more") == true, "it says who it waits on, off the title's count")
    check(q?.party == "Approve Uniswap", "named by what it does")
    var done = MoneyReceipt.Facts(source: "Safe",
        title: "Executed after 2 days — a transfer of 900 USDC to vendor.eth went through")
    done.capturedAt = realAt(1)
    done.sourceRef = "wallet:safeoutcome:eth:0xabc"
    let d = MoneyReceipt.compose(done)
    check(d?.stamp == .settled && d?.finality == .torn, "only an executed outcome is settled")
    check(d?.party == "Send 900 USDC" && d?.titleFallback == "to vendor.eth", "an outcome is named by its act")
    done.title = "Replaced — a transfer of 900 USDC to vendor.eth never executed; a rival transaction went through at the same nonce instead"
    check(MoneyReceipt.compose(done)?.stamp == .replaced, "a replaced proposal says so, never Settled")
}

// MARK: price rise (prd §1357.4)

do {
    var f = MoneyReceipt.Facts(source: "Apple Wallet", title: "Notion went up 20% — $10.00 to $12.00")
    f.capturedAt = realAt(10)
    f.sourceRef = "demo:applewallet:creep:notion:1000:1200:20367"
    f.counterparty = "Notion"
    f.priceValue = 12
    f.priceCurrency = "USD"
    f.tags = ["Price rise"]
    let r = MoneyReceipt.compose(f)
    check(r?.party == "Notion went up 20%", "a price rise is titled by its own words, the prices left to the box")
    check(r?.amount?.number.contains("12.00") == true, "the box says what it costs now")
    check(r?.secondary?.contains("10.00") == true && r?.secondary?.hasPrefix("was") == true,
          "and what it was, off the ref")
    check(r?.stamp == nil, "a price rise is never stamped settled")
    check(MoneyReceipt.creepWas(ref: "applewallet:creep:x:1549:1799:20000") == 15.49, "the was figure is the ref's")
}

// MARK: a card charge is read to the cent

do {
    var f = MoneyReceipt.Facts(source: "Plasma One", title: "Spent $305.80")
    f.capturedAt = realAt(2)
    f.priceValue = 305.80
    f.priceCurrency = "USD"
    check(MoneyReceipt.compose(f)?.amount?.number.contains("305.80") == true,
          "a $305.80 day is drawn to the cent, never \"$306\"")
}

// MARK: sources

do {
    let unknown = MoneyReceipt.Facts(source: "Bluesky", title: "a post")
    check(MoneyReceipt.compose(unknown) == nil, "a non-money source draws no receipt")
    check(MoneyReceipt.sources.contains("Peer"), "Peer is a money source")
    check(MoneyReceipt.sources.contains("Apple Wallet"), "Apple Wallet is a money source")
}

// MARK: commentary — history

do {
    // Four received, one sent: lopsided, so the claim is allowed.
    let lopsided: [(Double, Bool)] = [(1, true), (2, true), (0.5, false), (1, true), (3, true)]
    guard case .history(let head, let sub, let series)? =
        MoneyCommentary.history(party: "maria.eth", unit: "ETH", signed: lopsided) else {
        print("  ✗ a lopsided history composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("maria.eth") && head.contains("5"), "the headline counts and names")
    check(sub?.contains("Mostly them") == true, "and claims the direction")
    check(sub?.contains("biggest yet") == true, "the largest is called out")
    check(series.count == 5, "one bar per transfer")
    check(series[2] < 0, "a send is drawn below the line")

    // 3–2 is NOT lopsided. Claiming it would be a fluent wrong answer.
    let even: [(Double, Bool)] = [(1, true), (1, true), (1, false), (1, false), (1, true)]
    guard case .history(_, let evenSub, _)? =
        MoneyCommentary.history(party: "x", unit: "ETH", signed: even) else {
        print("  ✗ an even history composes nothing"); failures += 1; exit(1)
    }
    check(evenSub?.contains("Mostly") == false, "an even split makes NO 'mostly' claim")
    check(evenSub?.contains("both ways") == true, "it says both ways instead")

    // Two is a pair, not a pattern. One is the row you're reading.
    check(MoneyCommentary.history(party: "x", unit: "ETH",
                                  signed: [(1, true), (2, true)]) == nil,
          "two transfers earn no card")

    // Mixed tokens: the sentence survives, the bars do not — height means
    // quantity, and ETH beside USDC on one axis means nothing.
    guard case .note? = MoneyCommentary.history(party: "x", unit: nil,
                                                signed: lopsided) else {
        print("  ✗ a mixed-token history should degrade to a note"); failures += 1; exit(1)
    }

    // "Biggest yet" must be checkable, not decorative.
    let notBiggest: [(Double, Bool)] = [(9, true), (1, true), (2, true)]
    guard case .history(_, let nb, _)? =
        MoneyCommentary.history(party: "x", unit: "ETH", signed: notBiggest) else {
        print("  ✗ composes nothing"); failures += 1; exit(1)
    }
    check(nb?.contains("biggest") == false, "it is not called the biggest when it isn't")
}

// MARK: commentary — merchant

do {
    // One outlier. A MEAN would report ~$20 as typical, which is a spend that
    // never happened.
    let values: [Double] = [5, 5, 5, 5, 100, 6]
    guard case .merchant(let head, let sub, let drawn)? =
        MoneyCommentary.merchant(name: "Blue Bottle", values: values, currency: "USD") else {
        print("  ✗ a merchant board composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("5.00"), "typical is the MEDIAN, not the mean")
    check(!head.contains("20"), "and is not dragged by an outlier")
    check(sub?.contains("6") == true, "the window is named in the sentence")
    check(drawn.count == 6, "every charge is drawn")

    let highest: [Double] = [4, 5, 6, 99]
    guard case .merchant(_, let hs, _)? =
        MoneyCommentary.merchant(name: "x", values: highest, currency: "USD") else {
        print("  ✗ composes nothing"); failures += 1; exit(1)
    }
    check(hs?.contains("highest") == true, "a real high is called out")

    check(MoneyCommentary.merchant(name: "x", values: [5, 6], currency: "USD") == nil,
          "two charges are not a habit")
    check(MoneyCommentary.merchant(name: "x", values: [5, 6, 7], currency: nil) == nil,
          "no currency, no claim about money")
}

// MARK: commentary — rate

do {
    guard case .rate(let head, _)? =
        MoneyCommentary.rate(out: "0.5 ETH", into: "1,240.00 USDC") else {
        print("  ✗ a swap rate composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("2,480"), "0.5 ETH for 1,240 USDC is 2,480 per ETH, grouped")
    if case .rate(let back, _)? = MoneyCommentary.rate(out: "1,240 USDC", into: "0.5 ETH") {
        check(back.hasPrefix("1 ETH = 2,480 USDC"), "a rate under one is said from the other side (prd §1373)")
    } else { check(false, "a USDC-for-ETH rate composes") }
    let venue = MoneyReceipt.compose(MoneyReceipt.Facts(source: "Wallet",
        title: "Swapped 1,240 USDC → 0.4962 ETH on Uniswap"))
    check(venue?.party == "Swapped USDC for ETH", "a venue is no leg: the trade names its tokens (prd §1373)")
    let digit = MoneyReceipt.compose(MoneyReceipt.Facts(source: "Wallet",
        title: "Swapped 317.78 MAG7 → 3,869,551 MUSEGOD"))
    check(digit?.party == "Swapped MAG7 for MUSEGOD", "a ticker with a digit titles its trade (prd §1373)")
    check(head.contains("ETH") && head.contains("USDC"), "both units are named")
    check(MoneyCommentary.rate(out: "0.5", into: "1,240 USDC") == nil,
          "a leg with no unit yields no rate")
    check(MoneyCommentary.rate(out: "0 ETH", into: "1 USDC") == nil,
          "a zero leg is not divided by")
    check(MoneyCommentary.rate(out: "some ETH", into: "1 USDC") == nil,
          "an unreadable leg yields no rate")
}

// MARK: median

do {
    check(MoneyCommentary.median([1, 2, 3]) == 2, "odd median")
    check(MoneyCommentary.median([1, 2, 3, 4]) == 2.5, "even median")
    check(MoneyCommentary.median([]) == nil, "empty has no median")
    check(MoneyCommentary.number("1,240.00") == 1240, "grouped numbers read")
    check(MoneyCommentary.number("12 USDC") == nil, "a number with a word does not")
}

// MARK: said out loud — the tear, reachable by ear (prd §369 amendment)

do {
    // A settled send. The sign is a GLYPH in `number` (U+2212), and a screen
    // reader is free to skip a glyph — so direction, the one thing on a
    // receipt that must never be lost, has to be spelled.
    var sent = MoneyReceipt.Facts(source: "Wallet", title: "Sent 0.5 ETH")
    sent.direction = "sent"
    sent.amount = "0.5 ETH"
    sent.counterparty = "maria.eth"
    sent.capturedAt = realAt(0, hour: 16)
    guard let s = MoneyReceipt.compose(sent) else {
        print("  ✗ no receipt for a send"); exit(1)
    }
    check(s.spokenLabel.contains("minus 0.5 ETH"),
          "the sign is spelled, not left as a glyph")
    check(!s.spokenLabel.contains("−"),
          "no bare minus glyph survives into the spoken label")
    check(s.spokenLabel.contains("Sent to maria.eth"),
          "the lead and the party are spoken as one clause")
    check(s.spokenLabel.contains(s.sentence),
          "the sentence is spoken too")
    // THE POINT OF THE WHOLE CHANGE: finality is drawn as the shape of the
    // paper and nowhere else, so if it isn't in the value it reaches nobody.
    check(s.spokenValue.contains("Final"), "a torn receipt says it is final")
    check(s.spokenValue.contains("Settled"), "the stamp is spoken with it")

    // A received transfer says "plus", not nothing.
    var got = sent
    got.direction = "received"
    guard let r = MoneyReceipt.compose(got) else {
        print("  ✗ no receipt for a receive"); exit(1)
    }
    check(r.spokenLabel.contains("plus 0.5 ETH"), "a receive is spoken as plus")

    // A PENDING card authorization is the case that must never say "final" —
    // the amount can still change, and this is the half of the tear a
    // listener would otherwise never learn.
    var pending = MoneyReceipt.Facts(source: "Apple Wallet", title: "Tartine")
    pending.priceValue = 48.20
    pending.priceCurrency = "USD"
    pending.counterparty = "Tartine Bakery"
    pending.tags = ["Card", "Pending"]
    pending.capturedAt = realAt(0, hour: 14)
    guard let p = MoneyReceipt.compose(pending) else {
        print("  ✗ no receipt for a pending card charge"); exit(1)
    }
    check(p.spokenValue.contains("Not final yet"),
          "a pending authorization is NOT spoken as final")
    check(!p.spokenValue.contains("Final."),
          "…and does not contain the final phrasing at all")
    // The metaphor stays on screen: somebody listening has never seen the
    // paper, so "torn"/"flat" would describe a picture they don't have.
    check(!p.spokenValue.lowercased().contains("torn")
          && !s.spokenValue.lowercased().contains("torn"),
          "finality is spoken in words, never as the drawing's metaphor")

    // `numeric` is what `.numericText(value:)` counts between, and it may be
    // filled ONLY when the figure on screen really is that Double formatted.
    check(p.amount?.numeric == 48.20,
          "a card charge carries its Double for the roll")
    check(s.amount?.numeric == nil,
          "a chain transfer's bridge-stamped string carries no invented Double")

    // The case that actually pins the rule, and the reason the first version
    // of this block could not: a card charge whose currency CODE is missing,
    // so `currency()` refuses and the figure falls back to the amount string.
    // The two numbers are deliberately different — if `numeric` were filled
    // from `priceValue` regardless, the figure would roll toward 12.99 while
    // showing 9.40, which is a number counting to a value it is not
    // displaying, and nothing on screen would look wrong.
    var noCode = MoneyReceipt.Facts(source: "Apple Wallet", title: "Corner Shop")
    noCode.priceValue = 12.99
    noCode.priceCurrency = nil
    noCode.amount = "9.40 USD"
    noCode.counterparty = "Corner Shop"
    noCode.tags = ["Card"]
    noCode.capturedAt = realAt(0, hour: 11)
    guard let n = MoneyReceipt.compose(noCode) else {
        print("  ✗ no receipt for a card charge with no currency code"); exit(1)
    }
    check(n.amount?.number.contains("9.40") == true,
          "with no currency code the figure is the fallback string")
    check(n.amount?.numeric == nil,
          "…and carries no Double, since that is not the number it is showing")

    // A receipt with no stamped figure still speaks, leading with its title.
    var bare = MoneyReceipt.Facts(source: "Wallet", title: "Voted on Aerodrome")
    bare.capturedAt = realAt(1)
    guard let b = MoneyReceipt.compose(bare) else {
        print("  ✗ no receipt for a figureless row"); exit(1)
    }
    check(b.spokenLabel.contains("Voted on Aerodrome"),
          "a figureless receipt speaks its title")
}

// MARK: every Wallet app (prd §1341)

do {
    // Lightning, as `LightningIngest` lands it: the memo, sats, dollars.
    var ln = MoneyReceipt.Facts(source: "Lightning", title: "Coffee for Ana")
    ln.capturedAt = realAt(0)
    ln.direction = "received"
    ln.amount = "21,000 sats"
    ln.priceValue = 18.9
    ln.priceCurrency = "USD"
    guard let l = MoneyReceipt.compose(ln) else {
        print("  ✗ a Lightning payment composes nothing"); failures += 1; exit(1)
    }
    check(l.form == .record, "a payment is a record")
    check(l.party == "Coffee for Ana", "the memo names it")
    check(l.amount?.number == "+21,000" && l.amount?.unit == "sats", "the sats, signed, the unit beside")
    check(l.amount?.tone == .gain, "a payment received is a gain")
    check(l.secondary?.contains("18.90") == true, "worth the dollars it landed at")
    check(l.finality == .torn && l.stamp == .settled, "only settled payments land, so final")
    ln.direction = "sent"
    ln.title = "Paid over Lightning"
    let paid = MoneyReceipt.compose(ln)
    check(paid?.amount?.number == "−21,000", "a payment sent wears a minus")
    check(paid?.party == nil, "no memo: the direction's words are the lead, never the party")
    ln.priceCurrency = "EUR"
    check(MoneyReceipt.compose(ln)?.secondary == nil, "a figure in no dollars states no dollar worth")

    // Privy: what moved in an app's wallet.
    var pv = MoneyReceipt.Facts(source: "Privy", title: "Received 0.6974 ZORA")
    pv.capturedAt = realAt(2)
    pv.direction = "received"
    pv.amount = "0.6974 ZORA"
    pv.usd = 12.4
    pv.authorHandle = "Zora"
    let p = MoneyReceipt.compose(pv)
    check(p?.party == "Received 0.6974 ZORA", "an app wallet's move is titled by what moved (prd §1357)")
    check(p?.amount?.number == "+0.6974" && p?.amount?.unit == "ZORA", "the token amount, signed")
    check(p?.secondary?.contains("12.40") == true, "worth at landing")
    check(p?.mine == nil, "an app's wallet is not one you watch: no tucked face")

    // Splits: a proposal waiting on signatures, then one that went out.
    var sp = MoneyReceipt.Facts(source: "Splits",
                                title: "Waiting for signatures · Sent $4,500 (4,500 USDC) to Dana Ortiz")
    sp.capturedAt = realAt(1)
    sp.direction = "sent"
    sp.usd = 4500
    sp.authorHandle = "Payroll"
    sp.tags = ["Transfer", "Waiting"]
    sp.sourceRef = "splits:tx:1"
    guard let wait = MoneyReceipt.compose(sp) else {
        print("  ✗ a Splits transaction composes nothing"); failures += 1; exit(1)
    }
    check(wait.stamp == .pending && wait.finality == .open, "a proposal is pending and open")
    check(wait.party == "Sent $4,500 to Dana Ortiz", "a Splits move is titled by its sentence, the state and the restated USDC dropped (prd §1357)")
    check(wait.amount?.number.hasPrefix("−") == true, "money leaving wears a minus")
    check(wait.secondary == "Sent $4,500 (4,500 USDC) to Dana Ortiz",
          "Splits' own words under the figure, without the stage this app put first")
    check(wait.sentence.contains("Nothing has moved"), "it says nothing has moved yet")
    sp.tags = ["Transfer"]
    sp.title = "Received $12,000 (12,000 USDC) from Acme Labs"
    sp.direction = "received"
    sp.usd = 12000
    let got = MoneyReceipt.compose(sp)
    check(got?.finality == .torn && got?.amount?.number.hasPrefix("+") == true, "an executed receive tears, plus")
    sp.direction = nil
    let undirected = MoneyReceipt.compose(sp)
    check(undirected?.amount == nil && undirected?.titleFallback == sp.title,
          "no direction: no signed figure, Splits' own words lead")
    sp.direction = "received"
    sp.usd = nil
    check(MoneyReceipt.compose(sp)?.amount == nil, "no dollars displayed: no figure invented")

    // The onchain cards: no shop on the chain, so a void.
    var mm = card("MetaMask Card", tags: [], merchant: nil)
    mm.priceValue = nil
    mm.priceCurrency = nil
    mm.amount = "0.01 WETH"
    let m = MoneyReceipt.compose(mm)
    check(m?.subject == .absent(.merchantOffchain), "MetaMask Card draws the void where a shop would be")
    check(m?.amount?.unit == "WETH", "a token spend keeps its unit, never a bare number")
    check(m?.hue == .card, "and pours the card hue")
    let plasma = MoneyReceipt.compose(card("Plasma One", tags: [], merchant: nil))
    check(plasma?.subject == .absent(.merchantOffchain), "Plasma One draws the void too")
    check(plasma?.lead == "Spent with Plasma One", "the lead completes itself with the card")
}

// MARK: readings — where things stand, not what happened (prd §1341)

do {
    var ac = MoneyReceipt.Facts(source: "Acorns", title: "Checking — $191.40")
    ac.capturedAt = realAt(0)
    ac.priceValue = 191.40
    ac.priceCurrency = "USD"
    ac.sourceRef = "acorns:/v1/accounts:3"
    guard let a = MoneyReceipt.compose(ac) else {
        print("  ✗ an Acorns balance composes nothing"); failures += 1; exit(1)
    }
    check(a.form == .reading, "a balance is a reading")
    check(a.party == "Checking", "named by its account, the part before the seam")
    check(a.amount?.number.contains("191.40") == true, "the balance is the figure")
    check(a.amount?.number.hasPrefix("+") == false && a.amount?.number.hasPrefix("−") == false,
          "a balance carries no direction")
    check(a.stamp == nil, "and no stamp: nothing settled")
    check(a.sentence.hasPrefix("As of"), "it says when it was read")
    check(a.amount?.numeric == 191.40, "the stamped figure rolls")
    ac.priceValue = -12.5
    check(MoneyReceipt.compose(ac)?.amount?.number.hasPrefix("−") == true,
          "a balance below zero keeps its minus")
    // Before the bridge stamped a number: the bridge's own words, no Double.
    ac.priceValue = nil
    ac.priceCurrency = nil
    let words = MoneyReceipt.compose(ac)
    check(words?.amount?.number == "$191.40" && words?.amount?.numeric == nil,
          "with no stamped figure the title's money words stand, never parsed into a number")

    // A Rocket Money plan is a BILL (prd §1341 amended): a record, so it
    // keeps its tiles (Track), its figure, and no status.
    var rm = MoneyReceipt.Facts(source: "Rocket Money", title: "Netflix — $22.99")
    rm.priceValue = 22.99
    rm.priceCurrency = "USD"
    let r = MoneyReceipt.compose(rm)
    check(r?.form == .record && r?.party == "Netflix", "a Rocket Money plan is a bill, a record")
    check(r?.amount?.number.contains("22.99") == true, "it states what it charges")
    check(r?.stamp == nil, "and stamps nothing: a plan does not settle")
    check(!MoneyReceipt.isReading(source: "Rocket Money", ref: "rocketmoney:1"), "a bill is not a reading")

    var acct = MoneyReceipt.Facts(source: "Splits", title: "Treasury", content: "Account")
    acct.sourceRef = "splits:account:0xabc"
    let t = MoneyReceipt.compose(acct)
    check(t?.form == .reading && t?.party == "Treasury", "a Splits account is a reading")
    check(t?.amount == nil && t?.titleFallback == "Account", "no figure: it says what it is")

    // Which rows are states, never transactions.
    check(MoneyReceipt.isState(source: "Acorns", ref: "acorns:/v1/accounts:3"), "an Acorns account is a state")
    check(MoneyReceipt.isState(source: "Splits", ref: "splits:account:0xabc"), "a Splits account is a state")
    check(!MoneyReceipt.isState(source: "Splits", ref: "splits:tx:1"), "a Splits transaction is not")
    check(MoneyReceipt.isState(source: "Privy", ref: "privy:app:zora"), "an app that made you a wallet is a state")
    check(!MoneyReceipt.isState(source: "Privy", ref: "privy:tx:zora:0x1:in:eth"), "what moved in it is not")
    check(!MoneyReceipt.isState(source: "Lightning", ref: "lightning:w:h"), "a payment is not")
    check(!MoneyReceipt.isState(source: "Rocket Money", ref: "rocketmoney:1"),
          "a Rocket Money plan stays listed until it has another place")
}

if failures > 0 {
    print("\(failures) assertion(s) failed")
    exit(1)
}
print("all assertions passed")
SWIFT

echo "money-receipt-selftest: compiling MoneyReceipt + MoneyCommentary WHOLE and unmodified…"
# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 5.7x faster).
# Re-probe before trusting it again after adding mutations.
swiftc -Onone -o "$TMP/run" "$RECEIPT" "$SAYS" "$SEAM" "$TMP/main.swift" \
  || { echo "✗ the shipped receipt logic does not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$RECEIPT" "$TMP/MoneyReceipt.swift"
  cp "$SAYS" "$TMP/MoneyCommentary.swift"
  local a="$TMP/MoneyReceipt.swift" b="$TMP/MoneyCommentary.swift"
  local target
  case "$which" in
    receipt) target="$a" ;;
    says)    target="$b" ;;
  esac
  FRM="$frm" TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$a" "$b" "$SEAM" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# A receive wearing a minus. Renders perfectly; means the opposite.
mutate "the transfer sign is inverted" receipt \
  'number: (received ? "+" : "−") + parts.number,
                           unit: parts.unit,' \
  'number: (received ? "−" : "+") + parts.number,
                           unit: parts.unit,'

# Spending drawn as a gain — green over money that left.
mutate "a send is toned as a gain" receipt \
  'tone: received ? .gain : .plain),
            secondary: worthLine(f.usd),
            sentence: transferSentence' \
  'tone: .gain),
            secondary: worthLine(f.usd),
            sentence: transferSentence'

# A pending authorization claiming finality over an amount that can change.
mutate "a pending card charge is torn off" receipt \
  'finality: pending ? .open : .torn,
            hue: hue)' \
  'finality: .torn,
            hue: hue)'

# A deposit still in screening drawn as finished — i.e. as withdrawable money.
mutate "a screening deposit reads as final" receipt \
  'finality: cleared ? .torn : .open,
            hue: .shield)' \
  'finality: .torn,
            hue: .shield)'

# An unshield stamped "Shielded" — the opposite of what happened (prd §83).
mutate "an unshield is stamped shielded" receipt \
  'stamp: unshield ? .unshielded : .shielded,' \
  'stamp: .shielded,'

# A Safe proposal stamped settled before anything moved (prd §83).
mutate "a waiting Safe proposal is stamped settled" receipt \
  ': yourTurn ? .yourTurn : .waiting,' \
  ': yourTurn ? .yourTurn : .settled,'

# A figureless wallet row defaulting to settled (prd §83).
mutate "a figureless trade is stamped settled" receipt \
  'stamp: risk ? .openPosition
                : (!approval' \
  'stamp: risk ? .openPosition
                : true ? .settled : (!approval'

# A deadline drawn as a receipt.
mutate "a deadline ref composes a receipt" receipt \
  'guard sources.contains(f.source), !isAhead(ref: f.sourceRef) else { return nil }' \
  'guard sources.contains(f.source) else { return nil }'

# A phishing domain promoted into the currency slot.
mutate "the unit rule stops checking for letters" receipt \
  'last.allSatisfy({ $0.isLetter || $0.isNumber })' \
  'true'

# A weekday named for a day that has not happened.
mutate "a future date is given a weekday" receipt \
  'if days >= 2, days <= 6 {' \
  'if days <= 6 {'

# Bitcoin reaching for a market it does not read.
# Anchored on the LINE AFTER it, not on the sentence itself (2026-08-12).
# A mutation is by nature an exact source edit, so this used to pin Bitcoin's
# whole no-fiat sentence — and a copy pass that rewrote it ("Casberi reads the
# chain here…" → "Read from the chain…") stopped the mutation applying, which
# `set -e` turned into a silent exit with no ✗ at all. `sentence:
# bitcoinSentence(f),` is structure rather than prose: it names a function, so
# it only moves if the composition really moves, and inserting the fiat line
# above it is the same inversion the old edit made.
mutate "bitcoin claims a fiat figure" receipt \
  'sentence: bitcoinSentence(f),' \
  'secondary: worthLine(f.usd), sentence: bitcoinSentence(f),'

# "Mostly them sending you" over a 3–2 split.
mutate "the lopsided guard is dropped" says \
  'if received * 3 >= signed.count * 2 {' \
  'if received >= 1 {'

# One outlier redefining "usually".
mutate "typical becomes the mean" says \
  'let sorted = values.sorted()
        let mid = sorted.count / 2' \
  'let sorted = [values.reduce(0, +) / Double(values.count)]
        let mid = sorted.count / 2'

# A pair reported as a pattern.
mutate "two transfers earn a history card" says \
  'guard signed.count >= 3 else { return nil }' \
  'guard signed.count >= 1 else { return nil }'

# "The biggest yet" as decoration rather than a checked claim.
mutate "biggest-yet stops being checked" says \
  'signed.dropLast().allSatisfy({ $0.0 < mine })' \
  'true'

# A rate divided out of a leg that could not be read.
mutate "a zero leg is divided by" says \
  'outValue > 0, inValue > 0 else { return nil }' \
  'outValue >= 0, inValue >= 0 else { return nil }'

echo ""

# --- the §369 amendment's own mutations -------------------------------------
# Each is a change that leaves the receipt looking EXACTLY as it does now and
# makes it lie, or go silent, to somebody who cannot see it.

# The tear stops being spoken. This is the whole change reverting: the card
# still draws its scalloped edge, every assertion above still passes, and the
# one fact only the SHAPE carries becomes unreachable by ear again.
mutate "finality drops out of the spoken value" receipt \
  'let state = finality == .torn
            ? String(localized: "Final")
            : String(localized: "Not final yet")' \
  'let state = ""'

# A pending authorization spoken as final — the listening half of the mutation
# already covered visually above ("a pending card charge is torn off").
mutate "everything is spoken as final" receipt \
  '? String(localized: "Final")
            : String(localized: "Not final yet")' \
  '? String(localized: "Final")
            : String(localized: "Final")'

# The sign left as a glyph. Reads correctly on screen and is exactly the
# character a screen reader may skip, so "minus 0.5" becomes "0.5" — a send
# announced as a receipt.
mutate "the spoken sign stops being spelled" receipt \
  'said = String(localized: "minus ") + said.dropFirst()' \
  'said = String(said.dropFirst())'

# `numeric` filled from the fallback string's Double. The figure would then
# count toward a value it is not showing, which is the one thing this field
# was added carefully enough to avoid.
mutate "the roll's value is filled even when the figure isn't that Double" receipt \
  'numeric: priced == nil ? nil : f.priceValue.map(abs)' \
  'numeric: f.priceValue.map(abs)'

# --- prd §1341's own mutations ----------------------------------------------
echo ""

# A Lightning payment received drawn as money that left.
mutate "a Lightning receive wears a minus" receipt \
  'number: (received ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            secondary: worthLine(f.priceCurrency == "USD" ? f.priceValue : nil),' \
  'number: (received ? "−" : "+") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            secondary: worthLine(f.priceCurrency == "USD" ? f.priceValue : nil),'

# A balance drawn as a record: tiles, history and a status over a state.
mutate "a reading is composed as a record" receipt \
  'hue: .neutral,
            form: .reading)' \
  'hue: .neutral,
            form: .record)'

# An Acorns balance listed under Transactions again.
mutate "an Acorns account stops being a state" receipt \
  'source == "Acorns"
            || (source == "Splits"' \
  'source == "Acorns!"
            || (source == "Splits"'

# A Splits proposal claiming finality before anyone signed.
mutate "a waiting Splits proposal is torn" receipt \
  'finality: waiting ? .open : .torn,
            hue: .wallet)' \
  'finality: .torn,
            hue: .wallet)'

# A WETH spend printed as a bare number.
mutate "a token card spend drops its unit" receipt \
  'unit: priced == nil ? fallback.unit : nil,' \
  'unit: nil,'

echo "money-receipt-selftest: OK"
