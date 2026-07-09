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
}
