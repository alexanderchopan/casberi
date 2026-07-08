import Foundation
import Observation
import SwiftData

/// The Bankr bridge (2026-07-07) — read-only, by ruling. Bankr is agent
/// infrastructure whose users LAUNCH TOKENS; the tokens a creator address
/// launched are public, served with no key by Bankr's own API. So this is a
/// read bridge in the Zerion/Bluesky mold: paste your creator address, the
/// tokens you launched land as link things. Casberi never trades — Bankr's
/// own docs expose no approval flow, and executing a trade isn't ours to do.
@Observable
final class BankrStore {
    static let shared = BankrStore()
    private static let key = "bankr.address"

    var address: String {
        didSet { UserDefaults.standard.set(address, forKey: Self.key) }
    }

    private init() {
        address = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    /// A pasted address, lowercased. Bare or 0x-prefixed both work; anything
    /// that isn't a 42-char hex address stays as typed (the fetch returns
    /// nothing and the screen says so).
    static func normalize(_ raw: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let slash = a.lastIndex(of: "/") { a = String(a[a.index(after: slash)...]) }
        if !a.hasPrefix("0x"), a.count == 40 { a = "0x" + a }
        return a
    }

    static func isAddress(_ a: String) -> Bool {
        a.hasPrefix("0x") && a.count == 42
            && a.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}

enum BankrIngest {

    @MainActor private static var running = false

    /// Fetches every token the creator address launched and lands new ones as
    /// link things. Returns the new count, or nil when the address is malformed
    /// or the API can't be reached.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let address = BankrStore.shared.address
        guard BankrStore.isAddress(address), !running else {
            return running ? 0 : nil
        }
        running = true
        defer { running = false }

        // Public creator-fees endpoint — unauthenticated, per Bankr's docs.
        guard let root = await IngestSupport.getJSON(
            "https://api.bankr.bot/public/doppler/creator-fees/\(address)?days=30")
                as? [String: Any],
              let tokens = root["tokens"] as? [[String: Any]] else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0

        for token in tokens {
            guard let tokenAddress = token["tokenAddress"] as? String else { continue }
            let ref = "bankr:\(tokenAddress.lowercased())"
            guard !existing.contains(ref) else { continue }

            let name = (token["name"] as? String) ?? "Token"
            let symbol = (token["symbol"] as? String).map { "$\($0)" } ?? ""
            let title = symbol.isEmpty ? name : "\(name) · \(symbol)"

            let thing = Thing(
                kind: .link,
                title: title,
                content: "https://dexscreener.com/base/\(tokenAddress)",
                source: "Bankr",
                capturedAt: .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
