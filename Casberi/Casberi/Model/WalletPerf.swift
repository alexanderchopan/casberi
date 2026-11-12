import Foundation

/// The Wallet's three waits, timed (docs/specs/wallet-perf-spec.md Phase 0).
///
/// - **Open**: the Wallet tab tapped → its last reading drawn.
/// - **Current**: a holdings read asked → the live total returned, split into
///   the holdings read and the extras the combined total adds after it.
/// - **Pass**: `WalletIngest.refresh` entered → returned, with each rider's
///   time and the requests the pass spent.
///
/// Every reading lands in `PerfReadings` (`-perfReadingsProbe` prints them),
/// once per event, never from a body. `-walletPerf YES` also logs a
/// `walletPerf|` line per event and per rider, in Release as in Debug, the
/// way `-launchTimer` does.
///
/// Counting costs a lock and an add per request; nothing here runs per row.
enum WalletPerf {

    static let logs: Bool = UserDefaults.standard.bool(forKey: "walletPerf")

    private static let lock = NSLock()
    nonisolated(unsafe) private static var zerion = 0
    nonisolated(unsafe) private static var alchemy = 0
    nonisolated(unsafe) private static var sampleDecodes = 0
    nonisolated(unsafe) private static var openAsked: Date?

    // MARK: - Counters

    /// One request leaving the funnel (`IngestSupport`), counted by host.
    static func countRequest(host: String?) {
        guard let host = host?.lowercased() else { return }
        let isZerion = host.hasSuffix("zerion.io")
        let isAlchemy = host.contains("alchemy.com")
        guard isZerion || isAlchemy else { return }
        lock.lock()
        if isZerion { zerion += 1 } else { alchemy += 1 }
        lock.unlock()
    }

    /// One balance history decoded from defaults (`WalletStore`).
    static func countSampleDecode() {
        lock.lock(); sampleDecodes += 1; lock.unlock()
    }

    struct Counts: Equatable { var zerion = 0, alchemy = 0, sampleDecodes = 0 }

    static func counts() -> Counts {
        lock.lock(); defer { lock.unlock() }
        return Counts(zerion: zerion, alchemy: alchemy, sampleDecodes: sampleDecodes)
    }

    static func since(_ start: Counts) -> Counts {
        let now = counts()
        return Counts(zerion: now.zerion - start.zerion, alchemy: now.alchemy - start.alchemy,
                      sampleDecodes: now.sampleDecodes - start.sampleDecodes)
    }

    static func words(_ c: Counts) -> String {
        "zerion=\(c.zerion) alchemy=\(c.alchemy) decodes=\(c.sampleDecodes)"
    }

    // MARK: - Open

    /// The Wallet tab was tapped.
    static func openBegan() {
        lock.lock(); openAsked = Date(); lock.unlock()
    }

    /// The Wallet just drew a figure. Recorded on the next turn of the main
    /// run loop, after the frame holding it commits; the defaults write never
    /// happens inside the body pass that called this.
    @MainActor
    static func openDrew() {
        lock.lock()
        let asked = openAsked
        openAsked = nil
        lock.unlock()
        guard let asked else { return }
        DispatchQueue.main.async {
            let ms = Date().timeIntervalSince(asked) * 1000
            PerfReadings.record("WalletOpen", ms: ms)
            if logs { NSLog("[Casberi] walletPerf| open ms=%.0f", ms) }
        }
    }

    // MARK: - Current

    static func current(ms: Double, holdingsMs: Double, extrasMs: Double, combined: Bool, counts: Counts) {
        let note = "holdings \(Int(holdingsMs))ms · extras \(Int(extrasMs))ms\(combined ? "" : " · scoped")"
        PerfReadings.record("WalletCurrent", ms: ms, note: note)
        if logs {
            NSLog("[Casberi] walletPerf| current ms=%.0f holdings=%.0f extras=%.0f combined=%@ %@",
                  ms, holdingsMs, extrasMs, combined ? "yes" : "no", words(counts))
        }
    }

    // MARK: - Pass

    /// One sweep pass's clock, kept by `WalletIngest.refresh`.
    @MainActor
    final class Pass {
        let began = Date()
        let start = WalletPerf.counts()
        private var riders: [(String, Double)] = []

        /// Times one rider. Same isolation as the caller, so the closure can
        /// hold the pass's context exactly as the call did before.
        func rider<T>(_ name: String, _ op: () async -> T) async -> T {
            let t0 = Date()
            let value = await op()
            let ms = Date().timeIntervalSince(t0) * 1000
            riders.append((name, ms))
            if WalletPerf.logs {
                NSLog("[Casberi] walletPerf| rider %@ ms=%.0f at=%.0f", name, ms,
                      Date().timeIntervalSince(began) * 1000)
            }
            return value
        }

        /// A point in the pass (transfers landed, say), logged only.
        func mark(_ name: String) {
            guard WalletPerf.logs else { return }
            NSLog("[Casberi] walletPerf| mark %@ at=%.0f", name, Date().timeIntervalSince(began) * 1000)
        }

        func end(added: Int?) {
            let ms = Date().timeIntervalSince(began) * 1000
            let spent = WalletPerf.since(start)
            let slowest = riders.max { $0.1 < $1.1 }
            var note = WalletPerf.words(spent)
            if let slowest { note += " · slowest \(slowest.0) \(Int(slowest.1))ms" }
            PerfReadings.record("WalletPass", ms: ms, note: note)
            if WalletPerf.logs {
                NSLog("[Casberi] walletPerf| pass ms=%.0f added=%@ %@", ms,
                      added.map(String.init) ?? "unreached", note)
            }
        }
    }
}
