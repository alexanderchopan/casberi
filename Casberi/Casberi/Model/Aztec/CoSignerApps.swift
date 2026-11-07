import Foundation
import SwiftData

/// **THE APPS YOUR CO-SIGNER SIGNS INTO (prd §1700l items 11 and 13).** What
/// Apps on Aztec's browser keeps of the co-signer's work for apps, on this
/// iPhone only: which sites you signed into with it, so their Connect leads
/// with it next time and says so; and each send it made for one, as a
/// Wallet Activity row with Etherscan its door.
enum CoSignerApps {
    private static let hostsKey = "aztecBrowser.coSignerHosts.v1"

    /// The sites you last connected with your co-signer.
    static var hosts: [String] {
        UserDefaults.standard.data(forKey: hostsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    static func remembers(_ host: String) -> Bool { hosts.contains(host.lowercased()) }

    /// Kept when a site connects with your co-signer, let go when it
    /// connects with your account: the last choice stands.
    static func remember(_ host: String, coSigner: Bool) {
        let key = host.lowercased()
        var list = hosts.filter { $0 != key }
        if coSigner { list.append(key) }
        guard list != hosts, let data = try? JSONEncoder().encode(list) else { return }
        DefaultsWrite.set(data, forKey: hostsKey)
    }

    static let activityPrefix = "cosigner:"

    /// One Wallet row per transaction the co-signer sent for an app.
    @MainActor
    static func land(hash: String, title: String, context: ModelContext) {
        let ref = activityPrefix + hash.lowercased()
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return }
        context.insert(Thing(kind: .link, title: title, content: PrivateMoney.explorerTx(hash.lowercased(), chainId: 1),
                             source: "Wallet", capturedAt: .now, sourceRef: ref))
        try? context.save()
        NSLog("coSignerApps| landed | %@", title)
    }
}
