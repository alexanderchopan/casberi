import Foundation

/// The reads behind `WeiNames` (prd §597, 2026-09-04) — kept apart from the
/// encoders so that file stays Foundation-only and its harness can compile it
/// whole. Everything here is a keyless `eth_call` on Ethereum mainnet through
/// `WalletApprovals.rpcRead`, whose hosts are already declared in
/// `NetworkReach`: **this seat adds no host, no key and no account.**
enum WeiNamesSource {

    /// Mainnet, always. Both registries are deployed there and this app never
    /// asks anywhere else — a name is one global fact, not a per-chain one.
    private static let network = "eth-mainnet"

    /// `AerodromeDeFi`'s pacer, and for its reason: a forward resolve is two
    /// sequential calls and filling a book row is up to six, so an unpaced
    /// pass arrives at a shared public host as a burst. MEASURED 2026-09-04:
    /// an unpaced run of these exact reads drew `execution reverted`-shaped
    /// failures out of `eth.drpc.org` that a paced run, seconds later against
    /// the same host, did not.
    private actor RequestPacer {
        private var last: Date = .distantPast
        func wait(_ interval: TimeInterval) async {
            let elapsed = Date.now.timeIntervalSince(last)
            if elapsed < interval {
                try? await Task.sleep(nanoseconds: UInt64((interval - elapsed) * 1_000_000_000))
            }
            last = .now
        }
    }
    private static let pacer = RequestPacer()

    private static func ethCall(to: String, data: String) async -> String? {
        await pacer.wait(0.2)
        return await WalletApprovals.rpcRead(
            network: network, method: "eth_call",
            params: [["to": to, "data": data], "latest"]) as? String
    }

    // MARK: - Forward

    /// `alice.wei` → its address, or nil — not a WNS/GNS name, nobody has
    /// taken it, or the chain did not answer.
    ///
    /// THE DEMO REACHES NOTHING, gated here at the function that does the read
    /// — `ENS.resolve`'s own rule, and for the reason recorded there: gating
    /// the one caller leaves every future caller exposed.
    static func resolve(_ raw: String) async -> String? {
        guard !DemoMode.isActive,
              let registry = WeiNames.registry(claiming: raw) else { return nil }
        return await resolve(WeiNames.canonical(raw), in: registry)
    }

    /// The same read with the registry already decided — the verification leg
    /// below calls this, and must not re-derive a registry from a name the
    /// chain handed us.
    private static func resolve(_ canonical: String, in registry: WeiNames.Registry) async -> String? {
        guard let idReturn = await ethCall(to: registry.contract,
                                           data: WeiNames.computeIdCalldata(canonical)),
              let idWord = WeiNames.tokenIdWord(from: idReturn),
              let data = WeiNames.resolveCalldata(idWord: idWord),
              let addressReturn = await ethCall(to: registry.contract, data: data)
        else { return nil }
        // `WeiNames.address(from:)` is what refuses the zero address, which is
        // the ONLY "nobody has taken this" signal either registry gives — see
        // its own doc for what believing an id instead would watch.
        return WeiNames.address(from: addressReturn)
    }

    // MARK: - Reverse

    /// The primary name this address chose on one registry, or nil.
    ///
    /// **FORWARD-VERIFIED, always.** A reverse record is a claim the address
    /// makes about itself, and this app prints it in its own chrome beside
    /// money — so the name is only believed once resolving it comes back to
    /// the same address. Both real cases round-tripped when measured, but that
    /// showed those two are consistent, not that the contracts enforce it, and
    /// neither contract's source has been read here. ENSIP-3 requires the same
    /// check on ENS for the same reason: without it a stranger's address can
    /// present as `vitalik.wei` (§83, on the screen where it costs most).
    ///
    /// The verification costs two calls and is spent only on a NON-EMPTY
    /// answer, which is the rare case — most addresses have set no primary
    /// name on either registry.
    static func primaryName(for address: String,
                            in registry: WeiNames.Registry) async -> String? {
        guard !DemoMode.isActive,
              let data = WeiNames.reverseCalldata(address: address),
              let returned = await ethCall(to: registry.contract, data: data),
              let name = WeiNames.string(from: returned).map(WeiNames.canonical)
        else { return nil }
        // The answer must belong to the registry that gave it. A WNS record
        // reading `foo.gwei` is not a name this contract can speak for, and
        // resolving it here would ask the wrong contract about it.
        guard WeiNames.registry(claiming: name) == registry else { return nil }
        guard let back = await resolve(name, in: registry),
              back.caseInsensitiveCompare(address) == .orderedSame else { return nil }
        return name
    }

    /// Every registry's primary name for one address, in `Registry.allCases`
    /// order. Empty is the ordinary answer, not a failure.
    static func primaryNames(for address: String) async -> [(WeiNames.Registry, String)] {
        guard ENS.isHexAddress(address) else { return [] }
        var out: [(WeiNames.Registry, String)] = []
        for registry in WeiNames.Registry.allCases {
            if let name = await primaryName(for: address, in: registry) {
                out.append((registry, name))
            }
        }
        return out
    }

