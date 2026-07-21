import Foundation

/// Solana Name Service resolution (2026-07-16) — `ENS`'s sibling, pointed at
/// Solana. `toly.sol` resolves through Bonfida's public SNS proxy: the same
/// shape as every other read the app makes — public data, no key, no account,
/// nothing about the person leaves the device but the (public) name they're
/// looking up.
///
/// Why a second resolver rather than a branch inside `ENS`: the two families
/// disagree on everything that matters here. Different resolvers, different
/// address alphabets (hex vs base58), and — the load-bearing one — different
/// pipelines downstream. A hex address reads transfers AND holdings; a Solana
/// address reads holdings only (`alchemy_getAssetTransfers` is EVM-only). The
/// wallet has to know which it got, so the two stay separable by shape.
enum SNS {

    /// Base58's alphabet — Bitcoin/Solana's, which drops the four glyphs that
    /// misread by eye (0, O, I, l). Excluding `0` is also what keeps this test
    /// disjoint from `ENS.isHexAddress`: a `0x…` address can never be base58.
    private static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// True when the string is already a Solana address. A pubkey is 32 bytes
    /// base58-encoded, which lands at 32–44 characters.
    static func isAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...44).contains(t.count) else { return false }
        return t.allSatisfy { base58.contains($0) }
    }

    /// True when the string looks like a `.sol` name worth resolving. Narrower
    /// than `ENS.looksLikeName` (which takes any dotted string) on purpose —
    /// `.sol` is SNS's only TLD, and the wallet field tries this resolver first,
    /// so a loose test here would swallow `vitalik.eth`.
    static func looksLikeName(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".sol")
    }

    /// Resolves `toly.sol` to its Solana address, or nil (not a `.sol` name, no
    /// record, or the resolver was unreachable). The proxy takes the domain
    /// WITHOUT its `.sol` suffix and answers `{"s":"ok","result":"<address>"}`.
    static func resolve(_ raw: String) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard looksLikeName(name) else { return nil }
        let domain = String(name.dropLast(4))
        guard !domain.isEmpty, !domain.contains("."),   // subdomains aren't served by /resolve
              let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let root = await IngestSupport.getJSON(
                "https://sns-sdk-proxy.bonfida.workers.dev/resolve/\(encoded)") as? [String: Any],
              (root["s"] as? String) == "ok",
              let address = root["result"] as? String,
              isAddress(address)
        else { return nil }
        return address
    }
}
