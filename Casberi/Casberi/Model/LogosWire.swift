import Foundation
import CryptoKit

/// The Logos network's wire, pure (prd §988, 2026-09-29). Foundation only, no
/// app types, so `scripts/logos-selftest.sh` compiles this file WHOLE and
/// unmodified — the only proof the shapings are right, because nothing on
/// this host can send on LEZ and every failure here renders as a clean,
/// empty, wrong room.
///
/// **LEZ, not the L1.** Logos runs two chains: the L1 ("Bedrock", UTXO-style
/// notes, ZK-proved spends) and LEZ, the Logos Execution Zone — the
/// account-based zone Basecamp's wallet uses. Measured 2026-09-29: LEZ's
/// sequencer answers keyless JSON-RPC at `testnet.lez.logos.co` (POST only;
/// a GET is `405 POST is required`), while every L1 node route on the public
/// testnet is `401 Basic realm="Restricted API"` and its explorer has no
/// address index. So "watch an account" means an LEZ account.
enum LogosWire {

    // MARK: - Account ids

    /// An LEZ account id is 32 bytes, written in base58 — optionally behind a
    /// `Public/` or `Private/` visibility prefix, which is how Basecamp's
    /// wallet prints it. The id itself is `SHA256("/LEE/v0.3/AccountId/Public/"
    /// ‖ x-only pubkey)`, so no checksum exists to catch a typo: the length is
    /// the only structural test there is, and the node's own `invalid length:
    /// expected 32 bytes` is that same test.
    ///
    /// **A `Private/` id is refused, not watched.** Its balance and activity
    /// are encrypted to its owner; the sequencer answers a private id with an
    /// empty public account (balance 0, nonce 0), which a watch would draw as
    /// "this account is empty" — a confident wrong answer. Reading a private
    /// account is the Field Wallet door, with the owner's consent.
    enum Visibility: String, Equatable { case publicAccount = "Public", privateAccount = "Private" }

    struct AccountID: Equatable, Hashable {
        let base58: String
        let visibility: Visibility?
    }

