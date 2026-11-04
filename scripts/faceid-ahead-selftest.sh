#!/bin/zsh
# Casberi Face ID-ahead self-test (prd §1687) — Face ID is asked at the tap,
# beside preparing, and the send's first signature takes what it passed.
#
#   Casberi/Casberi/Model/FaceIDAhead.swift       one use, waits for the answer, refused throws
#   Casberi/Casberi/Model/YourAccountKey.swift    `ahead`, `unlockAhead`, and `sign` taking it
#   Casberi/Casberi/Screens/MoveSentence.swift    asked at the tap, around `spend`, the foot's words
#
# The pure file is compiled WHOLE and run; the wiring is read by source. What
# a failure here means (user, 2026-11-03: "the preparing stage is where it
# lags"):
#
#   • a context reused by a second signature, so one Face ID signs twice;
#   • a Face ID turned down at the tap that still signs;
#   • Face ID back at the end of preparing (the ahead never reaches `sign`);
#   • a turned-down Face ID that leaves the reads running to the end;
#   • the foot saying "Confirm with Face ID" after Face ID passed.
#
# `--self-test` runs the same suite: the mutations below ARE its self-test.
# Pure, local, deterministic.
set -euo pipefail
cd "$(dirname "$0")/.."

PURE="Casberi/Casberi/Model/FaceIDAhead.swift"
KEY="Casberi/Casberi/Model/YourAccountKey.swift"
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
for f in "$PURE" "$KEY" "$MOVE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/faceid-ahead-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

print("passed")
let ok = FaceIDAhead(context: "ctx") { try? await Task.sleep(for: .milliseconds(80)); return true }
check(!ok.refused, "not refused before the answer")
let first = try? await ok.take()
check(first == "ctx", "the first signature waits for Face ID and takes its context")
let second = try? await ok.take()
check(second == nil, "a second signature asks Face ID itself (one Face ID signs once)")
check(await ok.passed() && !ok.refused, "passed, and not refused")

print("turned down")
let no = FaceIDAhead(context: "ctx") { false }
var threw = false
do { _ = try await no.take() } catch is FaceIDAhead<String>.Refused { threw = true } catch {}
check(threw, "a Face ID turned down at the tap signs nothing")
check(no.refused, "refused is known once answered")
let late = FaceIDAhead(context: "ctx") { false }
check(!(await late.passed()) && late.refused, "passed() answers no and records it")

exit(failures == 0 ? 0 : 1)
SWIFT

