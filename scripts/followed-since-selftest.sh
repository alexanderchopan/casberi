#!/bin/zsh
# What a wallet you follow did since you last looked (prd §1969), compiled AS
# SHIPPED: `Model/FollowedSince.swift` is Foundation-only, so this compiles it
# whole beside `WalletRowWords` and `TitleSeam`.
#
# Every failure reads as a calm, wrong line on Following:
#   • "Deposited 480,000 USDC into Morpho" — the amount the row already says
#   • "Settled of card spending" — a money figure dropped as if an amount
#   • one swap named three times, or the fourth move silently lost (no "N more")
#   • "Nothing new" over moves you have not seen, or news over ones you have
#   • a change since you looked read off the wrong sample
# and the drift no build sees: All counting a wallet you follow again, or the
# switch coming back.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/FollowedSince.swift"
WORDS="Casberi/Casberi/Model/WalletRowWords.swift"
MARK="Casberi/Casberi/Model/WalletActionMark.swift"
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
NEWS="Casberi/Casberi/Model/FollowedNews.swift"
DERIV="Casberi/Casberi/Screens/FeedScreen+Derivations.swift"
TILES="Casberi/Casberi/Screens/FeedScreen+WalletTiles.swift"
SWITCH="Casberi/Casberi/Screens/WalletWhoseSwitch.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func m(_ title: String, _ minutes: Double) -> FollowedSince.Move {
    .init(title: title, at: t0.addingTimeInterval(minutes * 60))
}

// One move each, in a few words.
check(FollowedSince.phrase("Swapped 0.5 ETH → 1,240 USDC on Uniswap") == "Swapped ETH for USDC",
      "a swap is the pair, its amounts left to the row")
check(FollowedSince.phrase("Deposited 480,000 USDC into Morpho") == "Deposited USDC into Morpho",
      "a grouped amount goes")
check(FollowedSince.phrase("Received 0.5 ETH from Mom") == "Received ETH from Mom",
      "a receive keeps who it came from")
check(FollowedSince.phrase("Sent 12 USDC") == "Sent USDC", "a bare send keeps its token")
check(FollowedSince.phrase("Settled $246.31 of card spending") == "Settled $246.31 of card spending",
      "a money figure is the sentence's object and stays")
check(FollowedSince.phrase("Moved 2 ETH · Main → Cold") == "Moved ETH",
      "a move between their own accounts is one phrase")
check(FollowedSince.phrase("Minted CryptoPunks #402") == "Minted CryptoPunks #402",
      "a word after the verb that is not a number stays")
check(FollowedSince.phrase("") == nil, "an empty title says nothing")

// The line: newest first, each phrase once, three then "N more".
check(FollowedSince.line([]) == nil, "nothing since: no line")
check(FollowedSince.line([m("Sent 1 ETH", 1), m("Swapped 1 ETH → 3,000 USDC", 2)])
      == "Swapped ETH for USDC · Sent ETH", "newest first")
check(FollowedSince.line([m("Sent 1 ETH", 1), m("Sent 2 ETH", 2), m("Sent 3 ETH", 3)]) == "Sent ETH",
      "one phrase said once")
check(FollowedSince.line([m("Sent 1 ETH", 1), m("Received 2 USDC", 2), m("Minted Foo #1", 3),
                          m("Claimed 4 CRV from Curve", 4), m("Withdrew 5 DAI from Aave", 5)])
      == "Withdrew DAI from Aave · Claimed CRV from Curve · Minted Foo #1 · 2 more",
      "three, then how many more")

// Since when, in words.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = t0
check(FollowedSince.since(now.addingTimeInterval(-3600), now: now, calendar: cal) == "earlier today", "an hour ago is today")
check(FollowedSince.since(now.addingTimeInterval(-86_400), now: now, calendar: cal) == "yesterday", "a day back")
check(FollowedSince.nothingNew(now.addingTimeInterval(-86_400), now: now, calendar: cal) == "Nothing new since yesterday",
      "the quiet line")

// What its money did since you looked.
let s: [(at: Date, usd: Double)] = [(t0, 100), (t0.addingTimeInterval(60), 120), (t0.addingTimeInterval(120), 90)]
check(FollowedSince.change(s, since: t0.addingTimeInterval(30)) == -10, "the newest less the last at or before the look")
check(FollowedSince.change(s, since: t0.addingTimeInterval(-30)) == nil, "no sample before the look: no change")
check(FollowedSince.change(s, since: t0.addingTimeInterval(200)) == nil, "nothing after the look: no change")

if failures > 0 { print("\(failures) failed"); exit(1) }
SWIFT

swiftc -O -o "$work/t" "$SRC" "$WORDS" "$MARK" "$SEAM" "$work/main.swift" 2>"$work/err" || { cat "$work/err"; fail "followed-since did not compile"; }
"$work/t" || fail "followed-since cases failed"

# A harness that cannot fail certifies nothing: each mutation breaks one rule
# in a copy and expects the cases to FAIL.
mutate() {
    local what="$1" from="$2" to="$3"
    python3 - "$SRC" "$work/mut.swift" "$from" "$to" <<'PY' || { echo STALE; return 1; }
import sys
src, out, a, b = sys.argv[1:]
s = open(src).read()
assert s.count(a) == 1, f"mutation anchor not found once: {a!r}"
open(out, "w").write(s.replace(a, b))
PY
    swiftc -O -o "$work/m" "$work/mut.swift" "$WORDS" "$MARK" "$SEAM" "$work/main.swift" 2>"$work/merr" || { cat "$work/merr"; fail "mutation '$what' did not compile"; }
    if "$work/m" >/dev/null 2>&1; then fail "mutation '$what' passed — the harness catches nothing there"; fi
}
mutate "the amount stays in the phrase" 'words.remove(at: 1)' '_ = words'
mutate "a money figure dropped (\"Settled of card spending\")" 'CharacterSet(charactersIn: "~≈<>")' 'CharacterSet(charactersIn: "$~≈<>")'
mutate "a phrase said twice" '!said.contains(phrase)' 'true'
mutate "the fourth move lost" 'if extra > 0 {' 'if false {'
mutate "oldest first" 'sorted(by: { $0.at > $1.at })' 'sorted(by: { $0.at < $1.at })'
mutate "the change read off the first sample" 'last(where: { $0.at <= date })' 'first(where: { $0.at <= date })'

# The rule the screens keep (prd §1969): All is your money, no switch.
grep -q 'FollowedNews.isFollowedRow(thing, followed: leftOut)' "$DERIV" \
    || fail "the Feed and Activity count a wallet you follow again (FeedScreen+Derivations)"
grep -q 'var walletExcluded' "$TILES" || fail "All no longer leaves out the wallets you follow"
grep -q 'if let excluding { groups = groups.filter' "$INGEST" || fail "the holdings read counts a wallet you follow on All"
grep -q 'static var offered: \[WalletWhose\] { \[\] }' "$SWITCH" || fail "the Yours · Following · All switch is back"
grep -q 'func markSeen' "$NEWS" || fail "nothing marks a followed wallet looked at"

print "✓ followed-since self-test passed"