    static func parseAccountID(_ raw: String) -> AccountID? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibility: Visibility?
        for v in [Visibility.publicAccount, .privateAccount] {
            let prefix = v.rawValue + "/"
            if text.lowercased().hasPrefix(prefix.lowercased()) {
                visibility = v
                text = String(text.dropFirst(prefix.count))
            }
        }
        guard let bytes = base58Decode(text), bytes.count == 32 else { return nil }
        // Re-encode so two spellings of one id (leading-zero padding is the
        // only freedom base58 has) are one watch.
        return AccountID(base58: base58Encode(bytes), visibility: visibility)
    }

    /// The id a WATCH can take: public (or unprefixed, which is public on the
    /// wire). nil for anything else, and for a private id — see `Visibility`.
    static func watchableID(_ raw: String) -> String? {
        guard let id = parseAccountID(raw), id.visibility != .privateAccount else { return nil }
        return id.base58
    }

    /// `EfQh…PLw7` — the short form every row and roster line uses.
    static func short(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }

    // MARK: - Base58 (Bitcoin alphabet)

    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let index: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() { map[c] = i }
        return map
    }()

    static func base58Decode(_ s: String) -> [UInt8]? {
        guard !s.isEmpty else { return nil }
        var bytes: [UInt8] = []
        for c in s {
            guard var carry = index[c] else { return nil }
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 0xff)); carry >>= 8 }
        }
        let zeros = s.prefix { $0 == "1" }.count
        return Array(repeating: 0, count: zeros) + bytes.reversed()
    }

    static func base58Encode(_ bytes: [UInt8]) -> String {
        var digits: [Int] = []
        for b in bytes {
            var carry = Int(b)
            for i in 0..<digits.count {
                carry += digits[i] << 8
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        let zeros = bytes.prefix { $0 == 0 }.count
        return String(repeating: "1", count: zeros) + String(digits.reversed().map { alphabet[$0] })
    }

    // MARK: - JSON-RPC

    /// One request body. The sequencer takes positional params.
    static func request(_ method: String, _ params: [Any], id: Int = 1) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    /// The `result` of a reply, or nil for an `error` object or anything else.
    /// Split from the transport so the selftest can hold the measured shapes.
    static func result(_ reply: Any?) -> Any? {
        guard let obj = reply as? [String: Any], obj["error"] == nil else { return nil }
        return obj["result"]
    }

    /// `getAccount`'s result. Measured 2026-09-29:
    /// `{"program_owner":[8 × u32],"balance":1481100,"data":[…],"nonce":0}`.
    /// `balance` is a u128 on the wire, which JSON carries as a number; it is
    /// read through `Decimal` rather than `Int`, because a u128 is wider than
    /// anything `JSONSerialization` hands back as an integer (the `FramesMoney`
    /// lesson: wei wider than `UInt64` returned nil).
    struct Account: Equatable {
        let balance: Decimal
        let nonce: Int
        /// The eight u32 words of the owning program's id, as the node sends
        /// them. All-zero is the node's answer for an account nobody has
        /// initialised — which is also what every unknown id returns.
        let programOwner: [UInt32]
        var isUninitialised: Bool { programOwner.allSatisfy { $0 == 0 } && nonce == 0 && balance == 0 }
    }

    static func account(_ result: Any?) -> Account? {
        guard let obj = result as? [String: Any],
              let balance = decimal(obj["balance"]),
              let owner = obj["program_owner"] as? [Any]
        else { return nil }
        let words = owner.compactMap { ($0 as? NSNumber).map { UInt32(truncating: $0) } }
        guard words.count == 8 else { return nil }
        let nonce = (obj["nonce"] as? NSNumber)?.intValue ?? 0
        return Account(balance: balance, nonce: nonce, programOwner: words)
    }

    /// A u128 carried as a JSON number or a decimal string, never through a
    /// `Double` (which rounds past 2^53).
    static func decimal(_ any: Any?) -> Decimal? {
        switch any {
        case let s as String: return Decimal(string: s)
        case let n as NSNumber:
            // `stringValue` keeps every digit JSONSerialization parsed.
            return Decimal(string: n.stringValue)
        default: return nil
        }
    }

    /// `getProgramIds`' result: name → the eight-word id. Pinned to the
    /// running LEZ revision, which is why it is READ, never shipped: a
    /// testnet reset or an upgrade changes every id (measured names today:
    /// amm, authenticated_transfer, pinata, privacy_preserving_circuit, token).
    static func programIDs(_ result: Any?) -> [String: [UInt32]] {
        guard let obj = result as? [String: Any] else { return [:] }
        var out: [String: [UInt32]] = [:]
        for (name, value) in obj {
            guard let arr = value as? [Any] else { continue }
            let words = arr.compactMap { ($0 as? NSNumber).map { UInt32(truncating: $0) } }
            if words.count == 8 { out[name] = words }
        }
        return out
    }

    /// The program an account belongs to, by name, when the id is known.
    static func programName(_ owner: [UInt32], in ids: [String: [UInt32]]) -> String? {
        ids.first { $0.value == owner }?.key
    }

    /// The name a person reads for a program id. Measured names, spelled out;
    /// an unknown one keeps its own name with the underscores opened up.
    static func programLabel(_ name: String) -> String {
        switch name {
        case "authenticated_transfer": return "Transfers"
        case "token": return "Tokens"
        case "pinata": return "Faucet"
        case "amm": return "AMM"
        case "privacy_preserving_circuit": return "Private transfers"
        default: return name.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Blocks (v0.2 layout)

extension LogosWire {

    /// A block, as far as a watch needs it. Layout MEASURED 2026-09-29 against
    /// the live testnet, which runs LEZ's v0.2.x format (tags v0.2.2–v0.2.4
    /// are byte-identical; `main` and v0.3.0-rc1 are NOT — v0.3 adds a
    /// `producer` to the header and reshapes the message). Every testnet
    /// block 1…30,320 decodes with this reader to its exact length:
    ///
    ///     block_id u64 | prev_hash [32] | hash [32] | timestamp u64 ms (@72)
    ///     | signature [64] | Vec<LeeTransaction> | bedrock_status u8
    ///
    /// **Exact length or nil.** A reader that stops early on a drifted layout
    /// reads garbage as a valid block — a wrong amount on a real row — so a
    /// block that does not end where the reader ends is refused whole, and
    /// the walk stops rather than skip it (`LogosIngest.walk`).
    struct Block {
        let id: Int
        let timestamp: Date
        let transactions: [Transaction]
    }

    struct Transaction {
        enum Kind { case publicCall, privacyPreserving, programDeployment }
        let kind: Kind
        /// SHA-256 of the transaction's bytes WITHOUT the variant tag —
        /// verified live for all three kinds against `getTransaction`.
        let hashHex: String
        /// `[u32; 8]`; empty for a private or deployment transaction.
        let programID: [UInt32]
        /// Public: the message's account ids, in instruction order. Private:
        /// the public accounts whose post-state it carries.
        let accounts: [[UInt8]]
        /// risc0-serde words; empty unless public.
        let instruction: [UInt32]
        let signers: Int
    }

    static func block(_ data: Data) -> Block? {
        var r = Reader(Array(data))
        guard let id = r.u64(), r.skip(64),
              let ms = r.u64(), r.skip(64),
              let count = r.u32(), count < 100_000
        else { return nil }
        var txs: [Transaction] = []
        for _ in 0..<count {
            guard let tx = transaction(&r) else { return nil }
            txs.append(tx)
        }
        guard r.u8() != nil, r.atEnd else { return nil }
        return Block(id: Int(id), timestamp: Date(timeIntervalSince1970: Double(ms) / 1000),
                     transactions: txs)
    }

    private static func transaction(_ r: inout Reader) -> Transaction? {
        guard let tag = r.u8() else { return nil }
        let start = r.offset
        let kind: Transaction.Kind
        var program: [UInt32] = []
        var accounts: [[UInt8]] = []
        var instruction: [UInt32] = []
        var signers = 0
        switch tag {
        case 0:
            kind = .publicCall
            guard let p = r.words(8),
                  let a = r.vec({ $0.bytes(32) }),
                  r.vec({ $0.skip(16) ? () : nil }) != nil,        // nonces, u128 each
                  let n = r.u32(), let i = r.words(Int(n)),
                  let s = r.vec({ $0.skip(96) ? () : nil })       // (sig 64, pk 32)
            else { return nil }
            program = p; accounts = a; instruction = i; signers = s.count
        case 1:
            kind = .privacyPreserving
            guard let a = r.vec({ (r: inout Reader) -> [UInt8]? in
                      guard let id = r.bytes(32), r.skip(32),          // owner [u32; 8]
                            r.skip(16), r.blob(), r.skip(16)           // balance, data, nonce
                      else { return nil }
                      return id
                  }),
                  r.vec({ $0.skip(16) ? () : nil }) != nil,        // nonces
                  r.vec({ (r: inout Reader) -> Void? in                             // private actions
                      guard r.skip(96), r.blob(), r.blob(), r.skip(1) else { return nil }
                      return ()
                  }) != nil,
                  r.optionU64(), r.optionU64(), r.optionU64(), r.optionU64(),
                  let s = r.vec({ $0.skip(96) ? () : nil }), r.blob()
            else { return nil }
            accounts = a; signers = s.count
        case 2:
            kind = .programDeployment
            guard r.blob() else { return nil }
        default:
            return nil
        }
        let body = r.slice(from: start)
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return Transaction(kind: kind, hashHex: hash, programID: program,
                           accounts: accounts, instruction: instruction, signers: signers)
    }

    /// Borsh, little-endian: a Vec or String is a u32 count then its items;
    /// an Option is a u8 flag; a u128 is 16 bytes.
    struct Reader {
        private let b: [UInt8]
        private(set) var offset = 0
        init(_ bytes: [UInt8]) { b = bytes }
        var atEnd: Bool { offset == b.count }

        mutating func skip(_ n: Int) -> Bool {
            guard n >= 0, offset + n <= b.count else { return false }
            offset += n; return true
        }
        mutating func bytes(_ n: Int) -> [UInt8]? {
            guard n >= 0, offset + n <= b.count else { return nil }
            defer { offset += n }
            return Array(b[offset..<offset + n])
        }
        mutating func u8() -> UInt8? { bytes(1)?.first }
        mutating func u32() -> UInt32? {
            bytes(4).map { $0.reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        }
        mutating func u64() -> UInt64? {
            bytes(8).map { $0.reversed().reduce(0) { $0 << 8 | UInt64($1) } }
        }
        mutating func words(_ n: Int) -> [UInt32]? {
            guard n >= 0, n < 1_000_000 else { return nil }
            var out: [UInt32] = []
            out.reserveCapacity(n)
            for _ in 0..<n { guard let w = u32() else { return nil }; out.append(w) }
            return out
        }
        /// A `Vec<u8>` read past, length-checked.
        mutating func blob() -> Bool {
            guard let n = u32() else { return false }
            return skip(Int(n))
        }
        mutating func optionU64() -> Bool {
            guard let flag = u8() else { return false }
            switch flag { case 0: return true; case 1: return skip(8); default: return false }
        }
        mutating func vec<T>(_ item: (inout Reader) -> T?) -> [T]? {
            guard let n = u32(), n < 1_000_000 else { return nil }
            var out: [T] = []
            for _ in 0..<n { guard let x = item(&self) else { return nil }; out.append(x) }
            return out
        }
        func slice(from start: Int) -> [UInt8] { Array(b[start..<offset]) }
    }
}

// MARK: - Events

extension LogosWire {

    /// What a transaction means for ONE watched account — one row.
    struct Event: Equatable {
        let account: String       // base58
        let title: String
        let tags: [String]
    }

    /// The per-block clock transaction's program (first word). Not listed by
    /// `getProgramIds`, signed by nobody, touching three ASCII-named system
    /// accounts, in every block — skipped before anything else.
    static let clockProgramWord: UInt32 = 96_247_601

    /// A u128 in risc0-serde words: four u32, least-significant FIRST
    /// (measured: block 25894's transfer is `[0, 40, 0, 0, 0]`).
    static func u128(_ w: ArraySlice<UInt32>) -> Decimal? {
        guard w.count == 4 else { return nil }
        var value = Decimal(0)
        for word in w.reversed() { value = value * 4_294_967_296 + Decimal(word) }
        return value
    }

    /// A risc0-serde String: its byte length, then the bytes packed four to a
    /// word, little-endian, zero-padded. Returns the string and the words used.
    static func string(_ w: ArraySlice<UInt32>) -> (String, Int)? {
        guard let n = w.first.map(Int.init), n <= 256 else { return nil }
        let wordsUsed = (n + 3) / 4
        guard w.count >= 1 + wordsUsed else { return nil }
        var bytes: [UInt8] = []
        for word in w.dropFirst().prefix(wordsUsed) {
            for k in 0..<4 { bytes.append(UInt8((word >> (8 * UInt32(k))) & 0xff)) }
        }
        guard let s = String(bytes: bytes.prefix(n), encoding: .utf8) else { return nil }
        return (s, 1 + wordsUsed)
    }

    /// A native or token amount. **No unit, on purpose**: measured, LEZ has
    /// no symbol and no decimals anywhere — native balances are raw integers
    /// (the faucet's prize is the literal 150), a token carries only a name,
    /// and "LGO" is the L1's unit, not this zone's. A row saying "25 LGO"
    /// would be naming money that is not what moved.
    static func amount(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Every event `tx` makes for the accounts in `watched`. Titles follow
    /// the house seam (` — `, `TitleSeam`), and every tag is STATE, never
    /// subject (HomeComposition's mechanical list carries them).
    static func events(_ tx: Transaction, watched: Set<Data>,
                       programs: [String: [UInt32]]) -> [Event] {
        let mine = tx.accounts.enumerated().filter { watched.contains(Data($0.element)) }
        guard !mine.isEmpty else { return [] }
        func id(_ i: Int) -> String { base58Encode(tx.accounts[i]) }
        func other(_ i: Int) -> String { short(id(i)) }

        switch tx.kind {
        case .programDeployment:
            return []
        case .privacyPreserving:
            // Only the PUBLIC side is visible: which account's state it
            // changed, never who paid whom or how much.
            return mine.map { Event(account: id($0.offset), title: "Private transaction",
                                    tags: ["Private"]) }
        case .publicCall:
            break
        }
        if tx.programID.first == clockProgramWord { return [] }
        let name = programName(tx.programID, in: programs)
        let ins = tx.instruction[...]
        var out: [Event] = []

        switch (name, ins.first) {
        case ("authenticated_transfer", 0?) where tx.accounts.count == 2:
            guard let value = u128(ins.dropFirst().prefix(4)) else { break }
            let n = amount(value)
            for (i, _) in mine {
                out.append(i == 1
                    ? Event(account: id(1), title: "Received \(n) — from \(other(0))", tags: ["Received"])
                    : Event(account: id(0), title: "Sent \(n) — to \(other(1))", tags: ["Sent"]))
            }
        case ("authenticated_transfer", 1?):
            out = mine.map { Event(account: id($0.offset), title: "Account initialized", tags: ["Initialized"]) }
        case ("token", 0?) where tx.accounts.count == 2:
            guard let value = u128(ins.dropFirst().prefix(4)) else { break }
            let n = amount(value)
            for (i, _) in mine {
                out.append(i == 1
                    ? Event(account: id(1), title: "Received \(n) tokens — from \(other(0))", tags: ["Received"])
                    : Event(account: id(0), title: "Sent \(n) tokens — to \(other(1))", tags: ["Sent"]))
            }
        case ("token", 1?):
            let made = string(ins.dropFirst()).map { "Created token \($0.0)" } ?? "Created a token"
            out = mine.map { Event(account: id($0.offset), title: made, tags: ["Created"]) }
        case ("token", 5?):
            guard let value = u128(ins.dropFirst().prefix(4)) else { break }
            out = mine.map { Event(account: id($0.offset), title: "Minted \(amount(value)) tokens",
                                   tags: ["Minted"]) }
        case ("token", 4?):
            guard let value = u128(ins.dropFirst().prefix(4)) else { break }
            out = mine.map { Event(account: id($0.offset), title: "Burned \(amount(value)) tokens",
                                   tags: ["Burned"]) }
        case ("pinata", _):
            out = mine.map { Event(account: id($0.offset), title: "Faucet claim", tags: ["Faucet"]) }
        default:
            break
        }
        if out.isEmpty {
            // Anything else a watched account took part in: named by its
            // program, never guessed at.
            let label = name.map(programLabel) ?? "a program"
            out = mine.map { Event(account: id($0.offset), title: "Used \(label)", tags: ["Program"]) }
        }
        return out
    }
}
