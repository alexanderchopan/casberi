#!/bin/zsh
# A money row's name fits its one line (prd §1414), compiled AS SHIPPED:
# `Model/WalletRowWords.swift` is Foundation-only, so this compiles it whole
# beside `TitleSeam`.
#
# Every failure reads as a cut row or a wrong word:
#   • "Swapped 0.0136 ETH → 32.55 USDC on…" — the sentence drawn as the name
#   • a swap's figure on the wrong side, or its venue lost
#   • "1 of 2 signatures collected on deposit e t h" — the count as the name,
#     the act split on every capital
#   • "Fully signed" as a name, with the act cut on the line
#   • a title in another shape rewritten (a transfer, a deposit, a closing row)
# and the drift that no build sees: the bridges rewording the sentences this
# reads, or the row no longer reading the rule.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/WalletRowWords.swift"
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
SAFE="Casberi/Casberi/Model/SafeBridge.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
SOL="Casberi/Casberi/Model/SolanaActivity.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
typealias W = WalletRowWords.Words

// A swap: the pair and the venue as the name, in on the right, out on the line.
check(WalletRowWords.read("Swapped 0.0136 ETH → 32.55 USDC on Uniswap")
      == W(name: "ETH → USDC on Uniswap", figure: "+32.55 USDC", clause: "−0.0136 ETH"),
      "an EVM swap reads pair · venue, in, out")
check(WalletRowWords.read("Swapped 1,240 USDC → 0.4962 ETH on Uniswap")
      == W(name: "USDC → ETH on Uniswap", figure: "+0.4962 ETH", clause: "−1,240 USDC"),
      "a grouped amount stays whole")
check(WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC")
      == W(name: "ETH → USDC", figure: "+1,240 USDC", clause: "−0.5 ETH"),
      "no venue, no ' on '")
check(WalletRowWords.read("Swapped ETH → USDC")
      == W(name: "ETH → USDC"),
      "bare symbols: no figure, no clause")
check(WalletRowWords.read("Swapped 2 SOL → 310 USDC on Jupiter")
      == W(name: "SOL → USDC on Jupiter", figure: "+310 USDC", clause: "−2 SOL"),
      "a Solana swap reads the same")
check(WalletRowWords.read("Swapped 0.05 ETH → 160 ÚЅDС")?.figure == "+160 ÚЅDС",
      "a look-alike symbol keeps its figure; the row's flag picks the ink")
check(WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC — on Base")
      == W(name: "ETH → USDC", figure: "+1,240 USDC", clause: "−0.5 ETH", qualifier: "on Base"),
      "a seam after a swap rides as the qualifier")

// A Safe row: the act is the name, the count the line.
check(WalletRowWords.read("1 of 2 signatures collected on deposit ETH — your signature is needed")
      == W(name: "Deposit ETH", clause: "1 of 2 signed", qualifier: "your signature is needed"),
      "a Safe row names the act, counts on the line, keeps the clause for the Needs-you trim")
check(WalletRowWords.read("2 of 3 signatures collected on a transfer of 1,500 USDC to payroll.eth — waiting on others")
      == W(name: "Transfer of 1,500 USDC to payroll.eth", clause: "2 of 3 signed", qualifier: "waiting on others"),
      "the article goes, the first letter stands up")
check(WalletRowWords.read("1 of 3 signatures collected on an approval for Uniswap to spend 2,000 USDC")
      == W(name: "Approval for Uniswap to spend 2,000 USDC", clause: "1 of 3 signed"),
      "'an' goes too; no seam, no qualifier")
check(WalletRowWords.read("2 of 3 signatures collected on “Supply 2 WETH as collateral”")
      == W(name: "“Supply 2 WETH as collateral”", clause: "2 of 3 signed"),
      "a quoted act is left as written")
check(WalletRowWords.read("Fully signed — a batch of 3 transfers is ready to execute")
      == W(name: "Batch of 3 transfers", clause: "Fully signed · ready to execute"),
      "a fully signed row names the act")
check(WalletRowWords.read("Fully signed — a rejection is behind 2 earlier transactions")
      == W(name: "Rejection", clause: "Fully signed · behind 2 earlier transactions"),
      "a blocked row says what it is behind")

// A move between your own accounts (prd §1550): the accounts as the name,
// the amount on the right, unsigned.
check(WalletRowWords.read("Moved 0.0002 ETH · accountless.eth → You")
      == W(name: "accountless.eth → You", figure: "0.0002 ETH", stayed: true),
      "a move names the two accounts, the amount on the right")
check(WalletRowWords.read("Moved 14.22 DAI · You → Cold")
      == W(name: "You → Cold", figure: "14.22 DAI", stayed: true),
      "either direction reads the same")
check(WalletRowWords.read("Moved ETH · Main → Cold")
      == W(name: "Main → Cold", clause: "ETH", stayed: true),
      "no amount: the symbol goes on the line")
check(WalletRowWords.read("Moved to Archive")  == nil, "a Moved with no accounts is left alone")

// Anything else is nil: the row keeps its seam.
for other in ["Received 0.4 ETH from vitalik.eth", "Deposited 0.5 ETH into Aave",
              "Executed after 2h — a transfer went through",
              "Replaced — a transfer never executed; a rival transaction went through at the same nonce instead",
              "Fully signed", "x of y signatures collected on z", "Swapped nothing",
              "Approved Uniswap to manage all Doodles", "Rent — Needs attention · later"] {
    check(WalletRowWords.read(other) == nil, "left alone: \(other)")
}