    /// How many names an address HOLDS on one registry — `balanceOf`, which
    /// both registries answer.
    ///
    /// Deliberately a COUNT and never a list: neither contract is
    /// `ERC721Enumerable` (`tokenOfOwnerByIndex` and `totalSupply` both
    /// revert, measured), so the ids cannot be walked on-chain and listing
    /// them would mean an indexer — Alchemy credits against a shared-key
    /// ceiling, for a book that has no cap. A count is the honest fact that
    /// costs one call, and `0x1c0a…5a20` holding 79 `.wei` names is why a
    /// list would be the wrong reading anyway.
    static func heldCount(for address: String,
                          in registry: WeiNames.Registry) async -> Int? {
        guard !DemoMode.isActive,
              let word = WeiNames.addressWord(address) else { return nil }
        let data = "0x" + WeiNames.selector("balanceOf(address)") + word
        guard let returned = await ethCall(to: registry.contract, data: data),
              let value = WeiNames.word(returned, 0) else { return nil }
        // A balance is small; a word that does not fit an Int is a malformed
        // answer rather than a wallet holding 2^64 names.
        return Int(value.drop(while: { $0 == "0" }).isEmpty
                   ? "0" : String(value.drop(while: { $0 == "0" })), radix: 16)
    }

    #if DEBUG
    /// `-weiNameProbe <name|0x…|YES>` — the read, step by step.
    ///
    /// It exists because every interesting answer here is a SILENCE with
    /// several causes and only one of them is a bug: a name shows no address
    /// because nobody has taken it, because the chain did not answer, or
    /// because the suffix was routed to the wrong registry; an address shows
    /// no name because it set none (the ordinary case), because the reverse
    /// record failed to verify, or because the read never ran. The `id=` and
    /// `verified=` clauses are what separate them in one launch.
    ///
    /// ONE LINE PER FACT — a joined NSLog is truncated past its own length
    /// limit and silently drops the later ones (the `-todayProbe` lesson).
    @MainActor
    static func probe(_ spec: String) async -> [String] {
        var lines: [String] = ["demo=\(DemoMode.isActive ? "ACTIVE — every read returns nil" : "off")"]
        let asked = spec.trimmingCharacters(in: .whitespacesAndNewlines)

        if let registry = WeiNames.registry(claiming: asked) {
            let canonical = WeiNames.canonical(asked)
            lines.append("forward \(canonical) → \(registry.serviceName) \(registry.contract)")
            guard let idReturn = await ethCall(to: registry.contract,
                                               data: WeiNames.computeIdCalldata(canonical)),
                  let idWord = WeiNames.tokenIdWord(from: idReturn) else {
                lines.append("  computeId UNREACHABLE — the chain did not answer")
                return lines
            }
            lines.append("  id=0x\(idWord)")
            guard let data = WeiNames.resolveCalldata(idWord: idWord),
                  let returned = await ethCall(to: registry.contract, data: data) else {
                lines.append("  resolve UNREACHABLE")
                return lines
            }
            // The zero address is the ONLY unregistered signal — said out
            // loud, because a real id above it looks like a real name.
            lines.append("  → \(WeiNames.address(from: returned) ?? "nobody (zero address — unregistered)")")
            return lines
        }

        var addresses: [String] = []
        if ENS.isHexAddress(asked) { addresses = [asked] }
        else {
            addresses = WalletStore.shared.addresses.map(\.address).filter(ENS.isHexAddress)
            lines.append("no name or address given — reading the \(addresses.count) watched wallet(s)")
        }
        guard !addresses.isEmpty else {
            lines.append("nothing to read: watch a wallet, or pass a name or 0x address")
            return lines
        }
        for address in addresses {
            lines.append("reverse \(address)")
            if let ens = await ENS.reverseName(for: address) {
                lines.append("  ENS  \(ens)")
            } else {
                lines.append("  ENS  none")
            }
            for registry in WeiNames.Registry.allCases {
                guard let data = WeiNames.reverseCalldata(address: address),
                      let returned = await ethCall(to: registry.contract, data: data) else {
                    lines.append("  \(registry.label.padding(toLength: 4, withPad: " ", startingAt: 0)) UNREACHABLE")
                    continue
                }
                guard let raw = WeiNames.string(from: returned).map(WeiNames.canonical) else {
                    lines.append("  \(registry.label.padding(toLength: 4, withPad: " ", startingAt: 0)) none")
                    continue
                }
                // Reported apart from the name: an answer that fails the
                // forward check is the one shape here that means somebody is
                // claiming a name they do not hold, and it must never read
                // like an ordinary miss.
                let verified = await primaryName(for: address, in: registry) != nil
                lines.append("  \(registry.label.padding(toLength: 4, withPad: " ", startingAt: 0)) \(raw) verified=\(verified ? "YES" : "NO — NOT SHOWN")")
                if let held = await heldCount(for: address, in: registry) {
                    lines.append("       holds \(held) \(registry.suffix) name(s)")
                }
            }
        }
        return lines
    }
    #endif
}
