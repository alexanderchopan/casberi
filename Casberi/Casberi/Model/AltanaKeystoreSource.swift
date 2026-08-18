import Foundation
import SwiftData

/// The chain half of `AltanaKeystore` (2026-08-18, prd §402/§403) — the reads
/// across both registries, the rows, the snapshot, and the probes.
///
/// Split from the model for the reason every `*Source.swift` here is: the pure
/// file is Foundation-only so the harness compiles it AS SHIPPED, and anything
/// needing `IngestSupport`, `WalletStore` or SwiftData lives here.
///
/// Every call is `eth_call`. Nothing is signed, nothing is sent, and no write
/// selector is ever constructed — `AltanaKeystore.writeSelectors` exists to be
/// checked against, and the self-test fails the build on one appearing here.
extension AltanaKeystore {

    // MARK: - Transport

    /// One `eth_call` against one registry, trying its hosts in order.
    ///
    /// Rides `IngestSupport.postJSON` rather than a private `URLSession` so it
    /// lands in the receipts ledger (§277) — and NAMES its service, because
    /// these are shared public RPCs that no by-host rule can attribute to this
    /// seat alone (§289).
    static func call(_ data: String, on registry: Registry) async -> String? {
        for host in registry.hosts {
            let body: [String: Any] = [
                "jsonrpc": "2.0", "id": 1, "method": "eth_call",
                "params": [["to": registry.contract, "data": data], "latest"],
            ]
            guard let any = await IngestSupport.postJSON(host, body: body, service: "Altana"),
                  let dict = any as? [String: Any] else { continue }
            // A JSON-RPC error is an ANSWER, not a transport failure — asking
            // the next node the same bad question would just cost a round trip.
            if dict["error"] != nil { return nil }
            if let result = dict["result"] as? String { return result }
        }
        return nil
    }

    // MARK: - Reading

    /// Everything registered for one address, across every registry.
    ///
    /// nil only when NO registry answered. If one chain answers and the other
    /// is unreachable, that is a real (if partial) reading and is returned — a
    /// hiccup on one public RPC must not blank a room whose other half read
    /// perfectly well.
    @MainActor
    static func read(address: String) async -> Reading? {
        var keys: [Key] = []
        var truncated = false
        var answered = false

        for registry in registries {
            guard let data = encode(getKeysSelector, address: address),
                  let hex = await call(data, on: registry),
                  let list = decodeKeyIDs(hex) else { continue }
            answered = true
            guard !list.ids.isEmpty else { continue }

            let budgeted = list.ids.prefix(maxDetailedKeys)
            for id in budgeted {
                guard let key = await readKey(address: address, id: id, on: registry) else { continue }
                keys.append(key)
            }
            if list.truncated || list.ids.count > budgeted.count { truncated = true }
        }
        guard answered else { return nil }

        // A key id derives from its public key, so the SAME credential
        // registered on both chains carries the same id. Filed once, keeping
        // the first registry that answered — BNB, where the keys are.
        var seen = Set<String>()
        let deduped = keys.filter { seen.insert($0.id).inserted }
        return Reading(address: address.lowercased(), keys: sorted(deduped), truncated: truncated)
    }

    /// One key's record. nil when it is revoked, or when the two calls that
    /// decide what it IS could not be read — a key we cannot describe is left
    /// out rather than shown with guessed properties.
    ///
    /// **An EXPIRED key is kept**, unlike this file's first cut, which dropped
    /// it at the reading. Expired-but-still-listed is the hygiene finding
    /// (§403) and it is real: two of six session keys sampled on BNB are in
    /// exactly that state right now. `Key.isUsable(now:)` separates them
    /// downstream; dropping them here would delete the finding.
    @MainActor
    private static func readKey(address: String, id: String, on registry: Registry) async -> Key? {
        guard let activeData = encode(isKeyActiveSelector, address: address, keyID: id),
              let activeHex = await call(activeData, on: registry),
              decodeBool(activeHex) == true
        else { return nil }

        guard let rootData = encode(isRootKeySelector, address: address, keyID: id),
              let rootHex = await call(rootData, on: registry),
              let isRoot = decodeBool(rootHex)
        else { return nil }

        // The AUTHORITATIVE expiry — and also the witness that proves the
        // `getKey` struct layout below. 0 means never.
        var expirySeconds = 0
        if let data = encode(getExpirySelector, address: address, keyID: id),
           let hex = await call(data, on: registry), let seconds = decodeUInt(hex) {
            expirySeconds = seconds
        }
        let expiry = expirySeconds > 0
            ? Date(timeIntervalSince1970: TimeInterval(expirySeconds)) : nil

        var registered: Date?
        if let data = encode(getKeySelector, address: address, keyID: id),
           let hex = await call(data, on: registry) {
            registered = registeredAt(fromGetKey: hex, expectedExpiry: expirySeconds)
        }

        var hasEverSigned = false
        if let data = encode(getNonceSelector, address: address, keyID: id),
           let hex = await call(data, on: registry), let nonce = decodeUInt(hex) {
            hasEverSigned = nonce > 0
        }

        return Key(id: id.lowercased(), isRoot: isRoot, expiry: expiry,
                   hasEverSigned: hasEverSigned, registeredAt: registered,
                   chainLabel: registry.label)
    }

