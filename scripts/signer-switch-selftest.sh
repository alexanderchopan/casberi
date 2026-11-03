#!/bin/zsh
# Casberi signer-switch self-test (prd §1644) — the co-signer's sheet is never
# stuck on one wallet.
#
#   Casberi/Casberi/Model/SignerSwitch.swift          the doors, the ending rule, the signal
#   Casberi/Casberi/Model/YourAccountSignerLink.swift  `sign`: the rule applied, the switch heard
#   Casberi/Casberi/Screens/SignerRequestSheet.swift   the row, the doors, `coSigner` and `Batch`
#
# The pure file is compiled WHOLE and run; the wiring is read by source. Every
# failure here is the user's report coming back (2026-11-01: "rainbow isn't
# loading signature for my co-signer … i can't change wallet and so am stuck"):
#
#   • Use another wallet that keeps the silent session, or ends the send;
#   • a Cancel that keeps a wallet which never answered, so the next send
#     asks it again;
#   • a wallet door whose link is not `<scheme>://wc?uri=<encoded>`, or no
#     `wc:` door when none of the three is installed;
#   • an Ask again that hears nothing on the second request of one ask (an
#     `AsyncStream` is finished by cancelling its reader);
#   • `notTheSigner` loosened: another wallet signs only with the same key.
#
# `--self-test` runs the same suite: the mutations below ARE its self-test,
# each proving one assertion is load-bearing. Pure, local, deterministic.
set -euo pipefail
cd "$(dirname "$0")/.."

PURE="Casberi/Casberi/Model/SignerSwitch.swift"
LINK="Casberi/Casberi/Model/YourAccountSignerLink.swift"
SHEET="Casberi/Casberi/Screens/SignerRequestSheet.swift"
PLIST="Casberi/Casberi/Info.plist"
for f in "$PURE" "$LINK" "$SHEET" "$PLIST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/signer-switch-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

let pairing = URL(string: "wc:8a5e5bdc@2?relay-protocol=irn&symKey=" + String(repeating: "7", count: 64))!
let names = SignerSwitch.wallets.map(\.name)
check(names == ["Base", "Ambire", "MetaMask", "Rabby", "Zerion", "Rainbow", "OKX", "OKX"], "the user's seven, in the user's order (OKX under both its apps)")
check(Set(SignerSwitch.wallets.map(\.scheme)).count == SignerSwitch.wallets.count, "no scheme twice")

print("the wallet doors")
let mm = SignerSwitch.wallets.first { $0.scheme == "metamask" }!
let link = SignerSwitch.link(mm, pairing: pairing)
let comps = link.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
check(link?.scheme == "metamask" && link?.host == "wc", "the wallet's own scheme, onto wc")
check(comps?.queryItems?.count == 1 && comps?.queryItems?.first?.name == "uri", "one query item, uri")
check(comps?.queryItems?.first?.value == pairing.absoluteString, "the pairing comes back whole")
let raw = link.map { String($0.absoluteString.dropFirst("metamask://wc?uri=".count)) } ?? ""
check(!raw.contains(where: { ":@?&=/".contains($0) }), "the pairing is percent-encoded whole (its & and = never split the query)")

let none = SignerSwitch.doors(pairing: pairing, installed: { _ in false })
check(none == [SignerSwitch.Door(wallet: nil, url: pairing)], "none installed: the one wc: door, as before")
let some = SignerSwitch.doors(pairing: pairing, installed: { ["metamask", "rabby"].contains($0.scheme) })
check(some.map { $0.wallet?.name } == ["MetaMask", "Rabby"], "one door per installed wallet, in order")
check(some.allSatisfy { $0.url.absoluteString.hasPrefix("\($0.wallet!.scheme)://\($0.wallet!.path)wc?uri=") }, "each onto its own link")
let okx = SignerSwitch.doors(pairing: pairing, installed: { $0.name == "OKX" })
check(okx.count == 1 && okx[0].url.absoluteString.hasPrefix("okxwallet://main/wc?uri="), "both OKX apps installed: one OKX row, OKX Wallet's")
let okex = SignerSwitch.doors(pairing: pairing, installed: { $0.scheme == "okex" })
check(okex.count == 1 && okex[0].url.absoluteString.hasPrefix("okex://main/wc?uri="), "the OKX app alone: its own main/ link")
check(!some.contains { $0.wallet == nil }, "with a wallet installed, no bare wc: door")

