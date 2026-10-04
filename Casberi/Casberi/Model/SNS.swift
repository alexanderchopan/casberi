import Foundation

/// Solana Name Service resolution (2026-07-16) — `ENS`'s sibling, pointed at
/// Solana. `toly.sol` resolves through web3.bio (Bonfida's proxy until it went
/// dark, see `resolve`): the same shape as every other read the app makes — public data, no key, no account,
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
    /// record, or the resolver was unreachable).
    ///
    /// **Through web3.bio since 2026-10-03.** Bonfida's public proxy
    /// (`sns-sdk-proxy.bonfida.workers.dev`), which this read used from
    /// 2026-07-16, answers every path with a Cloudflare 404 / `error code: 1042`
    /// — measured on `/resolve/toly`, `/resolve/bonfida` and the reverse
    /// routes — so every `.sol` name the app was asked for silently resolved
    /// to nothing. web3.bio already answers ENS here and serves SNS in the same
    /// shape (`toly.sol` → `86xC…2MMY`, measured), so the fix adds no provider:
    /// it removes one.
    @MainActor
    static func resolve(_ raw: String) async -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard looksLikeName(name), name.count > 4,
              let address = await Web3Bio.resolve(name), isAddress(address)
        else { return nil }
        return address
    }

    /// The `.sol` name an address chose as its primary, or nil — forward-
    /// verified (prd §599): the name must resolve back to this exact address
    /// before it is believed, the bar every other reverse name here meets.
    @MainActor
    static func primaryName(for address: String) async -> String? {
        guard isAddress(address) else { return nil }
        for record in await Web3Bio.names(for: address) where record.platform == .sns {
            if await Web3Bio.verified(record, is: address) { return record.identity }
        }
        return nil
    }
}
