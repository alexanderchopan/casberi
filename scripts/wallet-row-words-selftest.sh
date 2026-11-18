#!/bin/zsh
# A money row's name fits its one line (prd §1414), compiled AS SHIPPED:
# `Model/WalletRowWords.swift` is Foundation-only, so this compiles it whole
# beside `TitleSeam`.
#
# Every failure reads as a cut row or a wrong word:
#   • "Swapped 0.0136 ETH → 32.55 USDC on…" — the sentence drawn as the name;
#     the row reads "Swapped 0.0136 ETH for 32.55 USDC" (prd §1805, verb
#     first as a send's row; §1555 had left it to the glyph), venue on the line
#   • a swap's venue lost, or its verb gone from VoiceOver
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

// A swap: the trade as it reads, "for" for the arrow, its verb left to the
// glyph and kept for VoiceOver, the venue on the line (prd §1555).
check(WalletRowWords.read("Swapped 0.0136 ETH → 32.55 USDC on Uniswap")
      == W(name: "Swapped ETH for USDC", clause: "0.0136 ETH → 32.55 USDC on Uniswap",
           spoken: "Swapped 0.0136 ETH for 32.55 USDC on Uniswap"),
      "an EVM swap names the pair, the amounts and venue on the line, the whole sentence spoken (prd §1863)")
check(WalletRowWords.read("Swapped 1,240 USDC → 0.4962 ETH on Uniswap")?.clause == "1,240 USDC → 0.4962 ETH on Uniswap",
      "a grouped amount stays whole")
check(WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC")
      == W(name: "Swapped ETH for USDC", clause: "0.5 ETH → 1,240 USDC", spoken: "Swapped 0.5 ETH for 1,240 USDC"),
      "no venue: the amounts alone on the line")
check(WalletRowWords.read("Swapped ETH → USDC")
      == W(name: "Swapped ETH for USDC", spoken: "Swapped ETH for USDC"),
      "bare symbols, no line clause")
check(WalletRowWords.read("Swapped 2 SOL → 310 USDC on Jupiter")
      == W(name: "Swapped SOL for USDC", clause: "2 SOL → 310 USDC on Jupiter", spoken: "Swapped 2 SOL for 310 USDC on Jupiter"),
      "a Solana swap reads the same")
check(WalletRowWords.read("Swapped 0.05 ETH → 160 ÚЅDС")?.name == "Swapped ETH for ÚЅDС",
      "a look-alike symbol is drawn as it is; the row's flag picks the ink")
check(WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC — on Base")
      == W(name: "Swapped ETH for USDC", clause: "0.5 ETH → 1,240 USDC", qualifier: "on Base",
           spoken: "Swapped 0.5 ETH for 1,240 USDC"),
      "a seam after a swap rides as the qualifier")
check(WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC")?.name.hasPrefix("Swapped ") == true
      && WalletRowWords.read("Swapped 0.5 ETH → 1,240 USDC")?.name.contains("→") == false,
      "the drawn name leads with its verb and carries no arrow")

// A Wise row (prd §1863): the stage and amounts are the name, the reference
// the line; "Needs attention · " stays for the Needs-you trim.
check(WalletRowWords.read("Sending · £120.00 → €141.00 · Invoice 204")
      == W(name: "Sending £120.00 → €141.00", clause: "Invoice 204", spoken: "Sending · £120.00 → €141.00 · Invoice 204"),
      "a Wise send names its amounts, the reference on the line")
check(WalletRowWords.read("Sent · £50.00")
      == W(name: "Sent £50.00", spoken: "Sent · £50.00"),
      "no reference, no line clause")
check(WalletRowWords.read("Needs attention · £200.00 → €235.00 · Deposit")?.name == "Needs attention · £200.00 → €235.00",
      "a stuck transfer keeps the seam the Needs-you trim reads")
check(WalletRowWords.read("Sending · love") == nil, "a word is not an amount")

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

// A card's row says its amount once (prd §1810): the card is the name, the
// sentence's figure stands on the right in the primary ink.
check(WalletRowWords.read("Spent $12.40 with MetaMask Card")
      == W(name: "MetaMask Card", figure: "$12.40", spoken: "Spent $12.40 with MetaMask Card", spent: true),
      "a card spend names the card, the figure on the right")
check(WalletRowWords.read("Spent $4.20 with ether.fi Cash — on credit")
      == W(name: "ether.fi Cash", figure: "$4.20", qualifier: "on credit",
           spoken: "Spent $4.20 with ether.fi Cash", spent: true),
      "the seam rides as the qualifier")
check(WalletRowWords.read("Settled $246.31 of card spending")
      == W(name: "Card spending", figure: "$246.31", spoken: "Settled $246.31 of card spending", spent: true),
      "a settlement names what it settled")
check(WalletRowWords.read("Spent with care") == nil, "no figure, no rewrite")
check(WalletRowWords.read("Spent a lot with Visa") == nil, "a word is not a figure")

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
mutate "the verb leaves the drawn name (prd §1805)" \
    'let name = "Swapped \(out.symbol) for \(inn.symbol)"' \
    'let name = "\(out.symbol) for \(inn.symbol)"'
mutate "the amounts back in the name, the row cut again (prd §1863)" \
    'let name = "Swapped \(out.symbol) for \(inn.symbol)"' \
    'let name = "Swapped \(Self.amounted(out)) for \(Self.amounted(inn))"'
mutate "VoiceOver loses the amounts" \
    'spoken: said + (on.map { " on \($0)" } ?? ""))' \
    'spoken: name)'
mutate "the amounts and venue leave the line" \
    '                     clause: clause,' \
    '                     clause: nil,'
mutate "a Wise row keeps its sentence (prd §1863)" \
    '?? spent(title) ?? wise(title)' \
    '?? spent(title)'
mutate "a stuck Wise row loses the seam the Needs-you trim reads" \
    'let name = stage == "Needs attention" ? lead + amounts : "\(stage) \(amounts)"' \
    'let name = "\(stage) \(amounts)"'
mutate "a move keeps its sentence" \
    'swap(title) ?? safe(title) ?? moved(title)' \
    'swap(title) ?? safe(title)'
mutate "a move's amount signed and green" \
    '                     stayed: true)' \
    '                     stayed: false)'
mutate "a card spend keeps its sentence and says the amount twice (prd §1810)" \
    'swap(title) ?? safe(title) ?? moved(title) ?? spent(title) ?? wise(title)' \
    'swap(title) ?? safe(title) ?? moved(title) ?? wise(title)'
mutate "a card's figure in the received green" \
    'spoken: seam.name, spent: true)' \
    'spoken: seam.name, spent: false)'
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
grep -q 'Needs attention · \\(amounts)\\(reference)' "Casberi/Casberi/Model/WiseBridge.swift" && grep -q 'Sending · \\(amounts)\\(reference)' "Casberi/Casberi/Model/WiseBridge.swift" \
    || fail "WiseBridge no longer titles a transfer \"<Stage> · <amounts> · <reference>\" — WalletRowWords.wise must follow it"
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
grep -q 'if let figure = words?.figure {' "$ROWS" \
    || fail "BandRow no longer draws the words' figure on the right"
grep -q '?? words?.spoken' "$ROWS" \
    || fail "BandRow no longer speaks a swap's verb (prd §1555)"
grep -q 'foregroundStyle(words?.stayed == true || words?.spent == true || thing.hasSecurityFlag("symbol") ? DS.textPrimary : DS.confirmInk)' "$ROWS" \
    || fail "BandRow draws a move between your own accounts in the received green (prd §1550)"

print "✓ wallet-row-words self-test passed"
