#!/bin/zsh
# zerion-lane-selftest.sh — the Zerion lane (prd §934, §1722): at most
# `concurrent` requests in flight, their starts spaced, an `ahead` request
# before every plain waiter, and a 429 waited out on a bounded schedule.
#
# `ZerionLane` is Foundation-only, so this compiles `Model/ZerionLane.swift`
# alone and drives it: eight concurrent `run`s of 1.2s each never put more
# than `concurrent` on the wire at once and start in submission order;
# consecutive starts are at least `spacing` apart; a request queued `ahead`
# behind four plain waiters starts before all four; the starts never exceed
# the tier's three a second; `delay(attempt:retryAfter:)` honours a numeric
# Retry-After capped at `maxWait`, ignores an HTTP-date, doubles from
# `firstWait`, and returns nil once the attempts are spent. Eight mutations
# prove the assertions bite, and each is checked to have CHANGED the source.
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
    var started: [Int] = []
    var inFlight = 0
    var peak = 0
    var starts: [Date] = []
    func begin(_ i: Int) {
        lock.lock(); inFlight += 1; peak = max(peak, inFlight); started.append(i); starts.append(Date()); lock.unlock()
    }
    func end(_ i: Int) { lock.lock(); inFlight -= 1; lock.unlock() }
    func reset() { lock.lock(); started = []; starts = []; peak = 0; lock.unlock() }
}
let log = Log()
let sema = DispatchSemaphore(value: 0)
// Eight requests of 1.2s each: the lane may run `concurrent` at once, so the
// pack takes about three waves; one at a time would take ten seconds.
let began = Date()
Task {
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<8 {
            group.addTask {
                _ = await ZerionLane.shared.run {
                    log.begin(i)
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
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
// A watchdog, not a bare wait: a lane that never wakes a parked request
// (one of the mutations below) would otherwise hang this test forever.
check(sema.wait(timeout: .now() + 30) == .success, "the eight runs all finished within 30s")
let took = Date().timeIntervalSince(began)
check(log.started == Array(0..<8), "eight queued runs start in submission order, got \(log.started)")
check(log.peak == ZerionLane.concurrent, "exactly \(ZerionLane.concurrent) were in flight at the peak, got \(log.peak)")
check(took < 8 * 1.2 * 0.6, "three in flight finish the pack well inside one-at-a-time's \(8 * 1.2)s, took \(String(format: "%.1f", took))s")
let gaps = zip(log.starts.dropFirst(), log.starts).map { $0.timeIntervalSince($1) }
// SPACING, ASSERTED WHERE A BUSY MACHINE CANNOT BREAK IT (2026-11-11). The
// lane spaces the SLOTS it reserves, and a start is never before its slot,
// only late. So a gap falls short by however late the start before it was:
// CI read 0.514 then 0.337 on correct code (one start 0.11s late, the next on
// time), and "every gap ≥ 0.9 × spacing" failed most pushes for a property the
// lane does not promise. What it promises is the rate, checked two ways that
// lateness cannot fake: the first wave (nothing in flight, so only spacing
// holds a start back, and the first of them never sleeps) spans its full
// width, and no gap collapses. The three-a-second check below is the tier's.
let firstWave = Array(log.starts.prefix(ZerionLane.concurrent))
let waveSpan = (firstWave.last ?? began).timeIntervalSince(firstWave.first ?? began)
check(waveSpan >= Double(ZerionLane.concurrent - 1) * ZerionLane.spacing * 0.9,
      "the first \(ZerionLane.concurrent) starts span \(ZerionLane.concurrent - 1) spacings, got \(String(format: "%.3f", waveSpan))s")
check(gaps.allSatisfy { $0 >= ZerionLane.spacing * 0.5 }, "no two starts collapse together, got \(gaps.map { String(format: "%.3f", $0) })")
for (i, t) in log.starts.enumerated() {
    let withinSecond = log.starts.filter { $0 >= t && $0 < t.addingTimeInterval(1) }.count
    check(withinSecond <= 3, "no second sees more than three starts (from start \(i): \(withinSecond))")
}

// An `ahead` request behind four plain waiters: the slots are full, four are
// parked, and the fifth, marked ahead, starts before all four of them.
log.reset()
let sema2 = DispatchSemaphore(value: 0)
Task {
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(ZerionLane.concurrent + 4) {
            group.addTask {
                _ = await ZerionLane.shared.run {
                    log.begin(i)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    log.end(i)
                    return i
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        group.addTask {
            _ = await ZerionLane.shared.run(ahead: true) {
                log.begin(99)
                log.end(99)
                return 99
            }
        }
    }
    sema2.signal()
}
check(sema2.wait(timeout: .now() + 30) == .success, "the ahead pack all finished within 30s")
if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
let plainWaiters = Array(ZerionLane.concurrent..<(ZerionLane.concurrent + 4))
let aheadAt = log.started.firstIndex(of: 99) ?? Int.max
check(aheadAt == ZerionLane.concurrent, "the ahead request takes the first freed slot, before the \(plainWaiters.count) plain waiters, order \(log.started)")

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
check(1.0 / ZerionLane.spacing <= 3.0, "the spacing never allows more starts a second than the Developer tier's three")
check(ZerionLane.concurrent <= 3, "no more in flight than the tier allows a second")
if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT
compile_and_run() {
    swiftc -O "$1" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" || { cat "$TMP/err" | head -20; return 2; }
    "$TMP/run"
}
echo "zerion-lane self-test"
compile_and_run "$SRC" || { echo "✗ the lane fails its own self-test"; exit 1; }
echo "  ok   the lane runs three, spaces, puts holdings ahead and waits out a 429 on schedule"

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
mutate "the lane admits everyone at once" 's/if inFlight < Self\.concurrent, waiting\.isEmpty \{/if true {/'
mutate "a freed slot wakes nobody" 's/waiting\.removeFirst\(\)\.resume\.resume\(\)/_ = waiting.first/'
mutate "the spacing is dropped" 's/if wait > 0 \{ try\? await Task\.sleep/if false { try? await Task.sleep/'
mutate "ahead is just another waiter" 's/waiting\.insert\(\(ahead: true, resume: c\), at: i\)/waiting.append((ahead: true, resume: c))/'
mutate "Retry-After is not capped" 's/return min\(seconds, maxWait\)/return seconds/'
mutate "the attempts never run out" 's/guard attempt >= 1, attempt < attempts else \{ return nil \}/guard attempt >= 1 else { return nil }/'
mutate "a 200 with zero remaining closes the pool" 's/guard status == 429,\n/guard status == 429 || status == 200,\n/'
mutate "the reset is not capped" 's/min\(reset, 86_400\)/reset/'
echo "  ok   8 mutations"
