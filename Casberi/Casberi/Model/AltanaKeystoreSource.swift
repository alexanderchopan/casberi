import Foundation

/// The chain half of `AltanaKeystore` (2026-08-18, prd §402) — the reads, the
/// between-pass snapshot, and the probe.
///
/// Split from the model for the reason every `*Source.swift` in this directory
/// is: the pure file is Foundation-only so `scripts/wallet-viz-selftest.sh`
/// compiles it AS SHIPPED, and everything that needs `WalletApprovals`,
/// `WalletStore` or `UserDefaults` lives here where the harness does not
/// follow.
///
/// Every call below is `eth_call` against the L1 keystore. Nothing is signed,
/// nothing is sent, and no write selector is ever constructed — see
/// `AltanaKeystore.writeSelectors`, which exists to be checked against.
extension AltanaKeystore {

    // MARK: - Reading

    /// Everything registered for one address, or nil when the registry could
    /// not be read at all.
    ///
    /// nil and an empty `Reading` are deliberately different answers: nil is
    /// "we could not ask", empty is "we asked and this wallet has nothing".
    /// Today every real wallet returns the second, so folding the first into
    /// it would hide an RPC outage behind the reassuring common case forever.
    @MainActor
    static func read(address: String) async -> Reading? {
        guard let data = encode(getKeysSelector, address: address),
              let hex = await call(data),
              let list = decodeKeyIDs(hex)
        else { return nil }

        // The whole point of the cheap gate: an unregistered wallet — which is
        // every wallet today — costs exactly one call and stops here.
        guard !list.ids.isEmpty else {
            return Reading(address: address.lowercased(), keys: [], truncated: false)
        }

        let budgeted = list.ids.prefix(maxDetailedKeys)
        var keys: [Key] = []
        for id in budgeted {
            guard let key = await readKey(address: address, id: id) else { continue }
            keys.append(key)
        }
        let now = Date.now
        let usable = keys.filter { $0.isUsable(now: now) }
        return Reading(address: address.lowercased(),
                       keys: sorted(usable),
                       truncated: list.truncated || list.ids.count > budgeted.count)
    }

    /// One key's four facts. nil when it is revoked, or when the calls that
    /// decide what it IS could not be read — a key we cannot describe is left
    /// out rather than shown with guessed properties, since "root key" and
    /// "session key" are the whole reading.
    @MainActor
    private static func readKey(address: String, id: String) async -> Key? {
        guard let activeData = encode(isKeyActiveSelector, address: address, keyID: id),
              let activeHex = await call(activeData),
              decodeBool(activeHex) == true
        else { return nil }

        guard let rootData = encode(isRootKeySelector, address: address, keyID: id),
              let rootHex = await call(rootData),
              let isRoot = decodeBool(rootHex)
        else { return nil }

        // Expiry and nonce are ENRICHMENT: a key whose expiry we cannot read
        // is still a key that can act, so a failure here degrades the row
        // rather than dropping it. `0` means "never expires" by the contract's
        // own convention (measured against the one registered key).
        var expiry: Date?
        if let data = encode(getExpirySelector, address: address, keyID: id),
           let hex = await call(data), let seconds = decodeUInt(hex), seconds > 0 {
            expiry = Date(timeIntervalSince1970: TimeInterval(seconds))
        }

        var hasEverSigned = false
        if let data = encode(getNonceSelector, address: address, keyID: id),
           let hex = await call(data), let nonce = decodeUInt(hex) {
            hasEverSigned = nonce > 0
        }

        return Key(id: id.lowercased(), isRoot: isRoot,
                   expiry: expiry, hasEverSigned: hasEverSigned)
    }

    /// One `eth_call` against the L1 keystore, through the same measured host
    /// pool every other wallet read in this app uses.
    @MainActor
    private static func call(_ data: String) async -> String? {
        await WalletApprovals.rpcRead(
            network: network, method: "eth_call",
            params: [["to": contract, "data": data], "latest"]) as? String
    }

    /// Reads several addresses, skipping anything that is not plain hex (an
    /// unresolved ENS name would be padded into a meaningless address).
    /// Addresses with nothing registered are dropped, so the caller receives
    /// only accounts with something to say.
    @MainActor
    static func read(addresses: [String]) async -> [Reading] {
        var out: [Reading] = []
        for address in addresses where ENS.isHexAddress(address) {
            guard let reading = await read(address: address), !reading.isEmpty else { continue }
            out.append(reading)
        }
        return out
    }

    // MARK: - The between-pass snapshot

    private static func snapshotKey(_ address: String) -> String {
        "altana.keys.\(address.lowercased())"
    }

    /// The key ids seen for this address on the previous pass, or nil if we
    /// have never read it. nil is what makes first sight silent — see
    /// `newlyAppeared`.
    static func storedKeyIDs(for address: String) -> [String]? {
        UserDefaults.standard.stringArray(forKey: snapshotKey(address))
    }

    static func storeKeyIDs(_ ids: [String], for address: String) {
        UserDefaults.standard.set(ids.map { $0.lowercased() }, forKey: snapshotKey(address))
    }

    /// Unwatching takes the snapshot with it, so re-watching starts honest at
    /// first sight instead of reporting every key registered in the gap as
    /// news — the rule `WalletApprovals.clearCursors` already follows for its
    /// own cursors, and called from the same place.
    static func clearSnapshot(address: String) {
        UserDefaults.standard.removeObject(forKey: snapshotKey(address))
    }

    /// Key ids that appeared for this address since the last pass, advancing
    /// the snapshot as it goes.
    ///
    /// The snapshot is written from what we DECODED, not from what we
    /// described — a key dropped by `readKey` because its details would not
    /// read is still a key we have now seen, and recording it any other way
    /// would re-announce it as new on every pass until the RPC recovered.
    @MainActor
    static func newKeyIDs(address: String) async -> [String] {
        guard let data = encode(getKeysSelector, address: address),
              let hex = await call(data),
              let list = decodeKeyIDs(hex)
        else { return [] }
        let current = list.ids.map { $0.lowercased() }
        let fresh = newlyAppeared(previous: storedKeyIDs(for: address), current: current)
        storeKeyIDs(current, for: address)
        return fresh
    }

    // MARK: - Probe

    /// `-altanaProbe YES` — one line per watched wallet, then one per key.
    ///
    /// It exists because an empty reading has FOUR causes that render as the
    /// same silence — no EVM wallet watched, the RPC did not answer, the
    /// wallet genuinely has no keys (which today is the correct answer for
    /// every wallet on Earth but one), or the decode refused a reply it did
    /// not recognise — and only the last two are worth acting on. The
    /// `keys=` / `unreadable` split is what separates them in one launch.
    @MainActor
    static func probeLines() async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return ["no EVM wallets watched"] }

        var lines: [String] = ["contract=\(contract) network=\(network)"]
        for address in addresses {
            let short = WalletStore.shortAddress(address)
            guard let reading = await read(address: address) else {
                lines.append("\(short) unreadable — the keystore did not answer")
                continue
            }
            lines.append("\(short) keys=\(reading.keys.count)"
                + " root=\(reading.rootCount) session=\(reading.sessionCount)"
                + " truncated=\(reading.truncated ? "YES" : "NO")")
            for key in reading.keys {
                let expiry = key.expiry.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
                lines.append("  altanaKey| \(key.id)"
                    + " role=\(key.isRoot ? "root" : "session")"
                    + " expires=\(expiry)"
                    + " everSigned=\(key.hasEverSigned ? "YES" : "NO")")
            }
        }
        return lines
    }
}
