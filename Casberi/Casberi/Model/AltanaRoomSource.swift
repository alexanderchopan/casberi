import Foundation

/// The stored half of `AltanaRoom` (2026-08-18, prd §403).
///
/// The head must cost NOTHING per open — a card that fired five `eth_call`s
/// every time the room re-drew would spend a person's battery on a scroll.
/// So the sweep writes what it read, and the card composes from that. It is
/// the `ASCState`/`X402State` shape: a small Codable snapshot in UserDefaults,
/// never a new `Thing` field, so there is **no CloudKit Production deploy**.
///
/// The snapshot is a CACHE OF A PUBLIC FACT, not a record of anything private:
/// key ids, roles and two dates, all readable by anyone with the address.
enum AltanaState {

    private static let key = "altana.readings"

    /// One key, flattened for storage. Deliberately a separate type from
    /// `AltanaKeystore.Key`: that one is the harness-compiled model and must
    /// stay free of `Codable` conformance decisions made for a cache.
    struct StoredKey: Codable, Equatable {
        var id: String
        var isRoot: Bool
        var expiry: Date?
        /// The COUNT (§404). Optional so a snapshot written by an older build
        /// still decodes — Swift's synthesized decoder does not apply defaults
        /// for a missing key, and a non-optional addition here would throw and
        /// silently blank the head for everyone who upgraded (the trap
        /// `WalletStore.WatchedAddress.updatedAt` documents).
        var signatureCount: Int?
        var publicKey: String?
        var registeredAt: Date?
        var chainLabel: String?
    }

    struct StoredReading: Codable, Equatable {
        var address: String
        var keys: [StoredKey]
        var truncated: Bool
    }

    static func save(_ readings: [AltanaKeystore.Reading]) {
        let stored = readings.map { r in
            StoredReading(address: r.address,
                          keys: r.keys.map {
                              StoredKey(id: $0.id, isRoot: $0.isRoot, expiry: $0.expiry,
                                        signatureCount: $0.signatureCount,
                                        publicKey: $0.publicKey,
                                        registeredAt: $0.registeredAt,
                                        chainLabel: $0.chainLabel)
                          },
                          truncated: r.truncated)
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var readings: [AltanaKeystore.Reading] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredReading].self, from: data)
        else { return [] }
        return stored.map { r in
            AltanaKeystore.Reading(
                address: r.address,
                keys: r.keys.map {
                    AltanaKeystore.Key(id: $0.id, isRoot: $0.isRoot, expiry: $0.expiry,
                                       signatureCount: $0.signatureCount ?? 0,
                                       publicKey: $0.publicKey,
                                       registeredAt: $0.registeredAt,
                                       chainLabel: $0.chainLabel)
                },
                truncated: r.truncated)
        }
    }

    /// Revoked credentials the card remembers (§410).
    ///
    /// Kept HERE rather than as `Thing` rows because a ghost is a property of
    /// the current reading, not an event in the feed — the event already
    /// landed as a row when §404 detected the revocation. This is what lets
    /// the key list still carry it.
    private static let goneKey = "altana.gone"

    struct StoredGhost: Codable, Equatable {
        var address: String
        var keyID: String
        var isRoot: Bool
        var kindLabel: String?
        var chainLabel: String?
        var noticedAt: Date
    }

    /// How long a ghost is remembered, and how many. A revocation from months
    /// ago is not the current reading any more — it is history, and the row that
    /// landed at the time is where history belongs.
    static let ghostLifetime: TimeInterval = 30 * 86_400
    static let ghostCap = 4

    static var ghosts: [AltanaRoom.Ghost] {
        guard let data = UserDefaults.standard.data(forKey: goneKey),
              let stored = try? JSONDecoder().decode([StoredGhost].self, from: data)
        else { return [] }
        let cutoff = Date.now.addingTimeInterval(-ghostLifetime)
        return stored
            .filter { $0.noticedAt > cutoff }
            .sorted { $0.noticedAt > $1.noticedAt }
            .prefix(ghostCap)
            .map { AltanaRoom.Ghost(address: $0.address, keyID: $0.keyID, isRoot: $0.isRoot,
                                    kindLabel: $0.kindLabel, chainLabel: $0.chainLabel,
                                    noticedAt: $0.noticedAt) }
    }

    /// Records one, newest first, never twice.
    static func rememberGone(_ ghost: StoredGhost) {
        var all = (try? JSONDecoder().decode(
            [StoredGhost].self,
            from: UserDefaults.standard.data(forKey: goneKey) ?? Data())) ?? []
        guard !all.contains(where: {
            $0.keyID.lowercased() == ghost.keyID.lowercased()
                && $0.address.lowercased() == ghost.address.lowercased()
        }) else { return }
        all.insert(ghost, at: 0)
        all = Array(all.prefix(ghostCap * 4))
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: goneKey)
        }
    }

    static func forgetGhosts(address: String) {
        guard let data = UserDefaults.standard.data(forKey: goneKey),
              var all = try? JSONDecoder().decode([StoredGhost].self, from: data) else { return }
        all.removeAll { $0.address.lowercased() == address.lowercased() }
        if let out = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(out, forKey: goneKey)
        }
    }

    /// Disconnecting forgets the cache, so a re-watch composes from a fresh
    /// read rather than a card describing wallets nobody is watching.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: goneKey)
    }
}

