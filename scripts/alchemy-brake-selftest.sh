#!/bin/zsh
# alchemy-brake-selftest.sh — the Alchemy brake (2026-10-20): a 429 holds
# EVERY Alchemy request on the phone, not one, then lets them go spaced.
#
# `AlchemyBrake` is Foundation-only, so this compiles `Model/AlchemyBrake.swift`
# alone and drives it on a fixed clock: only Alchemy's hosts brake; the pause
# runs 2s, 4s, 8s, capped at `maxPause`; requests queued behind a pause are let
# go `releaseGap` apart; a success clears the run; a later, shorter 429 never
# shortens a longer pause; a 5xx does not brake. It also asserts the USE:
# `IngestSupport.send` waits its turn before sending and reports the status
# after, or the brake is a type nothing calls. Five mutations prove the
# assertions bite, each checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/AlchemyBrake.swift"
FUNNEL="Casberi/Casberi/Model/IngestSupport.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }
echo "alchemy-brake self-test"
grep -q 'if braked { await AlchemyBrake.shared.waitForTurn() }' "$FUNNEL" \
    || { echo "✗ IngestSupport.send no longer waits for the brake before sending"; exit 1; }
grep -q 'if braked { await AlchemyBrake.shared.note(status: http.statusCode) }' "$FUNNEL" \
    || { echo "✗ IngestSupport.send no longer reports Alchemy's status to the brake"; exit 1; }
echo "  ok   the funnel waits for the brake and reports to it"
TMP=$(mktemp -d /tmp/alchemy-brake-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func near(_ a: TimeInterval, _ b: TimeInterval) -> Bool { abs(a - b) < 0.001 }
let t0 = Date(timeIntervalSince1970: 1_000_000)

check(AlchemyBrake.brakes(host: "eth-mainnet.g.alchemy.com"), "an RPC host brakes")
check(AlchemyBrake.brakes(host: "API.G.ALCHEMY.COM"), "a host brakes whatever its case")
check(!AlchemyBrake.brakes(host: "alchemy.com.example.io"), "a lookalike host does not brake")
check(!AlchemyBrake.brakes(host: "notalchemy.com"), "a host merely ending in the name does not brake")
check(!AlchemyBrake.brakes(host: "api.zerion.io"), "another provider does not brake")
check(!AlchemyBrake.brakes(host: nil), "no host does not brake")

check(AlchemyBrake.pause(strikes: 0) == 0, "no strikes, no pause")
check(AlchemyBrake.pause(strikes: 1) == 2, "the first 429 holds 2s")
check(AlchemyBrake.pause(strikes: 2) == 4, "the second doubles")
check(AlchemyBrake.pause(strikes: 3) == 8, "the third doubles again")
check(AlchemyBrake.pause(strikes: 9) == AlchemyBrake.maxPause, "a long run is capped at maxPause")
check(AlchemyBrake.pause(strikes: 500) == AlchemyBrake.maxPause, "a very long run is capped and does not overflow")

let sema = DispatchSemaphore(value: 0)
Task {
    let fresh = AlchemyBrake()
    check(await fresh.admission(now: t0) == 0, "an unbraked request goes at once")
    check(await fresh.admission(now: t0) == 0, "and so does the next: no gap without a pause")

    let b = AlchemyBrake()
    await b.note(status: 429, now: t0)
    let w1 = await b.admission(now: t0), w2 = await b.admission(now: t0), w3 = await b.admission(now: t0)
    check(near(w1, 2), "the first request after a 429 waits the pause, got \(w1)")
    check(near(w2, 2 + AlchemyBrake.releaseGap), "the next is let go releaseGap later, got \(w2)")
    check(near(w3, 2 + 2 * AlchemyBrake.releaseGap), "and the next after it, got \(w3)")
    check(await b.admission(now: t0.addingTimeInterval(60)) == 0, "once the queue has drained, requests go at once again")

    let run = AlchemyBrake()
    await run.note(status: 429, now: t0)
    await run.note(status: 429, now: t0)
    check(near(await run.admission(now: t0), 4), "a second 429 in a row holds 4s")
    await run.note(status: 200, now: t0.addingTimeInterval(100))
    await run.note(status: 429, now: t0.addingTimeInterval(100))
    check(near(await run.admission(now: t0.addingTimeInterval(100)), 2), "a success clears the run: the next 429 holds 2s again")

    let keep = AlchemyBrake()
    await keep.note(status: 429, now: t0)
    await keep.note(status: 429, now: t0)
    await keep.note(status: 429, now: t0)          // held to t0 + 8
    await keep.note(status: 200, now: t0)
    await keep.note(status: 429, now: t0.addingTimeInterval(1))   // would be t0 + 3
    check(near(await keep.admission(now: t0.addingTimeInterval(1)), 7), "a shorter 429 never shortens a longer pause")

    let server = AlchemyBrake()
    await server.note(status: 503, now: t0)
    await server.note(status: 0, now: t0)
    check(await server.admission(now: t0) == 0, "a 5xx or a dropped connection does not brake")
    sema.signal()
}
sema.wait()
if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT
compile_and_run() {
    swiftc -O "$1" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" || { cat "$TMP/err" | head -20; return 2; }
    "$TMP/run"
}
compile_and_run "$SRC" || { echo "✗ the brake fails its own self-test"; exit 1; }
echo "  ok   the brake holds every request, releases them spaced and clears on success"

mutate() {
    local name="$1" perl_expr="$2"
    cp "$SRC" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$SRC" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    if compile_and_run "$TMP/mut.swift" >/dev/null 2>&1; then
        echo "✗ SURVIVED  $name"; exit 1
    fi
    echo "  ok   catches  $name"
}
mutate "requests behind a pause are let go all at once" 's/nextRelease = slot\.addingTimeInterval\(Self\.releaseGap\)/nextRelease = slot/'
mutate "a success no longer clears the run" 's/(\(200\.\.\.299\)\.contains\(status\) \{\n\s*)strikes = 0/${1}_ = 0/'
mutate "the pause is not capped" 's/return min\(maxPause, (pow\(2, Double\(min\(strikes, 10\)\)\))\)/return $1/'
mutate "a lookalike host brakes" 's/host\.hasSuffix\("\.alchemy\.com"\)/host.contains("alchemy.com")/'
mutate "a shorter 429 shortens a longer pause" 's/pausedUntil = max\(pausedUntil, (now\.addingTimeInterval\(Self\.pause\(strikes: strikes\)\))\)/pausedUntil = $1/'
echo "  ok   5 mutations"
