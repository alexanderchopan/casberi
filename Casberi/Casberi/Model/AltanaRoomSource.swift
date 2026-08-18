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
        var hasEverSigned: Bool
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
                                        hasEverSigned: $0.hasEverSigned,
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
                                       hasEverSigned: $0.hasEverSigned,
                                       registeredAt: $0.registeredAt,
                                       chainLabel: $0.chainLabel)
                },
                truncated: r.truncated)
        }
    }

    /// Disconnecting forgets the cache, so a re-watch composes from a fresh
    /// read rather than a card describing wallets nobody is watching.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension AltanaRoom {

    /// The head, composed from the stored snapshot. No network, no fetch.
    ///
    /// nil has four causes and they render identically, which is why
    /// `-altanaRoomProbe` prints the snapshot before the card: nothing
    /// watched, no wallet holds keys, the snapshot failed to decode, or the
    /// leading wallet is under `minimumKeys`.
    static func card(now: Date = .now) -> Card? {
        compose(readings: AltanaState.readings, now: now)
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
        guard let card = compose(readings: readings, now: now) else {
            return lines + ["altanaRoom| no card — nothing watched, no keys, or under the floor"]
        }
        lines.append("altanaRoom| \(card.headline)")
        if let root = card.rootLine { lines.append("altanaRoom| root: \(root)") }
        if let stale = card.staleNote { lines.append("altanaRoom| stale: \(stale)") }
        if let other = card.otherWalletsNote { lines.append("altanaRoom| other: \(other)") }
        lines.append("altanaRoom| chains: \(card.chains.joined(separator: ", "))")
        for s in card.sessions {
            let pct = s.progress.map { "\(Int($0 * 100))%" } ?? "—"
            lines.append("  altanaSession| \(s.id.prefix(18))…"
                + " grant=\(s.grantPhrase ?? "—")"
                + " progress=\(pct)"
                + " daysLeft=\(s.daysLeft.map(String.init) ?? "—")"
                + " expired=\(s.expired ? "YES" : "NO")"
                + " chain=\(s.chainLabel ?? "?")")
        }
        return lines
    }
}
