#!/bin/zsh
# zerion-lane-selftest.sh — the Zerion lane (prd §934): one request at a
# time, spaced, and a 429 waited out on a bounded schedule.
#
# `ZerionLane` is Foundation-only, so this compiles `Model/ZerionLane.swift`
# alone and drives it: eight concurrent `run`s finish in the order they were
# queued and never overlap; consecutive starts are at least `spacing` apart;
# `delay(attempt:retryAfter:)` honours a numeric Retry-After capped at
# `maxWait`, ignores an HTTP-date, doubles from `firstWait`, and returns nil
# once the attempts are spent. Three mutations prove the assertions bite, and
# each is checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/ZerionLane.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }
TMP=$(mktemp -d /tmp/zerion-lane-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
final class Log: @unchecked Sendable {
    let lock = NSLock()
    var order: [Int] = []
    var inFlight = 0
    var overlap = false
    var starts: [Date] = []
    func begin(_ i: Int) {
        lock.lock(); inFlight += 1; if inFlight > 1 { overlap = true }; starts.append(Date()); lock.unlock()
    }
    func end(_ i: Int) { lock.lock(); inFlight -= 1; order.append(i); lock.unlock() }
}
let log = Log()
let sema = DispatchSemaphore(value: 0)
Task {
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<8 {
            group.addTask {
                _ = await ZerionLane.shared.run {
                    log.begin(i)
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    log.end(i)
                    return i
                }
            }
            // Queue in order — a tiny stagger so submission order is the claim.
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
    sema.signal()
}
sema.wait()
check(log.order == Array(0..<8), "eight queued runs finish in submission order, got \(log.order)")
check(!log.overlap, "no two runs were in flight at once")
let gaps = zip(log.starts.dropFirst(), log.starts).map { $0.timeIntervalSince($1) }
check(gaps.allSatisfy { $0 >= ZerionLane.spacing * 0.9 }, "consecutive starts are spaced ≥ \(ZerionLane.spacing)s, got \(gaps.map { String(format: "%.3f", $0) })")

check(ZerionLane.delay(attempt: 1, retryAfter: nil) == ZerionLane.firstWait, "first wait is firstWait")
check(ZerionLane.delay(attempt: 2, retryAfter: nil) == ZerionLane.firstWait * 2, "second wait doubles")
check(ZerionLane.delay(attempt: ZerionLane.attempts, retryAfter: nil) == nil, "the attempts are spent at \(ZerionLane.attempts)")
check(ZerionLane.delay(attempt: 0, retryAfter: nil) == nil, "attempt 0 is not a retry")
check(ZerionLane.delay(attempt: 1, retryAfter: "3") == 3, "a numeric Retry-After is honoured")
check(ZerionLane.delay(attempt: 1, retryAfter: " 2 ") == 2, "Retry-After is trimmed")
check(ZerionLane.delay(attempt: 1, retryAfter: "600") == ZerionLane.maxWait, "Retry-After is capped at maxWait")
check(ZerionLane.delay(attempt: 1, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT") == ZerionLane.firstWait, "an HTTP-date Retry-After falls to the backoff")
check(ZerionLane.delay(attempt: 1, retryAfter: "-1") == ZerionLane.firstWait, "a negative Retry-After falls to the backoff")
check((ZerionLane.delay(attempt: 2, retryAfter: nil) ?? 0) <= ZerionLane.maxWait, "no wait exceeds maxWait")
let t0 = Date(timeIntervalSince1970: 1_000_000)
check(ZerionLane.exhaustion(status: 429, dayRemaining: "0", dayReset: "29070", now: t0) == t0.addingTimeInterval(29070), "a refusal with the day's pool at zero names the reset")
check(ZerionLane.exhaustion(status: 200, dayRemaining: "0", dayReset: "29070", now: t0) == nil, "a 200 with zero remaining is the last one through, not a refusal")
check(ZerionLane.exhaustion(status: 429, dayRemaining: "46", dayReset: "29070", now: t0) == nil, "a refusal with pool left is the per-second limit, not exhaustion")
check(ZerionLane.exhaustion(status: 429, dayRemaining: nil, dayReset: "29070", now: t0) == nil, "no remaining header, no exhaustion")
check(ZerionLane.exhaustion(status: 429, dayRemaining: "0", dayReset: "9999999", now: t0) == t0.addingTimeInterval(86_400), "the reset is capped at a day")
check(ZerionLane.exhaustion(status: 429, dayRemaining: "0", dayReset: "0", now: t0) == nil, "a zero reset is not an exhaustion")
check(ZerionLane.spacing >= 1.0, "the spacing honours the measured one-a-second demo tier")
if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT
compile_and_run() {
    swiftc -O "$1" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" || { cat "$TMP/err" | head -20; return 2; }
    "$TMP/run"
}
echo "zerion-lane self-test"
compile_and_run "$SRC" || { echo "✗ the lane fails its own self-test"; exit 1; }
echo "  ok   the lane serialises, spaces and waits out a 429 on schedule"

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
mutate "the lane no longer waits for the previous request" 's/await previous\?\.value\n/\n/'
mutate "the spacing is dropped" 's/if gap > 0 \{ try\? await Task\.sleep/if false { try? await Task.sleep/'
mutate "Retry-After is not capped" 's/return min\(seconds, maxWait\)/return seconds/'
mutate "the attempts never run out" 's/guard attempt >= 1, attempt < attempts else \{ return nil \}/guard attempt >= 1 else { return nil }/'
mutate "a 200 with zero remaining closes the pool" 's/guard status == 429,\n/guard status == 429 || status == 200,\n/'
mutate "the reset is not capped" 's/min\(reset, 86_400\)/reset/'
echo "  ok   6 mutations"