extension AltanaRoom {

    /// The head, composed from the stored snapshot. No network, no fetch.
    ///
    /// nil has five causes and they render identically, which is why
    /// `-altanaRoomProbe` prints the snapshot before the card: nothing
    /// watched, no wallet holds keys, the snapshot failed to decode, the
    /// total is under `minimumKeys`, or the face rail is scoped to a wallet
    /// the keystore has never seen.
    ///
    /// **The scope is RESOLVED here rather than inside `compose` (prd §488).**
    /// `chrome.walletScope` holds the WATCHED spelling, which may be an ENS
    /// name, while a reading is stamped with the resolved hex — so a raw
    /// compare inside the pure model would silently empty the card for exactly
    /// the wallets people bother to name (`WalletStore.scopeMatches`'s own
    /// 2026-07-20 lesson, and the same reason `AddressFlight` keys on the
    /// book's form rather than the raw address). The store lives out here, so
    /// the resolution does too, and `compose` gets plain hex.
    static func card(now: Date = .now, scope: String? = nil) -> Card? {
        let readings = AltanaState.readings
        let resolved = scope.flatMap { s in
            readings.first { WalletStore.shared.scopeMatches($0.address, scope: s) }?.address
        }
        // A scope that resolves to nothing is a wallet this keystore has never
        // seen — passed through as the UNRESOLVED string so `compose` declines,
        // rather than dropped, which would draw the aggregate under a ringed
        // face that has nothing to do with it.
        return compose(readings: readings, ghosts: AltanaState.ghosts, now: now,
                       scope: resolved ?? scope)
    }

    /// `-altanaRoomProbe YES` — the stored readings, then the composed card.
    /// One NSLog per line (the `-todayProbe` truncation lesson).
    @MainActor
    static func probeLines(now: Date = .now) -> [String] {
        let readings = AltanaState.readings
        var lines = ["stored readings: \(readings.count)"]
        for r in readings {
            lines.append("altanaStored| \(WalletStore.shortAddress(r.address))"
                + " keys=\(r.keys.count) truncated=\(r.truncated ? "YES" : "NO")")
        }
        guard let card = compose(readings: readings, ghosts: AltanaState.ghosts, now: now) else {
            return lines + ["altanaRoom| no card — nothing watched, no keys, or under the floor"]
        }
        lines.append("altanaRoom| \(card.headline)")
        if let stale = card.staleNote { lines.append("altanaRoom| stale: \(stale)") }
        if let shared = card.sharedNote { lines.append("altanaRoom| shared: \(shared)") }
        lines.append("altanaRoom| accounts: \(card.accounts.count)")
        lines.append("altanaRoom| chains: \(card.chains.joined(separator: ", "))")
        if let hours = card.urgentHours { lines.append("altanaRoom| urgent: \(hours)h to the soonest expiry") }
        if let more = card.moreLine { lines.append("altanaRoom| capped: \(more)") }
        // Every CREDENTIAL once, deduped, IN DRAWN ORDER — the order is the
        // thing most worth seeing here, since it is what §405 found wrong.
        // `bar=` is the shelf fraction the row draws against the fixed 90-day
        // window (§488) and `—` is a row with no clock at all: a root, an
        // expired key or a ghost. It is printed beside `daysLeft` on purpose —
        // a bar that disagrees with the countdown beside it is the one failure
        // here that renders as a perfectly ordinary row.
        for s in card.credentials {
            let pct = s.progress.map { "\(Int($0 * 100))%" } ?? "—"
            let bar = s.shelfFraction(now: now).map { "\(Int($0 * 100))%" } ?? "—"
            lines.append("  altanaKey| \(s.id.prefix(18))…"
                + " role=\(s.isRoot ? "root" : "session")"
                + " kind=\(s.kindLabel ?? "—")"
                + " grant=\(s.grantPhrase ?? "—")"
                + " signed=\(s.signatureCount)"
                + " signsFor=\(s.accountAddresses.count)"
                + " progress=\(pct)"
                + " bar=\(bar)"
                + " countdown=\(s.countdown(now: now))"
                + " daysLeft=\(s.daysLeft.map(String.init) ?? "—")"
                + " expired=\(s.expired ? "YES" : "NO")"
                + " chain=\(s.chainLabel ?? "?")")
        }
        return lines
    }
}
