#!/bin/zsh
# Casberi co-signer Off self-test (prd §1647) — turning the co-signer off
# never needs the co-signer: this iPhone signs with its own key and the
# recovery key, the two owners it holds.
#
#   Casberi/Casberi/Model/YourAccountOp.swift      twoPasskeySignatures
#   Casberi/Casberi/Model/YourAccountChain.swift   turnOffAlone, operate's alsoSigner
#   Casberi/Casberi/Screens/MoveSecurity.swift     offAlone, the switch's walk
#
# 1. The pair's bytes, read back by a decoder written here the way Safe's
#    `checkNSignatures` reads them: two contract signatures (v = 0), owners
#    ascending, each offset landing on its own assertion. A wrong order or
#    offset is GS026/GS023 on chain and the person is locked in again.
# 2. Where Off is offered alone: threshold 2, this phone's key signing, the
#    recovery key an owner and on this iPhone — nowhere else.
# 3. The wiring, by source: the walk takes turnOffAlone where offAlone holds
#    and asks no co-signer there; turnOffAlone signs with the recovery key as
#    the second passkey; operate never adds the Signer to a two-passkey ask.
#
# Every check is then broken on purpose (mutations); each must be caught.
# `--self-test` is accepted and ignored: the mutations run on every call.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -uo pipefail
cd "$(dirname "$0")/.."

OP="Casberi/Casberi/Model/YourAccountOp.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
SECURITY="Casberi/Casberi/Screens/MoveSecurity.swift"
for f in "$OP" "$CHAIN" "$SECURITY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/cosigner-off-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Pull one declaration out of a file by its signature, braces balanced.
cat > "$TMP/grab.py" <<'PY'
import sys
def grab(path, signature):
    src = open(path).read()
    i = src.find(signature)
    if i < 0: sys.exit(1)
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")
op, security, out = sys.argv[1:4]
open(out, "w").write("import Foundation\n"
    + "extension YourAccountOp {\n" + grab(op, "static func twoPasskeySignatures(") + "\n}\n"
    + "extension MoveSecurity {\n" + grab(security, "static func offAlone(") + "\n}\n")
PY

cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
// The account's ABI word for an address, as `YourAccount.w` writes it.
enum YourAccount {
    static func w(_ address: String) -> [UInt8] {
        let hex = Array(address.lowercased().dropFirst(2))
        var bytes = [UInt8](repeating: 0, count: 12)
        var i = 0
        while i + 1 < hex.count { bytes.append(UInt8(String(hex[i...i+1]), radix: 16)!); i += 2 }
        return bytes
    }
    static func w(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32)
        var v = n, i = 31
        while v > 0 && i >= 0 { out[i] = UInt8(v & 0xff); v >>= 8; i -= 1 }
        return out
    }
}
// An assertion whose LENGTH depends on its key, so the second offset is
// only right when it counts the first assertion's real length.
enum SafeWebAuthn {
    static func signatureBytes(r: [UInt8], s: [UInt8]) -> [UInt8]? {
        guard r.count == 32, s.count == 32 else { return nil }
        return r + s + [UInt8](repeating: r[0], count: Int(r[0] % 7) * 13)
    }
}
enum YourAccountOp {}
enum MoveSecurity {}
enum Chain { enum RecoveryState: Equatable { case notThere, missing, added } }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func word(_ b: [UInt8], _ at: Int) -> Int? {
    guard at + 32 <= b.count, b[at..<(at + 24)].allSatisfy({ $0 == 0 }) else { return nil }
    return b[(at + 24)..<(at + 32)].reduce(0) { $0 << 8 | Int($1) }
}
/// Safe's `checkNSignatures`, for contract signatures only: per owner, its
/// address, its offset (from the start of the signatures) and v = 0; the
/// owners strictly ascending; at the offset, a length and the data.
func decode(_ sigs: [UInt8], count: Int) -> [(owner: [UInt8], data: [UInt8])]? {
    var out: [(owner: [UInt8], data: [UInt8])] = []
    var last = [UInt8](repeating: 0, count: 20)
    for i in 0..<count {
        let at = i * 65
        guard at + 65 <= sigs.count, sigs[at + 64] == 0 else { return nil }
        let owner = Array(sigs[(at + 12)..<(at + 32)])
        guard last.lexicographicallyPrecedes(owner), let offset = word(sigs, at + 32),
              offset >= count * 65, let length = word(sigs, offset), offset + 32 + length <= sigs.count else { return nil }
        out.append((owner, Array(sigs[(offset + 32)..<(offset + 32 + length)])))
        last = owner
    }
    return out
}
func addr(_ a: String) -> [UInt8] { Array(YourAccount.w(a).suffix(20)) }

