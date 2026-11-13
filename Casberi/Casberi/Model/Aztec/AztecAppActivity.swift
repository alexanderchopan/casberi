import Foundation
import SwiftData

/// **AN APP'S TRANSACTION IN THE WALLET'S ACTIVITY (prd §1764).** A send
/// Casberi made for an Aztec app left no trace: RavenHouse minted, the
/// account paid, and Activity said nothing. Each one lands as a Wallet row
/// named by the site and its calls, opening the site.
enum AztecAppActivity {
    static let activityPrefix = "aztecapp:"

    /// "RavenHouse — mint to private", "RavenHouse — authorized set authorized".
    static func title(host: String, calls: [String], authorization: Bool) -> String {
        let named = calls.filter { !$0.isEmpty }.prefix(3).map { $0.replacingOccurrences(of: "_", with: " ") }
        let what = named.isEmpty ? String(localized: "a transaction") : named.joined(separator: ", ")
        return TitleSeam.join(AztecAppsShape.name(host: host),
                              authorization ? String(localized: "authorized \(what)") : what)
    }

    @MainActor
    static func land(origin: String?, calls: [String], transaction: String, authorization: Bool) {
        guard !transaction.isEmpty, let origin, let door = AztecAppsShape.door(URL(string: origin)),
              let host = URL(string: door)?.host(percentEncoded: false),
              let context = SharedStore.live?.mainContext else { return }
        let ref = activityPrefix + transaction.lowercased()
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return }
        let title = title(host: host, calls: calls, authorization: authorization)
        context.insert(Thing(kind: .link, title: title, content: door, source: "Wallet", capturedAt: .now, sourceRef: ref))
        try? context.save()
        NSLog("aztecApp| landed | %@", title)
    }
}
