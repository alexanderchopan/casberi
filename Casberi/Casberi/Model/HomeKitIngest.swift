import Foundation
import HomeKit
import SwiftData

/// The HomeKit bridge (2026-07-17) — a system read bridge, like Contacts and
/// Calendar: the permission ask arrives in context (instantiating
/// `HMHomeManager` triggers it), connect ends in proof. Read-only: Casberi
/// never controls an accessory.
///
/// Scope, stated honestly: HomeKit has no historical-event query API —
/// accessory state changes are push-only (delegate callbacks while an app or
/// long-lived observer runs), so there is no way to backfill "what happened
/// while the app was closed" the way Calendar/Contacts refresh does. V1
/// therefore lands each accessory as a LIVE-STATE reference thing (room +
/// category), refreshed in place — a dashboard entry, not a growing event
/// history. Search-only, like Contacts (`Corpus.searchOnlySources`): a house
/// full of accessories re-updating every refresh shouldn't bury the feed.
enum HomeKitIngest {

    @MainActor private static var running = false

    static func connectAndIngest(context: ModelContext) async -> Int? {
        await ingest(context: context)
    }

    /// The bare re-scan foreground refresh calls. HomeKit has no synchronous
    /// "already granted?" check independent of loading homes, so this runs
    /// the same wait-for-homes path as connect — safe to call every
    /// foreground, since the system only ever prompts once.
    static func refresh(context: ModelContext) async -> Int? {
        await ingest(context: context)
    }

    @MainActor
    private static func ingest(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }

        let bridge = HomeManagerBridge()
        await bridge.waitForHomes()
        guard bridge.manager.authorizationStatus.contains(.authorized) else { return nil }