    /// Reads several addresses, skipping anything that is not plain hex.
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

    static func storedKeyIDs(for address: String) -> [String]? {
        UserDefaults.standard.stringArray(forKey: snapshotKey(address))
    }

    static func storeKeyIDs(_ ids: [String], for address: String) {
        UserDefaults.standard.set(ids.map { $0.lowercased() }, forKey: snapshotKey(address))
    }

    /// Unwatching takes the snapshot with it, beside `WalletApprovals.clearCursors`.
    static func clearSnapshot(address: String) {
        UserDefaults.standard.removeObject(forKey: snapshotKey(address))
    }

    // MARK: - The seat's gate

    /// Which watched wallets have actually been seen holding a key.
    ///
    /// The Gnosis Pay rule (§222), not Peer's: most wallets hold no keystore
    /// entry, and a seat lighting up for every watched wallet would claim a
    /// registry entry that isn't there (§83).
    ///
    /// A `WalletSeatEvidence` mark rather than a plain Bool, and the
    /// difference matters: that type STAMPS AND NEVER UNSTAMPS, so a public
    /// RPC having a bad minute cannot make a seat someone really uses blink
    /// out of the catalog and back in.
    static let evidence = WalletSeatEvidence("altana.evidence")

    // MARK: - Landing

    static let source = "Altana"

    /// A stable ref per credential, CHAIN-SCOPED: the same key id on two
    /// registries is two registrations, and merging them would hide one.
    static func ref(chain: String, address: String, keyID: String) -> String {
        let slug = chain.lowercased().replacingOccurrences(of: " ", with: "-")
        return "altana:key:\(slug):\(address.lowercased()):\(keyID.lowercased())"
    }

    /// Reads every watched wallet and lands what it finds.
    ///
    /// **First sight BACKFILLS, which amends §402's silent-first-sight rule**
    /// — deliberately, and only because the amendment is earned. That rule
    /// existed because we could not date a key: a backfilled row would have
    /// worn today's date and read as "this just happened", the Hyperliquid
    /// bug. `getKey` word 5 now gives the real registration date, *witnessed*
    /// (see the pure file), so a backfilled row sorts to when it actually
    /// happened and cannot fake urgency. Exactly the `PrivacyPoolsBridge`
    /// divergence (§162), taken for the same reason.
    ///
    /// The MOMENT rule still holds: only a key that appears while we are
    /// watching is news, and only that one is flagged.
    @MainActor
    @discardableResult
    static func sync(context: ModelContext) async -> Int {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return 0 }

        var landed = 0
        var snapshot: [Reading] = []