print("how an ending treats the session")
check(SignerSwitch.closes(.switched), "Use another wallet lets the session go")
check(SignerSwitch.closes(.timedOut), "a wait run out lets it go")
check(SignerSwitch.closes(.cancelled(sent: true)), "Cancel after the request went lets it go")
check(!SignerSwitch.closes(.cancelled(sent: false)), "Cancel before the request went keeps it")
check(SignerSwitch.pairsAfresh(.switched, kept: true) && SignerSwitch.pairsAfresh(.switched, kept: false),
      "Use another wallet pairs afresh, kept or fresh")
check(SignerSwitch.pairsAfresh(.gone, kept: true), "a kept session gone pairs afresh (§1601)")
check(!SignerSwitch.pairsAfresh(.gone, kept: false), "a fresh pairing gone at once is not chased")
check(!SignerSwitch.pairsAfresh(.timedOut, kept: true), "a wait run out ends the ask")
check(!SignerSwitch.pairsAfresh(.cancelled(sent: true), kept: true), "a Cancel ends the ask")

print("the signal")
func heard(_ stream: AsyncStream<Void>, within ms: Int) async -> Bool {
    await withTaskGroup(of: Bool.self) { g in
        g.addTask { for await _ in stream { return true }; return false }
        g.addTask { try? await Task.sleep(for: .milliseconds(ms)); return false }
        let first = await g.next() ?? false
        g.cancelAll()
        return first
    }
}
let signal = SignerSignal()
// The first request's reader, cancelled as `request`'s defer cancels it.
let first = signal.stream()
let reader = Task { for await _ in first {} }
try? await Task.sleep(for: .milliseconds(20))
reader.cancel()
_ = await reader.value
let second = signal.stream(), third = signal.stream()
signal.fire()
check(await heard(second, within: 500), "the second request of one ask hears Ask again")
check(await heard(third, within: 500), "every waiter hears it")
signal.finish()
check(!(await heard(signal.stream(), within: 200)), "a finished signal is silent")

exit(failures == 0 ? 0 : 1)
SWIFT

