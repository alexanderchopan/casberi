#!/bin/zsh
# The monthly recovery check (prd §1515, Phase 4 of
# docs/signing-safety-spec.md) — `YourAccountRecoveryCheck`: the due rule
# (thirty days from the last good check, else from the key's making, now
# when neither is known), each network's standing, and the sentence (green
# only when the key is here, it signed, and no network the account is on
# refuses it; red naming the first failure). Then the wiring: the check
# never asks a chain's isValidSignature (with the spend limit one key alone
# reads as a failure, §1456), stores only a good check's date, and the row
# raises no badge or notification.
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK="Casberi/Casberi/Model/YourAccountRecoveryCheck.swift"
RECOVERY="Casberi/Casberi/Model/YourAccountRecovery.swift"
PAGE="Casberi/Casberi/Screens/RecoveryCheckPage.swift"
for f in "$CHECK" "$RECOVERY" "$PAGE"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/recovery-check-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias R = YourAccountRecoveryCheck
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }
let now = Date(timeIntervalSince1970: 1_800_000_000)
let day: TimeInterval = 86_400

// Due: thirty days, from the last good check, else from the key's making.
check(!R.due(lastGood: now.addingTimeInterval(-29 * day), made: nil, now: now), "29 days since a good check is due")
check(R.due(lastGood: now.addingTimeInterval(-30 * day), made: nil, now: now), "30 days since a good check is not due")
check(!R.due(lastGood: nil, made: now.addingTimeInterval(-10 * day), now: now), "a key made 10 days ago is due")
check(R.due(lastGood: nil, made: now.addingTimeInterval(-31 * day), now: now), "a key made 31 days ago, never checked, is not due")
check(!R.due(lastGood: now.addingTimeInterval(-day), made: now.addingTimeInterval(-400 * day), now: now), "an old key checked yesterday is due")
check(R.due(lastGood: nil, made: nil, now: now), "a key with no date is not due")

// The verdict and the sentence.
func net(_ n: String, _ s: R.Standing) -> R.Network { R.Network(name: n, chainId: n.count, standing: s) }
let good = R.Result(keyPresent: true, signed: true, networks: [net("Base", .owner), net("Ethereum", .owner), net("Robinhood", .notOnYet)], at: now)
check(good.works && R.sentence(good) == ("Your recovery key works on Base and Ethereum.", true), "the canvas's sentence drifted")
check(R.fixable(good).map(\.name) == ["Robinhood"], "a network not on yet is not offered the fix")
let unread = R.Result(keyPresent: true, signed: true, networks: [net("Base", .owner), net("Ethereum", .unread)], at: now)
check(unread.works && R.sentence(unread).text == "Your recovery key works on Base.", "an unanswered network counted either way")
let refused = R.Result(keyPresent: true, signed: true, networks: [net("Base", .owner), net("Ethereum", .notOwner)], at: now)
check(!refused.works && R.sentence(refused) == ("Your recovery key is not an owner on Ethereum.", false), "a network that refuses the key is not named in red")
check(R.fixable(refused).map(\.name) == ["Ethereum"], "a refusing network is not offered the fix")
let unsigned = R.Result(keyPresent: true, signed: false, networks: [], at: now)
check(!unsigned.works && !R.sentence(unsigned).works, "a key that did not sign reads as working")
let gone = R.Result(keyPresent: false, signed: false, networks: [], at: now)
check(!gone.works && R.sentence(gone).text.contains("isn't in iCloud Keychain"), "a missing key is not said first")
let none = R.Result(keyPresent: true, signed: true, networks: [net("Base", .notOnYet)], at: now)
check(none.works && R.sentence(none).works, "a key on no network yet reads as broken")
check(R.Standing.notOwner.words == "Not an owner" && R.Standing.owner.words == "An owner" && R.Standing.notOnYet.words == "Not on yet",
      "a network's words drifted from the canvas")

print(bad == 0 ? "recovery-check self-test: \(ran) checks ok" : "recovery-check self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$CHECK" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ YourAccountRecoveryCheck.swift does not compile with Foundation alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring.
awk '/static func check\(_ account: String, reason: String\)/,/^    }$/' "$RECOVERY" > "$TMP/check.swift"
grep -q 'isValidSignature' "$TMP/check.swift" && grep -q 'ethCall' "$TMP/check.swift" \
  && { echo "✗ the check asks a chain to validate the signature — one key alone fails at the spend limit's threshold (§1456)"; exit 1; }
grep -q 'key.isValidSignature(ecdsa, for: RecoveryDigest' "$TMP/check.swift" \
  || { echo "✗ the test signature is no longer verified on the phone against the key's public half"; exit 1; }
grep -q 'if result.works {' "$TMP/check.swift" || { echo "✗ a failed check stores its date — the row would go quiet on a broken key"; exit 1; }
grep -q 'UNUserNotificationCenter\|\.badge(\|setBadgeCount\|applicationIconBadgeNumber' "$PAGE" && { echo "✗ the recovery check raises a notification or a badge (§1490)"; exit 1; }
true
