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
    ///
    /// THE DEMO REACHES NOTHING (2026-08-15) — gated HERE, at the function that
    /// does the read, the same pattern `WalletIngest.holdings()` already uses.
    /// It was not: `WalletScreen.onAppear` calls `WalletStore.loadAvatars()`
    /// directly, bypassing `BridgeRefresh`'s demo early-return entirely, and
    /// nothing downstream caught it — `verify.sh`'s "Demo reaches nothing"
    /// check found `api.ensideas.com` reached for the demo's fabricated
    /// address, once its own false-positive noise (a dirty NetworkLedger) was
    /// fixed the same day. A gate on the one caller would leave every future
    /// caller exposed to the same miss; gating the three functions here closes
    /// it structurally.
    ///
    /// **web3.bio alone (prd §916; the ensideas fallback deleted by §1573).**
    /// web3.bio answers Basenames and Linea names, and its records are what
    /// `NameResolve.primaryNames` reads for the linked Lens/Base rows — so the
    /// forward check §599 requires runs against the same service that made
    /// the claim. ensideas was the fallback until ENSv2 activated
    /// (2026-10-27): it answers ENS's own test name `ur.integration-tests.eth`
    /// with `0x1111…`, the outdated-resolver answer, where web3.bio answers
    /// the current `0x2222…`. A fallback that can name the WRONG address is
    /// worse than none, so an outage now resolves nothing.
    static func resolve(_ raw: String) async -> String? {
        guard !DemoMode.isActive else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeName(name) else { return nil }
        guard let hex = await Web3Bio.resolve(name), isHexAddress(hex) else { return nil }
        return hex
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
        guard !DemoMode.isActive else { return nil }
        let addr = hexAddress.lowercased()
        guard isHexAddress(addr) else { return nil }
        if let cached = reverseCache[addr] { return cached }
        // web3.bio alone (prd §916, §1573): the ENS record whose own address
        // is this one. `names(for:)` already drops the rows web3.bio linked
        // through its graph, so the forward check in `NameResolve` is the
        // only other bar left to clear.
        let name = await Web3Bio.names(for: addr).first(where: { $0.platform == .ens })?.identity
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
        guard !DemoMode.isActive else { return nil }
        let key = hexOrName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = avatarCache[key] { return cached }
        let avatar = await Web3Bio.avatar(for: key)
        avatarCache[key] = avatar
        return avatar
    }
}