# The wiring, by source, over (link, sheet, plist) — run on the tree and on
# every mutated copy below.
wiring() {
  local link="$1" sheet="$2" plist="$3"
  strip() { grep -v '^[[:space:]]*//' "$1"; }
  local SIGN; SIGN=$(strip "$link" | awk '/static func sign\(typedData/,/^    }/')
  print -r -- "$SIGN" | grep -q 'if SignerSwitch.closes(end) { close(pairing) }' \
    || { echo "  ✗ sign no longer lets a session go by SignerSwitch.closes"; return 1; }
  print -r -- "$SIGN" | grep -q 'guard SignerSwitch.pairsAfresh(end, kept: wasKept) else { throw error }' \
    || { echo "  ✗ sign no longer pairs afresh by SignerSwitch.pairsAfresh"; return 1; }
  print -r -- "$SIGN" | grep -q 'switching: switching' \
    || { echo "  ✗ sign's request does not hear Use another wallet"; return 1; }
  print -r -- "$SIGN" | grep -q 'sent: { sent.withLock { $0 = true }' \
    || { echo "  ✗ sign no longer knows whether the request went (Cancel keeps a silent wallet)"; return 1; }
  strip "$link" | awk '/private static func ending\(/,/^    }/' | grep -q 'if Task.isCancelled { return .cancelled(sent: sent) }' \
    || { echo "  ✗ a Cancel is no longer read as the person's"; return 1; }
  strip "$link" | grep -q 'case .switched: throw Failure.switched' \
    || { echo "  ✗ request never ends on Use another wallet"; return 1; }
  strip "$link" | awk '/static func answer\(to ids/,/^    }/' | grep -q 'for await _ in switching { return .switched }' \
    || { echo "  ✗ the wait does not listen for Use another wallet"; return 1; }
  # §1516/§1601's address check stays exactly as it was.
  strip "$link" | awk '/static func connect\(signer/,/^    }/' | grep -q 'throw Failure.notTheSigner(accounts.first?.address ?? "")' \
    || { echo "  ✗ a wallet connected as another address is no longer refused"; return 1; }

  strip "$sheet" | grep -q 'DSDoorRow(icon: "arrow.triangle.swap", label: "Use another wallet") { ask.useAnother() }' \
    || { echo "  ✗ the kept sheet has no Use another wallet"; return 1; }
  strip "$sheet" | awk '/func useAnother\(\)/,/^    }/' | grep -q 'switches.fire()' \
    || { echo "  ✗ Use another wallet tells no one"; return 1; }
  local CO; CO=$(strip "$sheet" | awk '/static func coSigner\(owner/,/^    }/')
  print -r -- "$CO" | grep -q 'switching: ask.switches' && print -r -- "$CO" | grep -q 'ask.offerSwitch()' \
    || { echo "  ✗ the co-signer's ask does not hear Use another wallet"; return 1; }
  local BATCH; BATCH=$(strip "$sheet" | awk '/private func sign\(_ typedData/,/^        }$/')
  print -r -- "$BATCH" | grep -q 'switching: ask.switches' && print -r -- "$BATCH" | grep -q 'ask.offerSwitch()' \
    || { echo "  ✗ a several-network ask does not hear Use another wallet"; return 1; }
  # The row shows only once the request listens, or a quick tap is lost.
  print -r -- "$BATCH" | grep -q 'sent: { ask.ask(kept: nil) })' \
    || { echo "  ✗ a several-network ask shows Use another wallet before it listens"; return 1; }
  # A re-paired wallet's door is its own session's, never the one let go.
  print -r -- "$SIGN" | grep -q 'asked = (pairing, door(of: pairing.topic))' \
    || { echo "  ✗ a fresh pairing's door may be the wallet just let go"; return 1; }
  print -r -- "$BATCH" | grep -A3 'catch YourAccountSignerLink.Failure.switched' | grep -q 'YourAccountSignerLink.close(current)' \
    || { echo "  ✗ a several-network ask keeps the wallet it moved off"; return 1; }
  print -r -- "$BATCH" | grep -A3 'catch YourAccountSignerLink.Failure.switched' | grep -q 'held.withLock { $0 = nil }' \
    || { echo "  ✗ a several-network ask does not pair again"; return 1; }
  strip "$sheet" | grep -q 'SignerSwitch.doors(pairing: url, installed: { installed.contains($0) })' \
    || { echo "  ✗ the pairing's doors are not one per installed wallet"; return 1; }
  # Every finish of the sheet finishes both signals.
  strip "$sheet" | awk '/    func done\(\)/,/^    }/' | grep -q 'switches.finish()' \
    || { echo "  ✗ the sheet done leaves Use another wallet listening"; return 1; }

  # `canOpenURL` answers only for a declared scheme.
  local scheme
  local schemes=( ${(f)"$(grep -o 'scheme: "[a-z0-9-]*"' "$PURE" | sed 's/scheme: "\(.*\)"/\1/')"} )
  (( ${#schemes} >= 7 )) || { echo "  ✗ the wallet list was not read (${#schemes} schemes)"; return 1; }
  for scheme in $schemes; do
    sed -n '/LSApplicationQueriesSchemes/,/<\/array>/p' "$plist" | grep -q "<string>$scheme</string>" \
      || { echo "  ✗ $scheme is not in LSApplicationQueriesSchemes, so its door never shows"; return 1; }
  done
  return 0
}

echo "SignerSwitch, compiled whole"
swiftc -Onone -o "$TMP/run" "$PURE" "$TMP/main.swift" > "$TMP/build.log" 2>&1 \
  || { sed -n '1,30p' "$TMP/build.log"; echo "✗ the harness did not compile"; exit 1; }
"$TMP/run" || { echo "✗ signer-switch self-test failed"; exit 1; }

echo "the wiring"
wiring "$LINK" "$SHEET" "$PLIST" || { echo "✗ signer-switch self-test failed"; exit 1; }
echo "  ✓ sign, request, the sheet, coSigner and Batch carry the switch; notTheSigner stands"

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$PURE" "$WORK/SignerSwitch.swift"; cp "$LINK" "$WORK/link.swift"
  cp "$SHEET" "$WORK/sheet.swift"; cp "$PLIST" "$WORK/Info.plist"
  local target
  case "$file" in
    "$PURE") target="$WORK/SignerSwitch.swift" ;;
    "$LINK") target="$WORK/link.swift" ;;
    "$SHEET") target="$WORK/sheet.swift" ;;
    "$PLIST") target="$WORK/Info.plist" ;;
  esac
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if cmp -s "$file" "$target"; then echo "  ✗ $name — changed nothing"; exit 1; fi
  if [[ "$file" == "$PURE" ]]; then
    if ! swiftc -Onone -o "$TMP/mut" "$WORK/SignerSwitch.swift" "$TMP/main.swift" 2>/dev/null; then
      echo "  ✓ $name (rejected at compile)"; return
    fi
    if "$TMP/mut" > /dev/null 2>&1; then
      echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
    fi
  else
    if wiring "$WORK/link.swift" "$WORK/sheet.swift" "$WORK/Info.plist" > /dev/null 2>&1; then
      echo "  ✗ $name — the wiring check still passed, so nothing was testing this"; exit 1
    fi
  fi
  echo "  ✓ $name"
}

mutate "Use another wallet keeps the silent session" "$PURE" \
  'case .gone, .timedOut, .switched: true' 'case .gone, .timedOut: true
        case .switched: false'
mutate "Cancel keeps a wallet that never answered" "$PURE" \
  'case .cancelled(let sent): sent' 'case .cancelled: false'
