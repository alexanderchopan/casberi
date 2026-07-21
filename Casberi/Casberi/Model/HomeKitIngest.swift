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
        for home in homes {
            for accessory in home.accessories {
                let ref = "homekit:accessory:\(accessory.uniqueIdentifier.uuidString)"
                let line = self.line(for: accessory, home: home)
                if let existing = bySourceRef[ref] {
                    if existing.content != line {
                        existing.content = line
                        updated.append(existing)
                    }
                } else {
                    let thing = Thing(kind: .accessory, title: accessory.name,
                                      content: line, source: "HomeKit", sourceRef: ref)
                    context.insert(thing)
                    landed.append(thing)
                }
            }
        }
        // Re-index updated accessories too — a state change (e.g. Reachable →
        // Unreachable) rewrites the Thing's content, and without this the
        // system Search index keeps showing the old text indefinitely (only
        // brand-new accessories were ever passed to SpotlightIndex before).
        let toIndex = landed + updated
        if !toIndex.isEmpty { SpotlightIndex.index(toIndex) }
        if !toIndex.isEmpty { context.saveHonestly() }
        return landed.count
    }

    /// Room + a plain-English category — reachability instead of a decoded
    /// characteristic value (a lock's actual locked/unlocked state needs
    /// per-service-type reads this app can't verify without a paired
    /// accessory or the HomeKit Accessory Simulator; honest v1 stops here).
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