        for address in addresses {
            guard let reading = await read(address: address) else { continue }
            if !reading.keys.isEmpty { evidence.remember(address) }
            snapshot.append(reading)

            let current = reading.keys.map { $0.id.lowercased() }
            let previous = storedKeyIDs(for: address)
            let firstSight = previous == nil
            let fresh = Set(newlyAppeared(previous: previous, current: current))
            storeKeyIDs(current, for: address)

            let existing = IngestSupport.existingSourceRefs(context, source: source)
            for key in reading.keys {
                let chain = key.chainLabel ?? "Ethereum"
                let r = ref(chain: chain, address: address, keyID: key.id)
                guard !existing.contains(r) else { continue }
                let isNews = !firstSight && fresh.contains(key.id)
                // A backfilled row is dated to its registration. A row whose
                // date could not be witnessed falls back to now — but that can
                // only happen on first sight, where it cannot read as news.
                let thing = Thing(kind: .link,
                                  title: title(for: key, address: address, isNews: isNews),
                                  content: explorerURL(address: address),
                                  source: source, sourceRef: r)
                thing.capturedAt = key.registeredAt ?? Date.now
                thing.walletAddress = address
                thing.externalLink = explorerURL(address: address)
                // A session key's expiry is a real deadline, so it reconciles
                // through the generic `deadlineNear` path with no notification
                // code of this seat's own (the ENSExpiry shape).
                thing.dueAt = key.isRoot ? nil : key.expiry
                // NEWS is carried by the TITLE, not by a flag: `isFlagged` is
                // computed from `securityFlags`, which is the credential-scan
                // tripwire's field (§277) and not ours to write. A newly
                // arrived root key says so in its own sentence, which is where
                // somebody reads it anyway.
                thing.tags = [key.isRoot ? "Root key" : "Session key", chain]
                context.insert(thing)
                SpotlightIndex.index([thing])
                landed += 1
            }
        }
        // The head composes from THIS, never from a live read — a card must
        // not spend an `eth_call` every time the room re-draws.
        AltanaState.save(snapshot)
        if landed > 0 { context.saveHonestly() }
        return landed
    }

    /// The row's sentence.
    ///
    /// A NEW root key wears the 7702 unknown-delegate phrasing — a credential
    /// added to your account that you did not add is the thing worth being
    /// alarmed by, and the copy says what to do about it rather than merely
    /// reporting. A backfilled one states the standing fact instead, because
    /// alarming about a key that has been there for weeks is the fake urgency
    /// the date exists to prevent.
    static func title(for key: Key, address: String, isNews: Bool) -> String {
        let short = WalletStore.shortAddress(address)
        if key.isRoot {
            return isNews
                ? String(localized: "A new key can now sign as \(short) — if that wasn't you, revoke it on Altana")
                : String(localized: "A root key can sign as \(short)")
        }
        guard let expiry = key.expiry else {
            return String(localized: "A session key was granted for \(short), with no expiry")
        }
        let when = expiry.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "A session key was granted for \(short), until \(when)")
    }

    /// The door. Altana's own explorer is where a key can actually be acted on
    /// — §112's preparing-surface rule, the Revoke.cash shape: we read and
    /// state, they act.
    static func explorerURL(address: String) -> String {
        "https://explorer.altana.network/account/\(address.lowercased())"
    }

    // MARK: - Probes

    /// `-altanaProbe YES` — one line per registry, then per wallet, then per key.
    ///
    /// An empty reading has FIVE causes that render as one silence: no EVM
    /// wallet watched, neither RPC answered, the wallet genuinely has nothing
    /// registered, the decoder refused a reply it did not recognise, or — the
    /// one that actually shipped — we asked the wrong chain. The per-registry
    /// lines are what separate that last one from the rest, which is why they
    /// are printed even when every wallet reads empty.
    @MainActor
    static func probeLines() async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        var lines: [String] = registries.map {
            "registry| \($0.label) \($0.contract) hosts=\($0.hosts.count)"
        }
        guard !addresses.isEmpty else { return lines + ["no EVM wallets watched"] }

        for address in addresses {
            let short = WalletStore.shortAddress(address)
            guard let reading = await read(address: address) else {
                lines.append("\(short) unreadable — no registry answered")
                continue
            }
            let now = Date.now
            let stale = reading.keys.filter { $0.isExpiredButListed(now: now) }.count
            lines.append("\(short) keys=\(reading.keys.count)"
                + " root=\(reading.rootCount) session=\(reading.sessionCount)"
                + " expiredButListed=\(stale)"
                + " truncated=\(reading.truncated ? "YES" : "NO")")
            for key in reading.keys {
                let exp = key.expiry.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
                let reg = key.registeredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "UNWITNESSED"
                let grant = key.grantDuration.map { "\(Int($0 / 3600))h" } ?? "—"
                lines.append("  altanaKey| \(key.id.prefix(18))…"
                    + " chain=\(key.chainLabel ?? "?")"
                    + " role=\(key.isRoot ? "root" : "session")"
                    + " registered=\(reg) expires=\(exp) grant=\(grant)"
                    + " everSigned=\(key.hasEverSigned ? "YES" : "NO")")
            }
        }
        return lines
    }
}
