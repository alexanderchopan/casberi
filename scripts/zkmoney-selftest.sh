#!/bin/zsh
# Casberi zk.money self-test — the SHIPPED wire behind zk.money's public
# edges (2026-10-11):
#
#   Casberi/Casberi/Model/ZkMoneyWire.swift (+ Keccak256.swift, pure)
#   Casberi/Shared/ZkMoneyLink.swift (the link reader, app and share extension)
#     — tag / nameHash / account / record   (the NameRegistry and its metadata)
#     — isDepositAddress / isPortal / move  (what a watched wallet's transfer is)
#     — link / requestPacket / CBOR / title (a shared link, read without fetching)
#     — dai                                  (the portal's DAI)
#
# Pure, local, deterministic, against replies saved off Ethereum mainnet
# (scripts/fixtures/zkmoney/) and a request link encoded with cbor-x, the
# reference encoder. Every failure below renders as a good-looking row:
#
#   • a namehash built without the `.zk.money` labels — every tag "unclaimed";
#   • any minimal proxy read as a deposit address — a send to ANY clone
#     contract titled "Deposited to zk.money";
#   • a DAI transfer FROM any address read as a withdrawal;
#   • a payment link kept WITH its fragment — the claim secret, a bearer
#     credential, synced to iCloud in a library row;
#   • the request amount read little-endian — "20.5 DAI" becomes nonsense.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/ZkMoneyWire.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
LINK="Casberi/Shared/ZkMoneyLink.swift"
FIX="scripts/fixtures/zkmoney"
for f in "$WIRE" "$KECCAK" "$LINK" "$FIX/ownerof-zac.json" "$FIX/userrecord-zac.json" "$FIX/code-deposit.json" \
         "$FIX/code-portal-head.json" "$FIX/portal-dai.json" "$FIX/request-link.txt"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let fix = ProcessInfo.processInfo.environment["ZK_FIX"]!
func result(_ name: String) -> String? {
    let data = try! Data(contentsOf: URL(fileURLWithPath: fix + "/" + name))
    return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["result"] as? String
}

print("tags")
check(ZkMoneyWire.tag("Zac.zk.money") == "zac", "a tag, folded")
check(ZkMoneyWire.tag(" @zac.zk.money. ") == "zac", "…from a mention")
check(ZkMoneyWire.tag("zac") == nil, "a bare word is no tag by itself")
check(ZkMoneyWire.tag("zac", bareAllowed: true) == "zac", "…unless the caller knows it is one")
check(ZkMoneyWire.tag("zac.eth") == nil && ZkMoneyWire.tag("a b.zk.money") == nil, "not a tag")
check(ZkMoneyWire.nameHash("zac") == "0x46f127163101255dc25a533a904a5fc10a98a3c27d675dc2944f876109dd0df9",
      "namehash(zac.zk.money) matches viem")
let account = ZkMoneyWire.account(result("ownerof-zac.json"))
check(account == "0xf5f6b47e15825e27bced1fe99ba90f8c2334fccf", "ownerOf reads the account")
check(ZkMoneyWire.account("0x" + String(repeating: "0", count: 64)) == nil, "a zero owner is an unclaimed tag")
let record = ZkMoneyWire.record(tag: "zac", account: account!, userRecord: result("userrecord-zac.json"))
check(record.aztec == "0x0e35b5beb1c09008a0388066efad062cd3e5fa060fdcddeef04d8753cad71d27", "the Aztec address")
check(record.onMainnet, "made on Aztec mainnet's rollup")

print("moves")
let me = "0xf4a56a0d8d04bc17df79241ce7c3c2eb2ef8b067"
let deposit = "0x32dec5945f023b441e6d6aa1b5d0f15ce1d7c588"
check(ZkMoneyWire.isDepositAddress(code: result("code-deposit.json")), "a swept deposit address is zk.money's proxy")
check(!ZkMoneyWire.isDepositAddress(code: result("code-portal-head.json")), "the portal's own code is not")
check(!ZkMoneyWire.isDepositAddress(code: "0x363d3d373d3d3d363d73" + String(repeating: "ab", count: 20) + "5af43d82803e903d91602b57fd5bf3"),
      "a minimal proxy to anything else is not")
check(!ZkMoneyWire.isDepositAddress(code: "0x"), "an address with no code yet is not (yet)")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: me, to: deposit, watched: me, counterpartyCode: result("code-deposit.json")) == .deposit,
      "DAI out to a deposit address is a deposit")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "DAI in from the portal is a withdrawal")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0x6534905c84f13af94d649706e4ec711770d3603c", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "…from an old portal too")
check(ZkMoneyWire.move(token: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", from: "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449", to: me, watched: me, counterpartyCode: nil) == nil,
      "a portal only ever pays out DAI")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: deposit, to: me, watched: me, counterpartyCode: nil) == nil,
      "DAI in from anyone else is nothing of zk.money's")