let low = "0x1111111111111111111111111111111111111111"
let high = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
let r1 = [UInt8](repeating: 3, count: 32), s1 = [UInt8](repeating: 4, count: 32)
let r2 = [UInt8](repeating: 5, count: 32), s2 = [UInt8](repeating: 6, count: 32)
let a1 = SafeWebAuthn.signatureBytes(r: r1, s: s1)!, a2 = SafeWebAuthn.signatureBytes(r: r2, s: s2)!
check(a1.count != a2.count, "the fixture's two assertions differ in length")

for (name, first, second) in [("the higher owner first", (high, r1, s1), (low, r2, s2)),
                              ("the lower owner first", (low, r2, s2), (high, r1, s1))] {
    guard let both = YourAccountOp.twoPasskeySignatures((first.0, first.1, first.2), (second.0, second.1, second.2)) else {
        check(false, "\(name): the pair builds"); continue
    }
    check(both.prefix(12).allSatisfy { $0 == 0 }, "\(name): no time bounds")
    let decoded = decode(Array(both.dropFirst(12)), count: 2)
    check(decoded != nil, "\(name): Safe reads two contract signatures, owners ascending")
    if let decoded {
        check(decoded[0].owner == addr(low) && decoded[1].owner == addr(high), "\(name): the lower owner leads")
        check(decoded[0].data == a2 && decoded[1].data == a1, "\(name): each owner's offset lands on its own assertion")
        check(Array(both.dropFirst(12)).count == 130 + 64 + a1.count + a2.count, "\(name): nothing after the second assertion")
    }
}
check(YourAccountOp.twoPasskeySignatures((low, r1, s1), (low.uppercased().replacingOccurrences(of: "0X", with: "0x"), r2, s2)) == nil,
      "one owner twice builds nothing")

// Where Off is offered without the co-signer.
check(MoveSecurity.offAlone(threshold: 2, keyIndex: 0, recovery: .added, hasRecoveryKey: true), "offered: two keys, this phone signs, recovery key an owner")
check(!MoveSecurity.offAlone(threshold: 2, keyIndex: 0, recovery: .missing, hasRecoveryKey: true), "not where the recovery key is no owner")
check(!MoveSecurity.offAlone(threshold: 2, keyIndex: 0, recovery: .added, hasRecoveryKey: false), "not where this iPhone holds no recovery key")
check(!MoveSecurity.offAlone(threshold: 2, keyIndex: nil, recovery: .added, hasRecoveryKey: true), "not where another device's key signs")
check(!MoveSecurity.offAlone(threshold: 1, keyIndex: 0, recovery: .added, hasRecoveryKey: true), "not where it is already off")
exit(failures == 0 ? 0 : 1)
SWIFT

strip() { grep -v '^[[:space:]]*//' "$1"; }