wiring() {
  local key="$1" move="$2"
  strip() { grep -v '^[[:space:]]*//' "$1"; }
  local SIGN; SIGN=$(strip "$key" | awk '/private static func sign\(_ digest: \[UInt8\], item:/,/^    }/')
  print -r -- "$SIGN" | grep -q 'let context = try await ahead?.take() ?? LAContext()' \
    || { echo "  ✗ the signature no longer takes the Face ID asked at the tap"; return 1; }
  print -r -- "$SIGN" | grep -q 'authenticationContext: context' \
    || { echo "  ✗ the Enclave key is not given the context"; return 1; }
  strip "$key" | grep -c '@TaskLocal static var ahead: FaceIDAhead<LAContext>?' > /dev/null \
    || { echo "  ✗ YourAccountKey.ahead is gone"; return 1; }
  local UA; UA=$(strip "$key" | awk '/static func unlockAhead\(reason/,/^    }/')
  print -r -- "$UA" | grep -q 'guard biometric else { return nil }' \
    || { echo "  ✗ a key with no Face ID on it is asked Face ID at the tap"; return 1; }
  print -r -- "$UA" | grep -q 'evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics' \
    || { echo "  ✗ the ahead does not ask the policy the key is made under (biometryCurrentSet)"; return 1; }

  local TAP; TAP=$(strip "$move" | awk '/    private func sign\(\) \{/,/^    }/')
  print -r -- "$TAP" | grep -q 'let unlock = YourAccountKey.unlockAhead(reason: reason)' \
    || { echo "  ✗ Move no longer asks Face ID at the tap"; return 1; }
  # Asked before the work starts, never after it.
  local a w
  a=$(print -r -- "$TAP" | grep -n 'let unlock = YourAccountKey.unlockAhead' | head -1 | cut -d: -f1)
  w=$(print -r -- "$TAP" | grep -n 'let work = Task {' | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$w" ]] && (( a < w )) \
    || { echo "  ✗ Face ID is asked after the send's work begins"; return 1; }
  print -r -- "$TAP" | grep -A1 'try await YourAccountKey.$ahead.withValue(unlock) {' | grep -q 'try await Self.spend(batch' \
    || { echo "  ✗ the send does not carry the Face ID it asked"; return 1; }
  print -r -- "$TAP" | grep -A4 'if await unlock.passed() {' | grep -q 'work.cancel()' \
    || { echo "  ✗ a turned-down Face ID leaves the reads running"; return 1; }
  print -r -- "$TAP" | grep -q 'if unlock?.refused == true { say(String(localized: "Not sent"), failure: true); return }' \
    || { echo "  ✗ a turned-down Face ID is said as a read that failed"; return 1; }
  print -r -- "$TAP" | grep -q 'unlock?.context.invalidate()' \
    || { echo "  ✗ a Face ID still up outlives the send"; return 1; }
  # Read whole first: `grep -q` leaving a 5,000-line pipe early is a SIGPIPE
  # that pipefail reads as a failure.
  local MOVEALL; MOVEALL=$(strip "$move")
  print -r -- "$MOVEALL" | grep -c 'case .signing: return faceIDPassed ? String(localized: "Preparing…") : String(localized: "Confirm with Face ID")' > /dev/null \
    || { echo "  ✗ the foot asks for Face ID after it passed"; return 1; }
  return 0
}

echo "FaceIDAhead, compiled whole"
swiftc -Onone -o "$TMP/run" "$PURE" "$TMP/main.swift" > "$TMP/build.log" 2>&1 \
  || { sed -n '1,30p' "$TMP/build.log"; echo "✗ the harness did not compile"; exit 1; }
"$TMP/run" || { echo "✗ faceid-ahead self-test failed"; exit 1; }

echo "the wiring"
wiring "$KEY" "$MOVE" || { echo "✗ faceid-ahead self-test failed"; exit 1; }
echo "  ✓ asked at the tap, carried to the signature, refused ends it, the foot honest"

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$PURE" "$WORK/FaceIDAhead.swift"; cp "$KEY" "$WORK/key.swift"; cp "$MOVE" "$WORK/move.swift"
  local target
  case "$file" in
    "$PURE") target="$WORK/FaceIDAhead.swift" ;;
    "$KEY") target="$WORK/key.swift" ;;
    "$MOVE") target="$WORK/move.swift" ;;
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
    if ! swiftc -Onone -o "$TMP/mut" "$WORK/FaceIDAhead.swift" "$TMP/main.swift" 2>/dev/null; then
      echo "  ✓ $name (rejected at compile)"; return
    fi
    if "$TMP/mut" > /dev/null 2>&1; then
      echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
    fi
  else
    if wiring "$WORK/key.swift" "$WORK/move.swift" > /dev/null 2>&1; then
      echo "  ✗ $name — the wiring check still passed, so nothing was testing this"; exit 1
    fi
  fi
  echo "  ✓ $name"
}

mutate "one Face ID signs every signature" "$PURE" \
  'return !taken' 'return true'
mutate "a turned-down Face ID still signs" "$PURE" \
  'guard await passed() else { throw Refused() }' '_ = await passed()'
mutate "refused never recorded" "$PURE" \
  'lock.withLock { answer = ok }' '_ = ok'
mutate "the signature ignores the ahead" "$KEY" \
  'let context = try await ahead?.take() ?? LAContext()' 'let context = LAContext()'
mutate "a key with no Face ID asked Face ID" "$KEY" \
  'guard biometric else { return nil }' ''
mutate "Move asks no Face ID at the tap" "$MOVE" \
  'let unlock = YourAccountKey.unlockAhead(reason: reason)' 'let unlock: FaceIDAhead<LAContext>? = nil'
mutate "the send does not carry it" "$MOVE" \
  'try await YourAccountKey.$ahead.withValue(unlock) {' 'try await YourAccountKey.$ahead.withValue(nil) {'
mutate "a turned-down Face ID leaves the reads running" "$MOVE" \
  '                    work.cancel()' '                    _ = work'
mutate "a turned-down Face ID said as a failed read" "$MOVE" \
  'if unlock?.refused == true { say(String(localized: "Not sent"), failure: true); return }' ''
mutate "the foot asks for Face ID after it passed" "$MOVE" \
  'case .signing: return faceIDPassed ? String(localized: "Preparing…") : String(localized: "Confirm with Face ID")' 'case .signing: return String(localized: "Confirm with Face ID")'

echo
echo "✓ faceid-ahead self-test passed"
