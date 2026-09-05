import Foundation
import Security

/// THE POOL, THE NOTE BOOK, AND THE SHIELDED BALANCE (prd §593e, 2026-09-05).
///
/// The pure arithmetic lives in `PrivacyDevnetPoseidon`/`PrivacyDevnetNote`
/// (Foundation-only, harness-verified against a real on-chain shield). This
/// file is the app-integrated half: WHERE the pool is, WHERE a note's secrets
/// are kept, and HOW the shielded balance is read back off the chain. It uses
/// the Keychain and the RPC, so it is not in the pure harness — the numbers it
/// produces were checked in `privacy-poseidon-selftest.sh` before this glue
/// ever touched them.
enum PrivacyDevnetPool {
    /// **THE POOL THIS APP SHIELDS INTO — a devnet contract that may reset.**
    ///
    /// This is a `lambdaclass/minimal-shielded-pool` deployment on chain 8141,
    /// the same address the room already references as "an address that used
    /// the pool". A devnet has no canonical pool and its own footer says it may
    /// be wiped without notice, so this is a one-line constant on purpose: if
    /// the chain resets and the pool moves, this is the single thing to update,
    /// and a stale value fails LOUDLY (a shield the node refuses, an empty
    /// View) rather than silently sending somewhere wrong.
    static let address = "0x062901d23f7e2d3bf9949c8a8cfd2c7a5ae3f980"

    /// `LeafAppended(bytes32 cm, uint64 epoch, uint32 index, bytes32 newRoot)`.
    static let leafAppendedTopic = "0x1c9386c619e61f45f16a19541b370266f8eb6fd22d241ff010e03cc31ea82368"
    /// `NoteSpent(bytes32 nf)`.
    static let noteSpentTopic = "0xd13faa8100906cf559aebacf9c16532cfc9708645c198c8f15798ee049dbcfc1"
    /// `domain()` selector — the nullifier domain, needed to tell a spent note
    /// from an unspent one.
    static let domainSelector = "0xc2fb26a6"
}

/// A note this device shielded, as stored: the secret `rho`, the amount, and
/// the commitment the chain will have as a leaf. `spendKey` is held once for
/// the whole book, not per note.
struct PrivacyDevnetStoredNote: Codable, Equatable {
    var rhoHex: String
    var valueWeiHex: String
    var commitmentHex: String
    var createdAt: Date
}

/// The device-only note book: one shielded spend key plus the notes made with
/// it. Kept in the Keychain as a single item, device-only and
/// non-synchronizable — the same protection class as the signing key, for the
/// same reason (`scripts/keychain-audit.py`): worthless money is still not a
/// reason to let a spend-enabling secret ride a backup onto another device.
///
/// **Losing this device loses the notes**, which is inherent to a minimal pool
/// with no on-chain note delivery, and acceptable on a devnet whose money has
/// no value (§525's ruling). Do not carry this shape to a chain where value is
/// real.
enum PrivacyDevnetNoteBook {
    private static let service = "casberi-privacydevnet-notes"
    private static let account = "shielded-note-book"

    private struct Book: Codable {
        var spendKeyHex: String
        var notes: [PrivacyDevnetStoredNote]
    }