mutate "Cancel before the request went drops a good session" "$PURE" \
  'case .cancelled(let sent): sent' 'case .cancelled: true'
mutate "Use another wallet ends the send" "$PURE" \
  'case .switched: true
        case .gone: kept' 'case .switched: false
        case .gone: kept'
mutate "a fresh pairing gone is chased forever" "$PURE" \
  'case .gone: kept' 'case .gone: true'
mutate "the pairing not encoded (its & splits the query)" "$PURE" \
  'unreserved.insert(charactersIn: "-._~")' 'unreserved.insert(charactersIn: "-._~:@?&=/")'
mutate "every wallet's door opens MetaMask" "$PURE" \
  'return URL(string: "\(wallet.scheme)://\(wallet.path)wc?uri=\(uri)")' 'return URL(string: "metamask://wc?uri=\(uri)")'
mutate "OKX's main/ dropped" "$PURE" \
  'return URL(string: "\(wallet.scheme)://\(wallet.path)wc?uri=\(uri)")' 'return URL(string: "\(wallet.scheme)://wc?uri=\(uri)")'
mutate "two OKX rows" "$PURE" \
  '!named.contains(where: { $0.wallet?.name == w.name })' 'true'
mutate "none installed: no door at all" "$PURE" \
  'return named.isEmpty ? [Door(wallet: nil, url: pairing)] : named' 'return named'
mutate "the bare wc: door beside the named ones" "$PURE" \
  'return named.isEmpty ? [Door(wallet: nil, url: pairing)] : named' 'return named + [Door(wallet: nil, url: pairing)]'
mutate "Rabby dropped" "$PURE" \
  '
                          Wallet(name: "Rabby", scheme: "rabby"),' ''
mutate "Ambire dropped" "$PURE" \
  '
                          Wallet(name: "Ambire", scheme: "ambire"),' ''
mutate "the signal a single stream (Ask again dead after a re-pair)" "$PURE" \
  'if !isOver { waiting[id] = continuation }' 'if !isOver, waiting.isEmpty { waiting[id] = continuation }'
mutate "sign ignores the closing rule" "$LINK" \
  'if SignerSwitch.closes(end) { close(pairing) }' 'if end == .timedOut { close(pairing) }'
mutate "sign never pairs afresh" "$LINK" \
  'guard SignerSwitch.pairsAfresh(end, kept: wasKept) else { throw error }' 'throw error'
mutate "sign's request deaf to the switch" "$LINK" \
  'resend: resend, switching: switching,' 'resend: resend,'
mutate "the wait deaf to the switch" "$LINK" \
  'for await _ in switching { return .switched }' 'for await _ in switching { break }'
mutate "a Cancel read as a timeout" "$LINK" \
  'if Task.isCancelled { return .cancelled(sent: sent) }' ''
mutate "notTheSigner loosened" "$LINK" \
  'throw Failure.notTheSigner(accounts.first?.address ?? "")' 'return Pairing(topic: session.topic, signer: signer, chainIds: [])'
mutate "no Use another wallet row" "$SHEET" \
  'DSDoorRow(icon: "arrow.triangle.swap", label: "Use another wallet") { ask.useAnother() }' 'EmptyView()'
mutate "the row tells no one" "$SHEET" \
  '        switches.fire()' '        _ = switches'
mutate "coSigner deaf to the switch" "$SHEET" \
  'switching: ask.switches, show: { ask.pair($0) })' 'show: { ask.pair($0) })'
mutate "Batch keeps the wallet it moved off" "$SHEET" \
  '                        YourAccountSignerLink.close(current)
' ''
mutate "Batch deaf to the switch" "$SHEET" \
  'switching: ask.switches,
                                                                       sent:' 'sent:'
mutate "Batch shows the row before it listens" "$SHEET" \
  'sent: { ask.ask(kept: nil) })' ')'
mutate "the fresh door looked up by address (the old wallet's)" "$LINK" \
  'asked = (pairing, door(of: pairing.topic))' 'asked = (pairing, keptSession(signer: signer, chainId: chainId)?.1)'
mutate "the installed wallets never asked (one wc: door again)" "$SHEET" \
  'installed: { installed.contains($0) }' 'installed: { _ in false }'
mutate "the sheet done leaves the switch listening" "$SHEET" \
  '        switches.finish()' ''
mutate "rabby undeclared" "$PLIST" \
  '<string>rabby</string>' ''
mutate "zerion undeclared" "$PLIST" \
  '<string>zerion</string>' ''
mutate "cbwallet undeclared (Base never shows)" "$PLIST" \
  '<string>cbwallet</string>' ''

echo "✓ signer-switch self-test"