# Everything, over the tree rooted at $1. Prints its lines; exit status says.
check_tree() {
  local root="$1" out="$TMP/run-$RANDOM"
  python3 "$TMP/grab.py" "$root/$OP" "$root/$SECURITY" "$out.swift" || { echo "  ✗ extraction failed"; return 1; }
  swiftc -Onone -o "$out" "$TMP/stubs.swift" "$out.swift" "$TMP/main.swift" 2>"$out.log" \
    || { grep -E 'error:' "$out.log" | head -5; echo "  ✗ the harness did not compile"; return 1; }
  "$out" || return 1

  local walk
  walk=$(strip "$root/$SECURITY" | awk '/private func walkCoSigner\(on/,/^    }/')
  print -r -- "$walk" | grep -q 'let alone = !on && offAlone(s)' \
    || { echo "  ✗ the walk no longer decides Off alone per network"; return 1; }
  print -r -- "$walk" | grep -q 'let co = s.threshold == 2 && !alone ? coSigner(s, batch) : nil' \
    || { echo "  ✗ the walk asks the co-signer where Off needs none"; return 1; }
  print -r -- "$walk" | grep -q 'Chain.turnOffAlone(on: net' \
    || { echo "  ✗ the walk no longer turns Off alone"; return 1; }
  strip "$root/$SECURITY" | awk '/private func coSignerAsked\(on/,/^    }/' | grep -c '(on || !offAlone($0))' >/dev/null \
    || { echo "  ✗ the tray counts a co-signer approval where none is asked"; return 1; }
  echo "  ✓ the walk turns Off alone where it can, and asks the co-signer only elsewhere"

  local alone
  alone=$(strip "$root/$CHAIN" | awk '/static func turnOffAlone\(on/,/^    }/')
  print -r -- "$alone" | grep -q 'YourAccountRecovery.sign(digest, for: account' \
    || { echo "  ✗ Off alone no longer signs with the recovery key"; return 1; }
  print -r -- "$alone" | grep -q 'signer: device, alsoSigner: recovery,' \
    || { echo "  ✗ Off alone is not signed by this phone and the recovery key"; return 1; }
  print -r -- "$alone" | grep -q 'coSigner:' \
    && { echo "  ✗ Off alone hands the co-signer in"; return 1; }
  print -r -- "$alone" | grep -q 'changeThreshold(uint256)") + YourAccount.w(1)' \
    || { echo "  ✗ Off alone no longer lowers the threshold to one key"; return 1; }
  local chain
  chain=$(strip "$root/$CHAIN")
  print -r -- "$chain" | grep -c 'func needsSigner() async throws -> Bool { given == nil && alsoSigner == nil && deployed' >/dev/null \
    || { echo "  ✗ a two-passkey operation would be handed the Signer anyway"; return 1; }
  echo "  ✓ Off alone is the phone's key and the recovery key, never the co-signer"
  return 0
}

echo "co-signer Off (prd §1647)"
check_tree "." || { echo "✗ cosigner-off self-test failed"; exit 1; }

echo
echo "mutations (each must be caught)"
mutate() {
  local name="$1" file="$2" from="$3" to="$4" work="$TMP/work"
  rm -rf "$work"; mkdir -p "$work/$(dirname "$OP")" "$work/$(dirname "$SECURITY")"
  cp "$OP" "$CHAIN" "$work/$(dirname "$OP")/"; cp "$SECURITY" "$work/$(dirname "$SECURITY")/"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$work/$file" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src: sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || cmp -s "$file" "$work/$file"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if check_tree "$work" >/dev/null 2>&1; then
    echo "  ✗ $name — the check still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "the owners left in the order given" "$OP" \
  'if !YourAccount.w(pair[0].0).lexicographicallyPrecedes(YourAccount.w(pair[1].0)) { pair.swapAt(0, 1) }' ''
mutate "the second offset ignores the first assertion's length" "$OP" \
  'YourAccount.w(130 + firstTail.count)' 'YourAccount.w(130 + 32 + 64)'
mutate "the pair signed as an ECDSA owner" "$OP" \
  'YourAccount.w(pair[1].0) + YourAccount.w(130 + firstTail.count) + [0]' 'YourAccount.w(pair[1].0) + YourAccount.w(130 + firstTail.count) + [27]'
mutate "Off alone offered where the recovery key is no owner" "$SECURITY" \
  'keyIndex != nil && recovery == .added && hasRecoveryKey' 'keyIndex != nil && hasRecoveryKey'
mutate "Off alone offered where another device's key signs" "$SECURITY" \
  'threshold == 2 && keyIndex != nil &&' 'threshold == 2 &&'
mutate "the walk asks the co-signer anyway" "$SECURITY" \
  'let co = s.threshold == 2 && !alone ? coSigner(s, batch) : nil' 'let co = s.threshold == 2 ? coSigner(s, batch) : nil'
mutate "the tray counts every network as a co-signer approval" "$SECURITY" \
  '(on || !offAlone($0))' '(on || true)'
mutate "operate hands the Signer to a two-passkey ask" "$CHAIN" \
  'given == nil && alsoSigner == nil && deployed' 'given == nil && deployed'
mutate "Off alone signed by the phone alone" "$CHAIN" \
  'signer: device, alsoSigner: recovery,' 'signer: device,'

echo "✓ cosigner-off self-test: assertions and mutations all passed"
