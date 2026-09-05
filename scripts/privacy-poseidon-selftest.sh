#!/bin/zsh
# Casberi Ethrex-Privacy shielded-note self-test (2026-09-05, prd §593e).
#
#   Casberi/Casberi/Model/PrivacyDevnetPoseidon.swift          — BN254 field + Poseidon
#   Casberi/Casberi/Model/PrivacyDevnetPoseidonConstants.swift — generated round constants
#   Casberi/Casberi/Model/PrivacyDevnetNote.swift              — note chain, shield calldata, tree
#
# All three Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED here.
#
# WHY THIS IS THE ONLY PROOF THESE NUMBERS ARE RIGHT. Poseidon over BN254 is the
# pool's one hash: a note commitment, a nullifier, and every Merkle node are
# Poseidon. A wrong hash is INVISIBLE to every other check — the build is happy,
# the screen is right — and it renders as a deposit nobody can ever spend and a
# proof that never verifies. So the field arithmetic and the note chain are
# checked here against circomlibjs's own vectors AND against the exact values
# that landed a REAL shield on chain 8141 (the commitment the chain emitted as
# a LeafAppended leaf, and the depth-20 root it published).
#
# THE FIXTURES ARE REAL. The note chain (spend key, rho, value 0.1 ETH), its
# commitment, and the one-leaf tree root are the values from a shield this
# project broadcast and the node accepted, returning our own predicted hash.
# The shield selector 0x26123548 is the first four bytes of that transaction's
# second frame on chain, not a locally recomputed keccak.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="Casberi/Casberi/Model"
FILES=("$MODEL/PrivacyDevnetPoseidon.swift" "$MODEL/PrivacyDevnetPoseidonConstants.swift" "$MODEL/PrivacyDevnetNote.swift")

for f in "$FILES[@]"; do
  [[ -f "$f" ]] || { echo "✗ missing $f"; exit 1; }
done

# --- the assertion program (compiled against the WHOLE shipped files) --------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$FILES[@]" "$work/"

cat > "$work/main.swift" <<'SWIFT'
import Foundation
typealias Fp = PrivacyDevnetPoseidon.Fp
var failures = 0
func fpDec(_ s: String) -> Fp {
    var n = [UInt8](repeating: 0, count: 32)
    for ch in s { let d = UInt8(ch.asciiValue! - 48); var c = UInt16(d)
        for i in (0..<32).reversed() { let v = UInt16(n[i]) * 10 + c; n[i] = UInt8(v & 0xff); c = v >> 8 } }
    return Fp(bytesBE: n)
}
func dec(_ f: Fp) -> String { var w = f.bytesBE(); if w.allSatisfy({ $0 == 0 }) { return "0" }; var d = [UInt8]()
    while !w.allSatisfy({ $0 == 0 }) { var r = 0; for i in 0..<32 { let c = r * 256 + Int(w[i]); w[i] = UInt8(c / 10); r = c % 10 }; d.append(UInt8(r)) }
    return String(d.reversed().map { Character(UnicodeScalar(48 + $0)) }) }
func ck(_ l: String, _ g: Fp, _ w: String) { if dec(g) == w { print("ok  \(l)") } else { print("FAIL \(l)\n  got  \(dec(g))\n  want \(w)"); failures += 1 } }
func ckHex(_ l: String, _ g: [UInt8], _ w: String) { let h = g.map { String(format: "%02x", $0) }.joined(); if h == w { print("ok  \(l)") } else { print("FAIL \(l) got \(h) want \(w)"); failures += 1 } }

// 1. circomlibjs base vectors
ck("poseidon2(1,2)", PrivacyDevnetPoseidon.p2(Fp(1), Fp(2)),
   "7853200120776062878684798364095072458815029376092732009249414926327459813530")
ck("poseidon3(0,0,0)", PrivacyDevnetPoseidon.p3(Fp(0), Fp(0), Fp(0)),
   "5317387130258456662214331362918410991734007599705406860481038345552731150762")

// 2. the pool's tagged chain, circomlibjs pool_chain vector
let vsk = fpDec("309172742813909128299932682904238834782572140067300474676")
let vrho = fpDec("4613053570233814709456818730276734957018462908845408743636")
let vval = fpDec("171028078353806246377624262744011790529")
let vdom = fpDec("1718789177404386403650277477276844977154177410039226274985")
ck("owner_pk", PrivacyDevnetPoseidon.ownerPk(spendKey: vsk),
   "1039946225446170998326178339291196362329225530018221890176570065876947005549")
