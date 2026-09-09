#!/bin/zsh
# Casberi save-coalescer self-test (prd §658, 2026-09-08) — proves that a
# foreground sweep's ~45 per-bridge saves become a handful, and that nothing
# else is ever held.
#
#   Casberi/Shared/SaveHonestly.swift  (compiled VERBATIM, against SwiftData)
#     — saveHonestly   outside a bridge pass: saves NOW, reports the outcome
#     — SaveCoalescer  inside one (the `landing` task-local): one save per
#                      burst, after `quietMs` of silence or `maxLatencyMs`
#                      from the first request, whichever is sooner
#     — inheritance    a child `Task {}` inside a pass is held with it; a
#                      `Task.detached` is not — the boundary the bridges'
#                      pure-compute hops already stand on
#     — flushNow       writes what is held, at once (the background hook)
#     — census         `count` is real saves, `requested` is asks; the sweep
#                      line prints both, which is the whole measurement
#
# WHY A HARNESS: every failure mode here is invisible on a green build. A
# coalescer that never coalesces is 45 saves a sweep again, each re-running
# every mounted `@Query` (§646) — the exact cost this replaced, and the app
# renders perfectly. A coalescer that holds a pin, a delete or an edit makes
# the feed answer a tap a second late. A cap that stops working holds a
# sweep's rows for as long as the sweep runs. The simulator cannot tell any
# of these from a working one without a stopwatch on the save count, and
# this file IS that stopwatch: the driver counts `ModelContext.didSave`.
#
# MEASURED FIRST (2026-09-08): the main context's autosave does not fire
# between explicit saves — ten inserts 30ms apart, zero saves in 1.5s — so the
# explicit saves are the re-emissions, and coalescing them is coalescing the
# feed's re-materialisations one for one. That probe is test 0 below, kept so
# the premise is re-checked on every toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."

SAVE="Casberi/Shared/SaveHonestly.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
ROOT_SHELL="Casberi/Casberi/Shell/RootShell.swift"
SWEEP="Casberi/Casberi/Shell/SweepClock.swift"
for f in "$SAVE" "$REFRESH" "$ROOT_SHELL" "$SWEEP"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

strip() { sed -E 's://.*$::' "$1"; }
need() { grep -qF -- "$2" <<< "$(strip "$1")" || { echo "✗ $3"; echo "   (missing in $1: $2)"; exit 1; }; }

# --- drift guards -----------------------------------------------------------
# Every sweep slot runs under the flag. A bare `Task {` followed by the
# stagger is a slot whose save is NOT coalesced — one is enough to bring a
# full re-materialisation back, silently.
bare=$(strip "$REFRESH" | awk '/Task \{ @MainActor in[[:space:]]*$/ && !/landingTask/ {t=NR; next} t && NR==t+1 && /await BridgeRefresh.stagger\(/ {n++} {t=0} END{print n+0}')
[[ "$bare" == "0" ]] || { echo "✗ $bare sweep slot(s) in BridgeRefresh run as a bare Task — their saves are not coalesced"; exit 1; }
slots=$(strip "$REFRESH" | grep -c 'BridgeRefresh.landingTask { @MainActor in' || true)
(( slots >= 40 )) || { echo "✗ only $slots landingTask slots in BridgeRefresh — the sweep's slots stopped going through the coalescer"; exit 1; }
need "$REFRESH" 'await SaveCoalescer.$landing.withValue(true) { await work() }' \
  "landingTask no longer raises the task-local — every slot's save is immediate again"
need "$ROOT_SHELL" 'SaveCoalescer.flushNow()' \
  "RootShell no longer flushes the coalescer on background — a held save could die with the process"
need "$SWEEP" 'asked=%d' \
  "the sweepPass| line lost asked= — saves and asks must sit on ONE line, or the coalescer's effect cannot be read"
need "$SAVE" 'if SaveCoalescer.landing, Thread.isMainThread {' \
  "saveHonestly no longer defers inside a pass"
echo "✓ save-coalescer drift guards green"

# --- the coalescer, compiled verbatim ---------------------------------------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
import SwiftData

@Model final class Item { var name: String; init(name: String) { self.name = name } }

var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { print("✗ \(msg)"); failures += 1 } }
func ms(_ n: Int) async { try? await Task.sleep(for: .milliseconds(n)) }

