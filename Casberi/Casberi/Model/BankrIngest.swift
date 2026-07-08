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

    /// A treemap of the creator's launches, each tile a token sized by the
    /// fees it earned — Bankr's real data as the app's own chart idiom (the
    /// same TagMap Home and Zerion use). Live, no demo gate: creator-fees is
    /// public. Returns nil when there's nothing to chart.
    @MainActor
    static func launchesChart() async -> [String]? {
        let address = BankrStore.shared.address
        guard BankrStore.isAddress(address) else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://api.bankr.bot/public/doppler/creator-fees/\(address)?days=30")
                as? [String: Any],
              let tokens = root["tokens"] as? [[String: Any]], !tokens.isEmpty
        else { return nil }

        var cells: [String] = []
        for token in tokens.prefix(6) {
            let symbol = ((token["symbol"] as? String) ?? "TOKEN")
                .uppercased().filter(\.isLetter)
            let claimed = feeAmount(token["claimed"])
            let claimable = feeAmount(token["claimable"])
            // sqrt compresses the range so a big earner doesn't slice the rest
            // into unreadable slivers (the Zerion treemap lesson).
            let value = max(1, Int((claimed + claimable).squareRoot() * 1000))
            cells.append("\(symbol.isEmpty ? "TOKEN" : symbol) \(value)")
        }
        return [
            "root = Stack([m])",
            "m = TagMap(\"Your launches\", \"By fees earned\", [\(cells.joined(separator: ", "))])",
        ]
    }

    /// The WETH side (token0) of a claimed/claimable object, as a Double.
    private static func feeAmount(_ raw: Any?) -> Double {
        guard let obj = raw as? [String: Any] else { return 0 }
        if let s = obj["token0"] as? String { return Double(s) ?? 0 }
        if let n = obj["token0"] as? Double { return n }
        return 0
    }
}