// An ABI method as words, a run of capitals kept whole.
let methods = ["multiSend": "multi send", "changeThreshold": "change threshold",
               "depositETH": "deposit ETH", "swapExactETHForTokens": "swap exact ETH for tokens",
               "execTransaction": "exec transaction", "ETH": "ETH", "transfer": "transfer",
               "Deposit": "deposit", "": ""]
for (method, words) in methods {
    check(WalletRowWords.method(method) == words, "\(method) → \(words), not \(WalletRowWords.method(method))")
}

if failures > 0 { print("\(failures) failed"); exit(1) }
SWIFT

swiftc -O -o "$work/t" "$SRC" "$SEAM" "$work/main.swift" 2>"$work/err" || { cat "$work/err"; fail "wallet-row-words did not compile"; }
"$work/t" || fail "wallet-row-words cases failed"

# Mutations: the harness must catch the shipped defects. Each builds a
# mutated copy and expects the cases to FAIL.
mutate() {
    local what="$1" from="$2" to="$3"
    python3 - "$SRC" "$work/mut.swift" "$from" "$to" <<'PY' || { echo STALE; return 1; }
import sys
src, dst, a, b = sys.argv[1:]
s = open(src).read()
assert s.count(a) == 1, f"mutation anchor not found once: {a!r}"
open(dst, "w").write(s.replace(a, b))
PY
    swiftc -O -o "$work/m" "$work/mut.swift" "$SEAM" "$work/main.swift" 2>"$work/merr" || { cat "$work/merr"; fail "mutation '$what' did not compile"; }
    if "$work/m" >/dev/null 2>&1; then fail "mutation '$what' passed — the harness catches nothing there"; fi
}
mutate "split on every capital (the shipped 'deposit e t h')" \
    'let acronym = (prevUpper || nextUpper) && !nextLower' \
    'let acronym = false'
mutate "a swap keeps its sentence" \
    'swap(title) ?? safe(title)' \
    'safe(title)'
mutate "the incoming leg lands on the line" \
    'figure: inn.amount.map { "+\($0) \(inn.symbol)" },' \
    'figure: nil,'
mutate "a move keeps its sentence" \
    'swap(title) ?? safe(title) ?? moved(title)' \
    'swap(title) ?? safe(title)'
mutate "a move's amount signed and green" \
    '                     stayed: true)' \
    '                     stayed: false)'
mutate "the article stays" \
    'act = String(act.dropFirst(article.count))' \
    'act = String(act)'

# The shapes this reads are the ones the bridges write.
grep -q 'let head = amount.isEmpty ? "Moved \\(asset)" : "Moved \\(amount) \\(asset)"' "$INGEST" && grep -q 'title = "\\(head) · \\(from) → \\(to)"' "$INGEST" \
    || fail "WalletIngest no longer titles an own move \"Moved <amount> <asset> · <from> → <to>\" — WalletRowWords.moved must follow it"
grep -q 'let head = "Swapped \\(out) → \\(inn)"' "$INGEST" \
    || fail "WalletIngest no longer titles a swap \"Swapped <out> → <in>\" — WalletRowWords.swap must follow it"
grep -q 'venue.map { "\\(head) on \\($0)" }' "$INGEST" \
    || fail "WalletIngest no longer appends the venue as \" on <venue>\""
grep -q 'Story(title: "Swapped \\(a) → \\(b)\\(tail)"' "$SOL" \
    || fail "SolanaActivity no longer titles a swap \"Swapped <out> → <in>\""
grep -q 'signatures collected on \\(description)")' "$SAFE" \
    || fail "SafeBridge no longer writes \"N of M signatures collected on <act>\" — WalletRowWords.safe must follow it"
grep -q 'String(localized: "Fully signed — \\(description) is ready to execute")' "$SAFE" \
    || fail "SafeBridge no longer writes \"Fully signed — <act> is ready to execute\""
grep -q 'is behind \\(blocked) earlier transactions")' "$SAFE" \
    || fail "SafeBridge no longer writes \"is behind N earlier transactions\""
grep -q 'WalletRowWords.method(method)' "$SAFE" \
    || fail "SafeBridge.humanize no longer reads WalletRowWords.method — 'deposit e t h' is back"

# The row reads the rule, in the money column only, and draws every slot.
grep -q 'let words = moneyColumn ? WalletRowWords.read(titleText) : nil' "$ROWS" \
    || fail "BandRow no longer reads WalletRowWords in the money column"
grep -q 'words.map { (name: $0.name, line: $0.qualifier) } ?? TitleSeam.split(titleText)' "$ROWS" \
    || fail "BandRow no longer takes the words' name and qualifier over the seam"
grep -q 'let lead = \[words?.clause, said\].compactMap { $0 }' "$ROWS" \
    || fail "BandRow no longer leads the line with the words' clause"
grep -q 'else if let figure = words?.figure {' "$ROWS" \
    || fail "BandRow no longer draws a swap's incoming leg on the right"
grep -q 'foregroundStyle(words?.stayed == true || thing.hasSecurityFlag("symbol") ? DS.textPrimary : DS.confirmInk)' "$ROWS" \
    || fail "BandRow draws a move between your own accounts in the received green (prd §1550)"

print "✓ wallet-row-words self-test passed"