    private static func load() -> Book? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let book = try? JSONDecoder().decode(Book.self, from: data)
        else { return nil }
        return book
    }

    private static func save(_ book: Book) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            // Device-only, non-synchronizable — named for keychain-audit.py.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        if SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = base
            for (k, v) in attrs { add[k] = v }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// The book's spend key, created on first use. A random field scalar
    /// (32 bytes reduced mod the BN254 scalar field), the same secret every
    /// note under this book shares as its owner.
    static func spendKey() -> PrivacyDevnetPoseidon.Fp {
        if let book = load(), let sk = book.spendKeyHex.hexToBytes() {
            return PrivacyDevnetNote.fp(bytesBE: sk)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let sk = PrivacyDevnetNote.fp(bytesBE: bytes)
        // Persist the CANONICAL field bytes, so the reduction is done once and
        // the same key comes back every time.
        save(Book(spendKeyHex: sk.bytesBE().toHex(), notes: load()?.notes ?? []))
        return sk
    }

    static func notes() -> [PrivacyDevnetStoredNote] { load()?.notes ?? [] }

    /// Record a note that was just shielded. `spendKey()` must already have run
    /// (the shield used it), so the book exists.
    static func record(_ note: PrivacyDevnetStoredNote) {
        guard var book = load() else { return }
        guard !book.notes.contains(where: { $0.commitmentHex == note.commitmentHex }) else { return }
        book.notes.append(note)
        save(book)
    }

    /// Forget everything — paired with the account key's own deletion.
    static func forget() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The shielded balance — "View", the read that turns stored notes into a
/// number by asking the chain which are confirmed and which are spent.
enum PrivacyDevnetShielded {

    struct Balance: Equatable {
        /// Sum of confirmed, unspent notes, in wei. Nil when the chain could
        /// not be reached — a failed read and a real zero must never look
        /// alike (§83).
        var unspentWei: Decimal?
        var confirmedCount: Int
        var spentCount: Int
    }

    /// Read the shielded balance for this device's note book.
    ///
    /// A note counts only when BOTH hold: its commitment is a real leaf the
    /// pool emitted (so a shield the node ultimately rejected is never counted)
    /// AND its nullifier has not appeared in a `NoteSpent` log. The nullifier
    /// needs the pool's `domain()`, read once here.
    static func balance() async -> Balance {
        let stored = PrivacyDevnetNoteBook.notes()
        guard !stored.isEmpty else { return Balance(unspentWei: 0, confirmedCount: 0, spentCount: 0) }

        // Leaves the pool has actually appended (commitment is topic[1]).
        guard let leafLogs = await logs(topic: PrivacyDevnetPool.leafAppendedTopic) else {
            return Balance(unspentWei: nil, confirmedCount: 0, spentCount: 0)
        }
        let onChainLeaves = Set(leafLogs.compactMap { ($0["topics"] as? [Any])?.dropFirst().first as? String }
            .map { $0.lowercased() })

        // Nullifiers the pool has spent (nf is topic[1]).
        let spentLogs = await logs(topic: PrivacyDevnetPool.noteSpentTopic) ?? []
        let spentNullifiers = Set(spentLogs.compactMap { ($0["topics"] as? [Any])?.dropFirst().first as? String }
            .map { $0.lowercased() })

        // The domain, for computing our notes' nullifiers.
        guard let domain = await readDomain() else {
            return Balance(unspentWei: nil, confirmedCount: 0, spentCount: 0)
        }
        let sk = PrivacyDevnetNoteBook.spendKey()

        var unspent = Decimal(0)
        var confirmed = 0, spent = 0
        for note in stored {
            let cmHex = "0x" + note.commitmentHex.stripHex().leftPadded(to: 64)
            guard onChainLeaves.contains(cmHex.lowercased()) else { continue } // not confirmed
            confirmed += 1
            guard let cm = note.commitmentHex.hexToBytes() else { continue }
            let nf = PrivacyDevnetPoseidon.nullifier(
                domain: domain, spendKey: sk, commitment: PrivacyDevnetNote.fp(bytesBE: cm))
            let nfHex = "0x" + nf.bytesBE().toHex()
            if spentNullifiers.contains(nfHex.lowercased()) {
                spent += 1
            } else if let wei = decimalWei(note.valueWeiHex) {
                unspent += wei
            }
        }
        return Balance(unspentWei: unspent, confirmedCount: confirmed, spentCount: spent)
    }

    // MARK: reads

    private static func logs(topic: String) async -> [[String: Any]]? {
        let params: [Any] = [[
            "address": PrivacyDevnetPool.address,
            "fromBlock": "0x0", "toBlock": "latest",
            "topics": [topic],
        ]]
        return await PrivacyDevnetRPC.call(method: "eth_getLogs", params: params) as? [[String: Any]]
    }

    private static func readDomain() async -> PrivacyDevnetPoseidon.Fp? {
        let params: [Any] = [["to": PrivacyDevnetPool.address, "data": PrivacyDevnetPool.domainSelector], "latest"]
        guard let s = await PrivacyDevnetRPC.call(method: "eth_call", params: params) as? String,
              let bytes = s.hexToBytes(), bytes.count == 32 else { return nil }
        return PrivacyDevnetNote.fp(bytesBE: bytes)
    }

    private static func decimalWei(_ hex: String) -> Decimal? {
        let d = hex.stripHex()
        guard !d.isEmpty else { return Decimal(0) }
        var total = Decimal(0)
        for ch in d { guard let v = ch.hexDigitValue else { return nil }; total = total * 16 + Decimal(v) }
        return total
    }
}

private extension String {
    func stripHex() -> String { hasPrefix("0x") ? String(dropFirst(2)) : self }
    func leftPadded(to n: Int) -> String {
        count >= n ? self : String(repeating: "0", count: n - count) + self
    }
    func hexToBytes() -> [UInt8]? {
        var t = stripHex()
        if t.count % 2 == 1 { t = "0" + t }
        var out = [UInt8](); var i = t.startIndex
        while i < t.endIndex {
            let j = index(i, offsetBy: 2)
            guard let b = UInt8(t[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
}

private extension Array where Element == UInt8 {
    func toHex() -> String { map { String(format: "%02x", $0) }.joined() }
}