let vinner = PrivacyDevnetNote.inner(spendKey: vsk, rho: vrho)
ck("inner", vinner, "13889555720016103730530817526090899750980470641114033550229056259052532544092")
let vcm = PrivacyDevnetNote.commitment(inner: vinner, value: vval)
ck("commitment", vcm, "10823010408303810809192284181848593809277645420173096998872853011972331385900")
ck("nullifier", PrivacyDevnetPoseidon.nullifier(domain: vdom, spendKey: vsk, commitment: vcm),
   "12632788740108496001633081209501119095314177530083891179193525174248521782678")

// 3. the empty depth-20 tree root (circomlibjs tree vector)
ck("empty root", PrivacyDevnetNote.merkleRoot(leaves: []),
   "15019797232609675441998260052101280400536945603062888308240081994073687793470")

// 4. THE LIVE SHIELD — values from a shield this project broadcast on chain 8141
let lsk = fpDec("6756049243489502329001266932442493804001155910352505508168586476345819947523")
let lrho = fpDec("13169441114018593136568951019791208819589554732630818579839500197909585874670")
let lval = PrivacyDevnetNote.fp(weiHex: "0x16345785d8a0000")   // 0.1 ETH
let linner = PrivacyDevnetNote.inner(spendKey: lsk, rho: lrho)
ck("live inner", linner, "5943260356020794580651422798385417970022317002089927441272842466270539586052")
let lcm = PrivacyDevnetNote.commitment(inner: linner, value: lval)
ck("live commitment", lcm, "12222699507414068318892760822988231409931940300696438487787766475588418019941")
ckHex("shield selector", PrivacyDevnetNote.shieldSelector, "26123548")
ckHex("shield calldata", PrivacyDevnetNote.shieldCalldata(inner: linner),
      "26123548" + linner.bytesBE().map { String(format: "%02x", $0) }.joined())
ck("live one-leaf root", PrivacyDevnetNote.merkleRoot(leaves: [lcm]),
   "19241281492636506489404263844113464685947380914337317476369246118983393333938")

if failures != 0 { print("FAILURES: \(failures)"); exit(1) }
print("ALL PASS")
SWIFT

run_program() {
  local dir="$1"
  ( cd "$dir" && swiftc -Onone *.swift -o check 2>/dev/null && ./check )
}

# --- optional self-test: prove a broken hash is CAUGHT (--self-test) ---------
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: proving the assertions catch a wrong hash…"
  mut="$(mktemp -d)"; trap 'rm -rf "$work" "$mut"' EXIT
  cp "$work"/*.swift "$mut/"
  # Mutation A: break the S-box (x^5 → x^4) — every Poseidon output changes.
  perl -0pi -e 's/let x4 = Fp\.mul\(x2, x2\)\n            return Fp\.mul\(x4, self\)/let x4 = Fp.mul(x2, x2)\n            return x4/' "$mut/PrivacyDevnetPoseidon.swift"
  if run_program "$mut" >/dev/null 2>&1; then
    echo "✗ self-test: a broken S-box was NOT caught"; exit 1
  fi
  echo "  S-box mutation caught ✓"
  # Mutation B: break the shield selector — calldata assertion must fail.
  mut2="$(mktemp -d)"; cp "$work"/*.swift "$mut2/"
  perl -0pi -e 's/\[0x26, 0x12, 0x35, 0x48\]/[0x26, 0x12, 0x35, 0x49]/' "$mut2/PrivacyDevnetNote.swift"
  if run_program "$mut2" >/dev/null 2>&1; then
    echo "✗ self-test: a wrong shield selector was NOT caught"; rm -rf "$mut2"; exit 1
  fi
  rm -rf "$mut2"
  echo "  selector mutation caught ✓"
  echo "self-test OK"
fi

# --- the real run ------------------------------------------------------------
out="$(run_program "$work")" || { echo "$out"; echo "✗ privacy-poseidon-selftest: build or assertions failed"; exit 1; }
echo "$out"
[[ "$out" == *"ALL PASS"* ]] || { echo "✗ privacy-poseidon-selftest: did not reach ALL PASS"; exit 1; }
echo "✓ privacy-poseidon-selftest"