check(ZkMoneyWire.title(.deposit, amount: "459.58", symbol: "DAI") == "Deposited 459.58 DAI to zk.money", "the deposit's words")
check(ZkMoneyWire.dai(result("portal-dai.json")).map { $0 > 25_000 && $0 < 26_000 } == true, "the portal's DAI, whole units")

print("links")
let request = (try! String(contentsOfFile: fix + "/request-link.txt", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
guard case .request(let tag, let amount, let symbol, let note, let expires)? = ZkMoneyLink.link(request) else {
    print("  ✗ the request link did not decode"); exit(1)
}
check(tag == "zac" && symbol == "DAI" && note == "dinner", "tag, token and note")
check(amount == Decimal(string: "20.5"), "the amount, big-endian over 18 decimals: \(String(describing: amount))")
check(expires.map { Int($0.timeIntervalSince1970) } == 1_791_900_000, "the expiry, a cbor-x float64")
check(ZkMoneyLink.title(ZkMoneyLink.link(request)!) == "Payment request — 20.5 DAI to zac.zk.money", "the request's title")
check(ZkMoneyLink.capture(url: URL(string: request)!, text: request)!.note?.hasPrefix("“dinner”") == true, "its note is the row's body")
let pay = "https://zk.money/link#AbCdSeCrEtClAiMkEy-123"
check(ZkMoneyLink.link(pay) == .payment(kept: "https://zk.money/link"), "a payment link keeps no fragment")
check(ZkMoneyLink.link("https://wallet.zk.money/claim#zzz") == .payment(kept: "https://wallet.zk.money/claim"), "…a claim link neither")
check(ZkMoneyLink.title(.payment(kept: "x")) == "zk.money payment link", "a payment link's title")
let captured = ZkMoneyLink.capture(url: URL(string: pay)!, text: "claim this: " + pay)!
check(!captured.content.contains("SeCrEt") && captured.content == "claim this: https://zk.money/link", "capture drops the secret from the surrounding words too")
check(captured.note?.contains("was not kept") == true, "and the row's body says so")
check(ZkMoneyLink.link("https://evil.example/request#" + request.split(separator: "#")[1]) == nil, "another host is not zk.money")
check(ZkMoneyLink.link("https://zk.money/request#!!") == nil, "a broken fragment is no request")
check(CBOR.decode([0xbf]) == nil, "an indefinite map is refused")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "ZkMoneyWire, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "$WIRE" "$KECCAK" "$LINK" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile against the shipped ZkMoneyWire:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
ZK_FIX="$PWD/$FIX" "$TMP/run" || exit 1

# --- mutations ----------------------------------------------------------------
echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/ZkMoneyWire.swift"
  cp "$LINK" "$WORK/ZkMoneyLink.swift"
  # The anchor names its own file: the wire's, else the Shared link reader's.
  local target="$WORK/ZkMoneyWire.swift" original="$WIRE"
  if ! grep -qF -- "$from" "$target"; then target="$WORK/ZkMoneyLink.swift"; original="$LINK"; fi
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1; fi
  if cmp -s "$original" "$target"; then
    echo "  ✗ $name — the mutation changed nothing"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/ZkMoneyWire.swift" "$KECCAK" "$WORK/ZkMoneyLink.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if ZK_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "a payment link kept with its secret" \
  'parts?.fragment = nil' \
  'parts?.fragment = parts?.fragment'
mutate "any minimal proxy read as a deposit address" \
  'return deployments.contains { $0.depositImplementation == implementation }' \
  'return true'
mutate "DAI from anyone read as a withdrawal" \
  'if to.lowercased() == me, isPortal(from), token?.lowercased() == dai { return .withdrawal }' \
  'if to.lowercased() == me, token?.lowercased() == dai { return .withdrawal }'
mutate "the namehash built bottom-up" \
  'for label in display(tag).split(separator: ".").reversed() {' \
  'for label in display(tag).split(separator: ".") {'
mutate "the amount read little-endian" \
  'for byte in raw { value = value * 256 + Decimal(byte) }' \
  'for byte in raw.reversed() { value = value * 256 + Decimal(byte) }'
mutate "a zero owner read as an account" \
  'return address.allSatisfy { $0 == "0" } ? nil : "0x" + address' \
  'return "0x" + address'
mutate "a bare word taken as a tag" \
  '} else if !bareAllowed {' \
  '} else if false {'
mutate "the cbor-x tag not unwrapped" \
  'return item(b, &i, depth: depth + 1)
        case 7 where info == 27:' \
  'return nil
        case 7 where info == 27:'

echo "✓ zk.money self-test passed"