@MainActor func run() async throws {
    let c = try ModelContainer(for: Item.self, configurations: .init(isStoredInMemoryOnly: true))
    let ctx = c.mainContext
    var saves = 0
    let obs = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in saves += 1 }
    defer { NotificationCenter.default.removeObserver(obs) }

    // 0. The premise: autosave does not fire between explicit saves.
    for i in 0..<10 { ctx.insert(Item(name: "a\(i)")); await ms(30) }
    await ms(600)
    check(saves == 0 && ctx.hasChanges, "premise: the main context autosaved on its own (\(saves)) — the coalescer's arithmetic no longer holds")

    // 1. Outside a pass: immediate, honest.
    let t1 = ctx.saveHonestly()
    check(t1 && saves == 1 && !ctx.hasChanges, "a save outside a pass is immediate (saves=\(saves))")

    // 2. Inside a pass: a burst is one save, after the quiet window.
    saves = 0
    let asked0 = SaveCensus.requested, count0 = SaveCensus.count
    await SaveCoalescer.$landing.withValue(true) {
        for i in 0..<5 {
            ctx.insert(Item(name: "b\(i)"))
            check(ctx.saveHonestly(), "a deferred save reports true")
            await ms(20)
        }
        check(saves == 0, "no save ran inside the burst (saves=\(saves))")
        check(SaveCoalescer.isHolding, "the coalescer reports it is holding")
        // Pending rows are visible to a fetch on the same context.
        let n = (try? ctx.fetchCount(FetchDescriptor<Item>(predicate: #Predicate { $0.name == "b3" }))) ?? -1
        check(n == 1, "a pending insert is visible to fetchCount (\(n))")
    }
    await ms(SaveCoalescer.quietMs + 150)
    check(saves == 1, "five asks in a burst became ONE save (saves=\(saves))")
    check(SaveCensus.requested - asked0 == 5, "requested counts asks (\(SaveCensus.requested - asked0))")
    check(SaveCensus.count - count0 == 1, "count counts real saves (\(SaveCensus.count - count0))")
    check(!ctx.hasChanges && !SaveCoalescer.isHolding, "nothing left pending after the flush")

    // 3. The cap: a stream of asks cannot hold a save past maxLatencyMs.
    saves = 0
    let start = Date()
    var firstSaveAt: TimeInterval? = nil
    await SaveCoalescer.$landing.withValue(true) {
        while Date().timeIntervalSince(start) < 1.8 {
            ctx.insert(Item(name: "c"))
            ctx.saveHonestly()
            await ms(150)
            if saves > 0, firstSaveAt == nil { firstSaveAt = Date().timeIntervalSince(start) }
        }
    }
    await ms(SaveCoalescer.quietMs + 150)
    check(firstSaveAt != nil, "a save ran under a continuous stream of asks")
    if let firstSaveAt {
        let capS = Double(SaveCoalescer.maxLatencyMs) / 1000
        check(firstSaveAt <= capS + 0.35, "the first save landed within the cap (\(Int(firstSaveAt * 1000))ms vs \(SaveCoalescer.maxLatencyMs)ms)")
        check(firstSaveAt >= 0.25, "the first save was not immediate (\(Int(firstSaveAt * 1000))ms)")
    }
    check(saves >= 2 && saves <= 4, "1.8s of asks every 150ms became a few saves, not twelve (saves=\(saves))")

    // 4. Inheritance: a child Task is held with the pass, a detached one is not.
    saves = 0
    await SaveCoalescer.$landing.withValue(true) {
        let child = Task { @MainActor in ctx.insert(Item(name: "d")); ctx.saveHonestly() }
        await child.value
        check(saves == 0, "a child Task inside a pass inherits the hold (saves=\(saves))")
        let detached = Task.detached { @MainActor in ctx.insert(Item(name: "e")); ctx.saveHonestly() }
        await detached.value
        check(saves == 1, "a detached Task inside a pass saves at once (saves=\(saves))")
    }
    await ms(SaveCoalescer.quietMs + 150)
    // The detached save wrote the child's row with its own; the held flush
    // then had nothing to write and wrote nothing.
    check(saves == 1 && !ctx.hasChanges && !SaveCoalescer.isHolding,
          "a flush with nothing left to write writes nothing (saves=\(saves))")

    // 5. flushNow writes what is held, at once.
    saves = 0
    await SaveCoalescer.$landing.withValue(true) {
        ctx.insert(Item(name: "f")); ctx.saveHonestly()
        SaveCoalescer.flushNow()
        check(saves == 1 && !ctx.hasChanges, "flushNow wrote the held save immediately (saves=\(saves))")
    }
    await ms(SaveCoalescer.quietMs + 150)
    check(saves == 1, "nothing was written twice after a flushNow (saves=\(saves))")

    // 6. A save asked for with nothing held is not repeated by the timer.
    saves = 0
    SaveCoalescer.flushNow()
    check(saves == 0, "flushNow with nothing pending saves nothing")
}
let sem = DispatchSemaphore(value: 0)
Task { @MainActor in
    do { try await run() } catch { print("✗ threw \(error)"); failures += 1 }
    sem.signal()
}
while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
if failures > 0 { print("✗ save-coalescer self-test: \(failures) failure(s)"); exit(1) }
print("✓ save-coalescer self-test: 22 assertions green")
SWIFT

build() { # build <dir> <save.swift>
  swiftc -O "$2" "$TMP/main.swift" -o "$1/run" 2>&1 | grep -v "warning:" | grep -E "error" && return 1
  [[ -x "$1/run" ]]
}
mkdir -p "$TMP/real"
build "$TMP/real" "$SAVE" || { echo "✗ the harness does not compile against $SAVE"; exit 1; }
"$TMP/real/run" || exit 1

# --- mutations: each restores a pre-fix shape and must be CAUGHT -------------
mutate() { # mutate <name> <perl expression>
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  perl -0777 -pe "$2" "$SAVE" > "$dir/SaveHonestly.swift"
  if cmp -s "$dir/SaveHonestly.swift" "$SAVE"; then echo "✗ mutation '$1' changed nothing — its anchor drifted"; exit 1; fi
  if build "$dir" "$dir/SaveHonestly.swift" && "$dir/run" >/dev/null 2>&1; then
    echo "✗ mutation '$1' SURVIVED — the harness cannot see it"; exit 1
  fi
}
mutate "saves inside a pass are immediate again" \
  's/if SaveCoalescer\.landing, Thread\.isMainThread \{/if false {/'
mutate "the latency cap is gone" \
  's/let wait = max\(0, min\(Double\(quietMs\), Double\(maxLatencyMs\) - sinceFirst\)\)/let wait = Double(quietMs)/'
mutate "a flushed save is not counted" \
  's/try context\.save\(\)\n            SaveCensus\.count \+= 1/try context.save()/'
mutate "flushNow no longer writes" \
  's/guard let context = pending else \{ return \}/guard let context = pending, false else { return }/'
mutate "a request no longer re-arms the timer" \
  's/flushTask\?\.cancel\(\)\n        flushTask = Task/flushTask = Task/'
echo "✓ save-coalescer self-test: 5 mutations caught, 7 drift guards"
