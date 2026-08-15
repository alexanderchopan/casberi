import Foundation
import Observation

/// Friendlier names for the semantic map's clusters (2026-08-15, prd §386j).
///
/// A cluster is named by `AgentPanelFigures.scatter` with the TERM its members
/// actually share — "onchain", "eth", "kitchen" — which is honest and
/// sometimes ugly. This upgrades that term to something a person would write
/// ("Onchain", "Kitchen reno"), and the discipline is the whole design:
///
/// **The model NAMES, it never narrates.** One or two words, in place of a
/// word we already have. That is the §282 librarian doctrine — the model
/// organizes the corpus rather than writing about it — and it is the exact
/// inverse of the `dayRead` paragraph §386a retired, which is why this is a
/// good use of the same engine that was a bad one there.
///
/// **It is never awaited by a compose.** §386a's headline win was taking the
/// brief's only model await off the compose path, and a cluster name is not
/// worth giving that back: `name(for:)` is a synchronous cache read that
/// falls through to the raw term, and `refresh` runs on the foreground sweep
/// like `HomeInsightStore` does ("computed OFF the render path and painted on
/// the next compose"). A device without Apple Intelligence, and a device that
/// simply hasn't gotten to a term yet, both draw the same honest map.
///
/// **A name is asked for ONCE, ever.** The ledger records the attempt rather
/// than the answer, so a term the model declined is not re-asked on every
/// foreground for the life of the install — the same rule
/// `ScreenshotNaming`'s own id ledger keeps.
@MainActor
@Observable
final class ClusterNames {
    static let shared = ClusterNames()

    private static let namesKey = "cluster.names"
    private static let askedKey = "cluster.named.asked"
    /// How many terms one pass will name. The map draws at most six clusters
    /// and they are stable across days, so a small budget catches up within a
    /// couple of foregrounds and then costs nothing.
    private static let perPass = 3

    private var names: [String: String]
    private var asked: Set<String>
    /// Terms the map has drawn and nobody has named yet. In-memory: the map
    /// re-notes them on every compose, so a relaunch loses nothing.
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var running = false

    private init() {
        let d = UserDefaults.standard
        names = d.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        asked = Set(d.stringArray(forKey: Self.askedKey) ?? [])
    }

    /// The display name for a cluster term — the model's, or the term itself
    /// title-cased. Synchronous and total: the map always has something to
    /// draw, and a missing name is invisible rather than an empty label.
    nonisolated func name(for term: String) -> String {
        MainActor.assumeIsolated {
            if let named = names[term.lowercased()], !named.isEmpty { return named }
            // Title-case the raw term as the floor — "onchain" reads as a
            // label, "Onchain" reads as a name, and that much needs no model.
            return term.prefix(1).uppercased() + term.dropFirst()
        }
    }

    /// The terms the map actually drew, recorded so the sweep knows what is
    /// worth naming. Called from `TodayBrief.clusterMap` — cheap, synchronous
    /// and never a model call, because compose must stay off that path.
    func note(terms: [String]) {
        let fresh = terms.map { $0.lowercased() }.filter { !asked.contains($0) }
        guard !fresh.isEmpty else { return }
        pending.formUnion(fresh)
        // Bounded: the map draws at most six clusters, so a runaway pending
        // set means something upstream changed, not that there is more work.
        if pending.count > 60 { pending = Set(pending.prefix(60)) }
    }

    /// Names up to `perPass` pending terms. Called from the foreground sweep,
    /// never from a compose. No-op without the on-device model, so nothing
    /// here can spend anyone's battery on a device that cannot answer.
    func refresh() async {
        guard !running, OnDeviceModel.isAvailable else { return }
        let pending = self.pending
            .filter { !asked.contains($0) }
            .sorted()
            .prefix(Self.perPass)
        guard !pending.isEmpty else { return }
        running = true
        defer { running = false }
        for term in pending {
            asked.insert(term)
            self.pending.remove(term)
            if let named = await OnDeviceModel.clusterName(term: term) {
                names[term] = named
            }
        }
        persist()
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(names, forKey: Self.namesKey)
        // Capped — the ledger is a "don't ask twice" record, not an archive.
        d.set(Array(asked.suffix(400)), forKey: Self.askedKey)
    }

    #if DEBUG
    /// `-clusterNameProbe YES` support — what is named and what is pending.
    func debugSummary() -> String {
        "named=\(names.count) asked=\(asked.count)"
    }
    #endif
}
