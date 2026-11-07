#!/bin/zsh
# Aztec words self-test (prd §1711 items 1, 2) — `AztecWords` and
# `AztecFeeWords`: an Aztec transaction's Activity title (the move with no
# verb, what Aztec charged after the one seam), which kinds wear the
# eye-slash, and the approval sheet's fee line (who pays, about how much, and
# amber when your Fee Juice holds less).
#
# Each failure renders as a working row or sheet: a sponsor's fee said to come
# from your Fee Juice, a fee in eighteen places, a short balance said to be
# enough, gas or an app's call said to be private.
set -euo pipefail
cd "$(dirname "$0")/.."

WORDS="Casberi/Casberi/Model/Aztec/AztecWords.swift"
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
TAIL="Casberi/Shared/AddressTail.swift"
ACTIVITY="Casberi/Casberi/Model/Aztec/AztecActivity.swift"
ENGINE="Casberi/Casberi/Model/Aztec/AztecEngine.swift"
BROWSER="Casberi/Casberi/Screens/AztecBrowser.swift"
for f in "$WORDS" "$SEAM" "$TAIL" "$ACTIVITY" "$ENGINE" "$BROWSER"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/aztec-words-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }
let fee = "310000000000000000"     // 0.31 Fee Juice
let tiny = "4000000000000000"      // 0.004
let them = "0x" + String(repeating: "1", count: 60) + "a91c"
let eth = "0x71c7656ec7ab88b098defb751b7401b5f6d849a2"

// The fee, at two places at most.
check(AztecWords.feeFigure(fee) == "0.31 Fee Juice", "a fee is not two places")
check(AztecWords.feeFigure("1234567890000000000") == "1.23 Fee Juice", "a fee kept its eighteen places")
check(AztecWords.feeFigure(tiny) == "under 0.01 Fee Juice", "a fee below a hundredth read as nothing")
check(AztecWords.feeFigure("0") == "no Fee Juice" && AztecWords.feeFigure("x") == "no Fee Juice", "no fee read as one")

// The titles: no verb, the fee after the seam.
check(AztecWords.title(.gas, figure: "30 Fee Juice", to: nil, calls: [], fee: fee) == "30 Fee Juice as gas — 0.31 Fee Juice fee", "the gas row drifted")
check(AztecWords.title(.arrival, figure: "25 USDC", to: nil, calls: [], fee: nil) == "25 USDC to your private account", "the arrival row drifted")
check(AztecWords.title(.send, figure: "25 USDC", to: them, calls: [], fee: nil) == "25 USDC to ...a91c on Aztec", "the private send row drifted")
check(AztecWords.title(.exit, figure: "25 USDC", to: eth, calls: [], fee: nil) == "25 USDC to ...49a2 on Ethereum", "the exit row drifted")
check(AztecWords.title(.app, figure: "", to: "nemi.fi", calls: ["swap_private"], fee: nil) == "Swap private on nemi.fi", "the app row drifted")
check(AztecWords.title(.app, figure: "", to: "nemi.fi", calls: ["swap", "transfer"], fee: nil) == "Swap and 1 more on nemi.fi", "an app's second call was lost")
check(AztecWords.title(.app, figure: "", to: "nemi.fi", calls: [], fee: nil) == "A transaction on nemi.fi", "an app's row with no call named nothing")
check(!AztecWords.title(.send, figure: "25 USDC", to: them, calls: [], fee: fee).contains(" · "), "a title used a second seam")

// Which kinds are private.
check([AztecTxKind.arrival, .send, .exit].allSatisfy(\.isPrivate), "a private move lost its eye-slash")
check(!AztecTxKind.gas.isPrivate && !AztecTxKind.app.isPrivate, "gas or an app's call was said to be private")

// The sheet's fee line.
typealias F = AztecFeeWords
check(F.line(units: fee, payer: .you, held: "2500000000000000000") == "About 0.31 Fee Juice, from your Fee Juice.", "the fee line drifted")
check(!F.short(units: fee, payer: .you, held: "2500000000000000000"), "enough Fee Juice read as short")
check(F.short(units: fee, payer: .you, held: "100000000000000000"), "a short balance read as enough")
check(F.line(units: fee, payer: .you, held: "100000000000000000") == "About 0.31 Fee Juice. Your Fee Juice holds 0.1 Fee Juice: not enough.",
      "a short balance was not said")
check(F.line(units: fee, payer: .you, held: "0") == "About 0.31 Fee Juice. You have no Fee Juice to pay it.", "an empty balance was not said")
check(F.line(units: fee, payer: .app, held: "0") == "The app pays the fee." && !F.short(units: fee, payer: .app, held: "0"),
      "a sponsor's fee was said to be yours")
check(F.line(units: fee, payer: .claim, held: "0") == "About 0.31 Fee Juice, from the Fee Juice it claims." && !F.short(units: fee, payer: .claim, held: "0"),
      "a claim paying its own fee read as short")
check(F.line(units: nil, payer: .you, held: nil) == "Paid from your Fee Juice. Casberi could not price it.", "an unpriced fee was made up")
check(!F.short(units: fee, payer: .you, held: nil), "an unread balance was said to be short")

print(bad == 0 ? "aztec-words self-test: \(ran) checks ok" : "aztec-words self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$WORDS" "$SEAM" "$TAIL" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ AztecWords.swift does not compile with Foundation, TitleSeam and AddressTail alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring.
grep -q 'case "engineSent":' "$ENGINE" && grep -q 'AztecActivity.record(.init(hash: hash, kind: .app' "$ENGINE" \
  || { echo "✗ an app's Aztec send no longer lands in Activity"; exit 1; }
grep -q 'Text(verbatim: AztecFeeWords.line(units: fee.units, payer: fee.payer, held: held))' "$BROWSER" \
  || { echo "✗ the approval sheet no longer says the fee"; exit 1; }
grep -q 'return AztecWords.title(tx.kind, figure: figure, to: tx.to, calls: tx.calls ?? \[\], fee: tx.fee)' "$ACTIVITY" \
  || { echo "✗ an Activity row is no longer titled by AztecWords"; exit 1; }
for f in Casberi/Casberi/Model/Aztec/AztecGas.swift Casberi/Casberi/Model/Aztec/ShieldBridge.swift Casberi/Casberi/Screens/MoveAztecPrivate.swift; do
  grep -q 'AztecActivity.record(' "$f" || { echo "✗ $f sends on Aztec without a record in Activity"; exit 1; }
done
true