        let homes = bridge.manager.homes
        let existingThings = (try? context.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "HomeKit" })
        )) ?? []
        var bySourceRef: [String: Thing] = [:]
        for t in existingThings { if let ref = t.sourceRef { bySourceRef[ref] = t } }

        var landed: [Thing] = []
        var updated: [Thing] = []
        var seen = Set<String>()
        for home in homes {
            for accessory in home.accessories {
                let ref = "homekit:accessory:\(accessory.uniqueIdentifier.uuidString)"
                seen.insert(ref)
                let line = self.line(for: accessory, home: home)
                let encoded = self.facts(for: accessory, home: home,
                                         multiHome: homes.count > 1).map(\.encoded)
                if let existing = bySourceRef[ref] {
                    // Either half can move on its own: reachability flips
                    // without the room changing, and a rename changes the
                    // sentence without changing the state. `moved` rather than
                    // an append per half, so a pass that changed both doesn't
                    // hand the same accessory to Spotlight twice.
                    var moved = false
                    if existing.content != line { existing.content = line; moved = true }
                    if existing.facts != encoded { existing.facts = encoded; moved = true }
                    if moved { updated.append(existing) }
                } else {
                    let thing = Thing(kind: .accessory, title: accessory.name,
                                      content: line, source: "HomeKit", sourceRef: ref)
                    thing.facts = encoded
                    context.insert(thing)
                    landed.append(thing)
                }
            }
        }
        // RECONCILE: an accessory unpaired (or a whole home removed) stops
        // appearing in `homes` — its Thing is LIVE STATE, not a record, so a
        // stale row here is worse than for the activity bridges. A
        // momentarily empty `homes` (iCloud homes still syncing) must not
        // read as "every accessory vanished" — only reconcile when the read
        // actually found a home to walk.
        var removedIDs: [UUID] = []
        if !homes.isEmpty {
            for (ref, thing) in bySourceRef where !seen.contains(ref) {
                removedIDs.append(thing.id)
                context.delete(thing)
            }
        }
        // Re-index updated accessories too — a state change (e.g. Reachable →
        // Unreachable) rewrites the Thing's content, and without this the
        // system Search index keeps showing the old text indefinitely (only
        // brand-new accessories were ever passed to SpotlightIndex before).
        let toIndex = landed + updated
        if !toIndex.isEmpty { SpotlightIndex.index(toIndex) }
        if !removedIDs.isEmpty { SpotlightIndex.remove(ids: removedIDs) }
        if !toIndex.isEmpty || !removedIDs.isEmpty { context.saveHonestly() }
        return landed.count
    }

    /// What an accessory is and where, un-joined (2026-08-12, prd §365).
    ///
    /// REACHABILITY LEADS and is a `.state` fact, not a word in a sentence.
    /// This row is the only one in the corpus that is pure LIVE STATE — the
    /// ingest re-reads it on every foreground and reconciles it — and until now
    /// the sheet rendered a reachable lock and an unreachable one identically,
    /// in the same grey prose. Which of the two it is happens to be the entire
    /// reason to open the sheet.
    ///
    /// The home's name is included only when there is more than one. For the
    /// overwhelmingly common single-home setup it is a row that says the same
    /// thing on every accessory you own.
    private static func facts(for accessory: HMAccessory, home: HMHome,
                              multiHome: Bool) -> [ThingFact] {
        var out: [ThingFact] = [
            ThingFact("Checked just now",
                      accessory.isReachable ? "Reachable" : "Unreachable", .state),
            ThingFact("Type", category(for: accessory)),
        ]
        if let room = accessory.room?.name, !room.isEmpty {
            out.append(ThingFact("Room", room))
        }
        if multiHome, !home.name.isEmpty {
            out.append(ThingFact("Home", home.name))
        }
        // What the thing actually IS (2026-08-14). These are plain properties
        // on `HMAccessory` — no characteristic read, no pairing, none of what
        // the decline below rules out — and they answer the question a
        // category can't: "Lock" is every lock you own, "Aqara · A100" is the
        // one whose app you need and whose battery you are about to buy.
        //
        // Model only when it isn't the manufacturer repeated, which some
        // accessories do report.
        let maker = (accessory.manufacturer ?? "").trimmingCharacters(in: .whitespaces)
        let model = (accessory.model ?? "").trimmingCharacters(in: .whitespaces)
        switch (maker.isEmpty, model.isEmpty) {
        case (false, false) where maker.caseInsensitiveCompare(model) != .orderedSame:
            out.append(ThingFact("Made by", "\(maker) · \(model)"))
        case (false, _): out.append(ThingFact("Made by", maker))
        case (true, false): out.append(ThingFact("Model", model))
        case (true, true): break
        }
        return out
    }

    /// Room + a plain-English category — reachability instead of a decoded
    /// characteristic value (a lock's actual locked/unlocked state needs
    /// per-service-type reads this app can't verify without a paired
    /// accessory or the HomeKit Accessory Simulator; honest v1 stops here).
    ///
    /// Kept beside `facts` above rather than retired by it: this is the string
    /// `Retriever.rank` scores and Spotlight indexes, so an accessory stays
    /// findable by its room. The facts are what the sheet draws.
    private static func line(for accessory: HMAccessory, home: HMHome) -> String {
        var parts: [String] = [category(for: accessory)]
        if let room = accessory.room?.name { parts.append(room) }
        parts.append(accessory.isReachable ? "Reachable" : "Unreachable")
        return parts.joined(separator: " · ")
    }

    private static func category(for accessory: HMAccessory) -> String {
        switch accessory.category.categoryType {
        case HMAccessoryCategoryTypeDoor:       return "Door"
        case HMAccessoryCategoryTypeDoorLock:   return "Lock"
        case HMAccessoryCategoryTypeGarageDoorOpener: return "Garage door"
        case HMAccessoryCategoryTypeWindow:     return "Window"
        case HMAccessoryCategoryTypeWindowCovering: return "Window covering"
        case HMAccessoryCategoryTypeLightbulb:  return "Light"
        case HMAccessoryCategoryTypeSwitch:     return "Switch"
        case HMAccessoryCategoryTypeSensor:     return "Sensor"
        case HMAccessoryCategoryTypeThermostat: return "Thermostat"
        case HMAccessoryCategoryTypeSecuritySystem: return "Security system"
        case HMAccessoryCategoryTypeVideoDoorbell: return "Doorbell"
        case HMAccessoryCategoryTypeIPCamera:   return "Camera"
        case HMAccessoryCategoryTypeFan:        return "Fan"
        case HMAccessoryCategoryTypeOutlet:     return "Outlet"
        case HMAccessoryCategoryTypeSprinkler:  return "Sprinkler"
        default:                                return "Accessory"
        }
    }
}

/// A tiny delegate bridge — `HMHomeManager` has no closure-based access
/// request (unlike `CNContactStore`), so a one-shot continuation over its
/// delegate callback stands in for one.
private final class HomeManagerBridge: NSObject, HMHomeManagerDelegate {
    let manager = HMHomeManager()
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Bounded — measured 2026-07-17: `homeManagerDidUpdateHomes` never fires
    /// at all on the iOS Simulator (no homes, no permission prompt, silence),
    /// and even on a real device the connect flow shouldn't hang forever if
    /// the callback is ever dropped. 20s is generous for a human answering
    /// the real system permission alert.
    func waitForHomes(timeout: Duration = .seconds(20)) async {
        await withCheckedContinuation { cont in
            lock.lock(); continuation = cont; lock.unlock()
            Task {
                try? await Task.sleep(for: timeout)
                self.resume()
            }
        }
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        resume()
    }

    private func resume() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
