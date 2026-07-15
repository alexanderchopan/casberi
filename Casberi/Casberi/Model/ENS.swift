import Foundation

/// ENS resolution (2026-07-09) — the wallet field invites "0x… or ENS", but
/// Alchemy's Transfers and Portfolio APIs only accept a hex `0x` address, so a
/// watched ENS name (vitalik.eth) silently returned nothing. This resolves a
/// name to its address through a public ENS resolver — the same shape as every
/// other read the app makes: public data, no key, no account, nothing about the
/// person leaves the device but the (public) name they're looking up.
enum ENS {

    /// True when the string is already a hex address (no resolution needed).
    static func isHexAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    /// True when the string looks like an ENS name worth resolving (has a dot,
    /// isn't already hex) — `.eth`, `.box`, and the other ENS TLDs.
    static func looksLikeName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains(".") && !t.lowercased().hasPrefix("0x")
    }

    /// Resolves an ENS name to its `0x` address, or nil (not a name, no record,
    /// or the resolver was unreachable). A no-op for input that's already hex.
    static func resolve(_ raw: String) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeName(name),
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let root = await IngestSupport.getJSON(
                "https://api.ensideas.com/ens/resolve/\(encoded)") as? [String: Any],
              let address = root["address"] as? String,
              isHexAddress(address)
        else { return nil }
        return address
    }

    /// The primary name an address goes by, when it set one — reverse
    /// resolution through the same resolver (counterparty naming on wallet
    /// transfers, 2026-07-14: "Received 0.2 ETH from vitalik.eth" is a story;
    /// a bare hash is a receipt). Cached per launch INCLUDING misses — a
    /// wallet's counterparties repeat, and a nameless address must not cost
    /// a lookup on every refresh forever. Main-actor because WalletIngest
    /// (the only caller) already is.
    @MainActor private static var reverseCache: [String: String?] = [:]

    @MainActor
    static func reverseName(for hexAddress: String) async -> String? {
        let addr = hexAddress.lowercased()
        guard isHexAddress(addr) else { return nil }
        if let cached = reverseCache[addr] { return cached }
        var name: String?
        if let root = await IngestSupport.getJSON(
            "https://api.ensideas.com/ens/resolve/\(addr)") as? [String: Any],
           let n = root["name"] as? String, !n.isEmpty {
            name = n
        }
        reverseCache[addr] = name
        return name
    }

    /// The avatar an address (or name) set on its ENS profile — the same
    /// public resolve the counterparty naming uses, reading the `avatar`
    /// field the resolver already returns alongside the name (2026-07-15,
    /// wallet faces). Only a plain http(s) URL is handed back: ENS also
    /// allows `eip155:` NFT-token avatars, which need a token-metadata
    /// gateway to become an image — those fall through to nil so the caller
    /// draws the deterministic identicon instead of a broken image. Cached
    /// per launch INCLUDING misses (a faceless address must not cost a
    /// lookup every foreground). Main-actor because WalletStore, the only
    /// caller, already is.
    @MainActor private static var avatarCache: [String: String?] = [:]

    @MainActor
    static func avatar(for hexOrName: String) async -> String? {
        let key = hexOrName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = avatarCache[key] { return cached }
        var avatar: String?
        if let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let root = await IngestSupport.getJSON(
            "https://api.ensideas.com/ens/resolve/\(encoded)") as? [String: Any],
           let a = root["avatar"] as? String,
           a.hasPrefix("http") {
            avatar = a
        }
        avatarCache[key] = avatar
        return avatar
    }
}
