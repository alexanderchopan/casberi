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
        var text = clean(raw)
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

    /// What a paste carries around an id (prd §1034): whitespace and
    /// invisible marks (a byte-order mark, zero-width spaces), the quotes or
    /// backticks a chat wraps it in, the period that ends its sentence, and
    /// the explorer link it was copied from. Measured: each one turned a
    /// good id into "That isn't an LEZ account id".
    static func clean(_ raw: String) -> String {
        let invisible: Set<Character> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
        var text = String(raw.filter { !invisible.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "/account/", options: .backwards) {
            text = String(text[range.upperBound...].prefix { !"/?#".contains($0) })
        }
        let wrap = CharacterSet(charactersIn: "\"'`“”‘’<>()[]")
        let trailing = CharacterSet(charactersIn: ".,;!")
        var last = ""
        while text != last {
            last = text
            text = text.trimmingCharacters(in: wrap)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            while let end = text.unicodeScalars.last, trailing.contains(end) { text.removeLast() }
        }
        return text
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

    /// `getAccountBalance`'s result: the native balance, a bare number.
    /// Measured 2026-09-30 on LEZ v0.3. `getAccount` no longer carries a
    /// balance or an owning program: a v0.3 account is `{nonce, data:
    /// {shards}}`, one shard per program that keeps data on it, the native
    /// balance among them — so the balance is asked for by name, and the
    /// v0.2 "owner" line has nothing left to read (prd §1007).
    ///
    /// `balance` is a u128 on the wire, which JSON carries as a number; it is
    /// read through `Decimal` rather than `Int`, because a u128 is wider than
    /// anything `JSONSerialization` hands back as an integer (the `FramesMoney`
    /// lesson: wei wider than `UInt64` returned nil).
    static func balance(_ result: Any?) -> Decimal? { decimal(result) }

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
}

// MARK: - Blocks (v0.3 layout)

extension LogosWire {

    /// A block, as far as a watch needs it. Layout read from LEZ's own source
    /// at tag v0.3.0 (`lez/common/src/block.rs`, `lee/state_machine`) and
    /// MEASURED 2026-09-30 against the live testnet, which was reset onto
    /// v0.3 that day: every block 1…281 decodes with this reader to its exact
    /// length. v0.2's reader refused every one of them — v0.3 put the
    /// producer's key in the header, named programs by ACCOUNT id, carried
    /// instructions as bytes and added a fee to the message (prd §1007):
    ///
    ///     block_id u64 | prev_hash [32] | hash [32] | timestamp u64 ms (@72)
    ///     | producer [32] | signature [64] | Vec<LeeTransaction> | bedrock_status u8
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
        enum Kind { case publicCall, privacyPreserving }
        let kind: Kind
        /// SHA-256 of the transaction's bytes WITHOUT the variant tag — the
        /// node's own `hash()` is SHA-256 over the transaction's Borsh, and
        /// the variant tag belongs to the enum around it.
        let hashHex: String
        /// The program's ACCOUNT id, 32 bytes; empty for a private
        /// transaction. The native token is all zeros.
        let program: [UInt8]
        /// Public: the shard selectors' account ids, in instruction order,
        /// each once. Private: the public accounts whose state it changed.
        let accounts: [[UInt8]]
        /// The instruction's Borsh bytes; empty unless public.
        let instruction: [UInt8]
        let signers: Int
        /// Public only: whether the message declared a fee. A transaction
        /// with no signer and no fee is the node's own (the per-block clock
        /// and its companion, genesis deposits) — "fee-exempt (system)" in
        /// LEZ's words.
        let paysFee: Bool
    }

    static func block(_ data: Data) -> Block? {
        var r = Reader(Array(data))
        guard let id = r.u64(), r.skip(64),
              let ms = r.u64(), r.skip(32 + 64),                  // producer, signature
              let count = r.u32(), count < 100_000
        else { return nil }
        var txs: [Transaction] = []
        for _ in 0..<count {
            guard let tx = transaction(&r) else { return nil }
            txs.append(tx)
        }
        guard let status = r.u8(), status < 3, r.atEnd else { return nil }
        return Block(id: Int(id), timestamp: Date(timeIntervalSince1970: Double(ms) / 1000),
                     transactions: txs)
    }

    /// A block's header alone (prd §1035): its id, its own hash and its
    /// time — what reset detection needs, read without decoding the body, so
    /// a body layout the reader cannot follow never hides a reset.
    struct Header: Equatable {
        let id: Int
        let hashHex: String
        let timestamp: Date
    }

    static func header(_ data: Data) -> Header? {
        var r = Reader(Array(data))
        guard let id = r.u64(), r.skip(32), let hash = r.bytes(32), let ms = r.u64() else { return nil }
        return Header(id: Int(id), hashHex: hash.map { String(format: "%02x", $0) }.joined(),
                      timestamp: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// Whether the transaction is the network's own (prd §1035): signed by
    /// nobody and paying no fee — the per-block clock and its companion,
    /// genesis deposits. An account one of these touches is a NETWORK
    /// account, not anybody's wallet.
    static func isSystem(_ tx: Transaction) -> Bool {
        tx.kind == .publicCall && tx.signers == 0 && !tx.paysFee
    }

    private static func transaction(_ r: inout Reader) -> Transaction? {
        guard let tag = r.u8() else { return nil }
        let start = r.offset
        let kind: Transaction.Kind
        var program: [UInt8] = []
        var accounts: [[UInt8]] = []
        var instruction: [UInt8] = []
        var signers = 0
        var paysFee = false
        switch tag {
        case 0:
            kind = .publicCall
            guard let p = r.bytes(32),
                  let selectors = r.vec({ (r: inout Reader) -> [UInt8]? in  // (account, shard's program)
                      guard let id = r.bytes(32), r.skip(32) else { return nil }
                      return id
                  }),
                  r.vec({ $0.skip(16) ? () : nil }) != nil,        // nonces, u128 each
                  let n = r.u32(), let i = r.bytes(Int(n)),
                  let fee = r.option({ $0.skip(32 + 8 + 8 + 16) ? () : nil }),  // payer, gas, tip, max
                  let s = r.vec({ $0.skip(96) ? () : nil })       // (sig 64, pk 32)
            else { return nil }
            program = p; instruction = i; signers = s.count; paysFee = fee != nil
            for id in selectors where !accounts.contains(id) { accounts.append(id) }
        case 1:
            kind = .privacyPreserving
            guard let a = r.vec({ (r: inout Reader) -> [UInt8]? in  // public actions
                      guard let id = r.bytes(32),
                            r.vec({ (r: inout Reader) -> Void? in   // effects
                                guard r.skip(64), r.blob() else { return nil }
                                return ()
                            }) != nil
                      else { return nil }
                      return id
                  }),
                  r.vec({ $0.skip(16) ? () : nil }) != nil,        // nonces
                  r.vec({ (r: inout Reader) -> Void? in             // private actions
                      guard r.skip(96), r.blob(), r.blob(), r.skip(1) else { return nil }
                      return ()
                  }) != nil,
                  r.option({ $0.u64() }) != nil, r.option({ $0.u64() }) != nil,   // block window
                  r.option({ $0.u64() }) != nil, r.option({ $0.u64() }) != nil,   // time window
                  r.vec({ (r: inout Reader) -> Void? in             // program image claims
                      switch r.u8() {
                      case 0?: return r.skip(64) ? () : nil         // disclosed: account, image
                      case 1?: return r.skip(32) ? () : nil         // undisclosed: root
                      default: return nil
                      }
                  }) != nil,
                  let s = r.vec({ $0.skip(96) ? () : nil }), r.blob()  // signers, proof
            else { return nil }
            accounts = a; signers = s.count
        default:
            return nil
        }
        let body = r.slice(from: start)
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return Transaction(kind: kind, hashHex: hash, program: program, accounts: accounts,
                           instruction: instruction, signers: signers, paysFee: paysFee)
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
        /// A `Vec<u8>` read past, length-checked.
        mutating func blob() -> Bool {
            guard let n = u32() else { return false }
            return skip(Int(n))
        }
        /// `.some(nil)` is a Borsh `None`; nil is a malformed option.
        mutating func option<T>(_ item: (inout Reader) -> T?) -> T?? {
            switch u8() {
            case 0?: return .some(nil)
            case 1?: return item(&self).map { .some($0) }
            default: return nil
            }
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

    /// The native token's program account: all zeros (`NATIVE_TOKEN_PROGRAM_ID`).
    static let nativeProgram = [UInt8](repeating: 0, count: 32)

    /// A u128 in Borsh: sixteen bytes, least-significant FIRST.
    static func u128(_ b: ArraySlice<UInt8>) -> Decimal? {
        guard b.count == 16 else { return nil }
        var value = Decimal(0)
        for byte in b.reversed() { value = value * 256 + Decimal(byte) }
        return value
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
    ///
    /// Only the NATIVE transfer is named with its amount. v0.3 names every
    /// other program by an account id `getProgramIds` does not map to (it
    /// answers image ids), and no token transfer has run on the new chain to
    /// read one against — so anything else is "Used a program", never a
    /// guessed amount (prd §1007).
    static func events(_ tx: Transaction, watched: Set<Data>) -> [Event] {
        let mine = tx.accounts.enumerated().filter { watched.contains(Data($0.element)) }
        guard !mine.isEmpty else { return [] }
        func id(_ i: Int) -> String { base58Encode(tx.accounts[i]) }
        func other(_ i: Int) -> String { short(id(i)) }

        if tx.kind == .privacyPreserving {
            // Only the PUBLIC side is visible: which account's state it
            // changed, never who paid whom or how much.
            return mine.map { Event(account: id($0.offset), title: "Private transaction",
                                    tags: ["Private"]) }
        }
        // The node's own transactions: the clock and its companion in every
        // block, touching system accounts, signed by nobody and paying nothing.
        if isSystem(tx) { return [] }

        let ins = tx.instruction[...]
        // `native_token::Instruction::Transfer { amount }`: variant 0, a u128.
        if tx.program == nativeProgram, tx.accounts.count == 2,
           ins.count == 17, ins.first == 0, let value = u128(ins.dropFirst()) {
            let n = amount(value)
            return mine.map { i, _ in
                i == 1
                    ? Event(account: id(1), title: "Received \(n) — from \(other(0))", tags: ["Received"])
                    : Event(account: id(0), title: "Sent \(n) — to \(other(1))", tags: ["Sent"])
            }
        }
        // Anything else a watched account took part in: said, never guessed at.
        return mine.map { Event(account: id($0.offset), title: "Used a program", tags: ["Program"]) }
    }
}

// MARK: - Resets (prd §1035)

extension LogosWire {

    /// How long after a reset the page names it. Past a month an empty
    /// account is somebody's quiet account, not the reset's.
    static let resetNoticeWindow: TimeInterval = 30 * 24 * 3600

    /// Whether to say the testnet was reset: the current chain began within
    /// `resetNoticeWindow`, and a watched account reads exactly zero — the
    /// one thing a reset does to an account, and the confusion it caused
    /// (2026-10-01: three ids from the Logos team, all empty, no word why).
    /// An unread balance is not a zero.
    static func showsResetNote(chainStart: Date?, now: Date, balances: [Decimal?]) -> Bool {
        guard let chainStart, now.timeIntervalSince(chainStart) < resetNoticeWindow,
              now >= chainStart else { return false }
        return balances.contains { $0 == 0 }
    }
}

// MARK: - Your node (prd §989)

extension LogosWire {

    /// A Logos blockchain node's own HTTP API, read keylessly. MEASURED in
    /// source (logos-blockchain @11711d3): it serves `127.0.0.1:8080` by
    /// default with NO auth layer — Basecamp's embedded node leaves
    /// `http_addr` empty, which is that address — and the public testnet's
    /// `401 Basic realm="Restricted API"` is a proxy in front, not the node.
    ///
    /// **Only GETs, and only these five.** The same API serves writes
    /// (`/leader/claim`, `/pow/claim`, `/pow/mining/start`, `/wallet/*`,
    /// `/mempool/add/tx`), which is why a node reached over the network is an
    /// exposure the page names.
    static let nodeInfoPath = "/cryptarchia/info"
    static let nodePeersPath = "/network/info"
    static let nodeVouchersPath = "/leader/claim/vouchers"
    /// Proof-of-work mining (prd §1016), read from logos-blockchain 0.3.0's
    /// source: `{is_mining, are_rewards_enabled, auto_claim}` and
    /// `{claimable_tickets, slots_until_expiry}`, both plain GETs. The phone
    /// never mines (App Review 3.1.5(b)(iii) bans it on device); it reads a
    /// node that mines somewhere else.
    static let nodeMiningPath = "/pow/status"
    static let nodeTicketsPath = "/pow/rewards/claimable"

    /// The address someone types: `host:port`, a bare host (port 8080, the
    /// node's default), or a full `http(s)://` URL. Returns the base URL with
    /// no trailing slash, or nil for anything that is not an address.
    static func nodeBase(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.path.isEmpty || url.path == "/"
        else { return nil }
        // No port means the node's own default, 8080 — never the scheme's 80,
        // which no node listens on.
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(hostPart):\(url.port ?? 8080)"
    }

    /// What the page's ONE field means by what was typed: an account id, a
    /// node, or neither. An id wins — a base58 id is also a valid bare host
    /// name, so a mistyped id must never become a node at `<typo>:8080`. A node
    /// needs a dot, a colon or `localhost` to be read as one.
    ///
    /// **Sixty-four hex characters** are what Logos's command-line wallet
    /// prints for an account's public KEY ("With pk …", under the base58 id),
    /// so a valid secp256k1 x-only key is read as one and watched as its
    /// account (`.key`, the id derived exactly as LEZ does). Hex that is not
    /// a point on the curve is no LEZ key at all — measured, one such paste
    /// was a Logos chat address — so it is named (`.notKey`) rather than
    /// turned into an account nobody owns, which would read as an empty one.
    enum Entry: Equatable { case account(String), key(String), privateAccount, node(String), notKey, invalid }

    static func entry(_ raw: String) -> Entry {
        if let id = parseAccountID(raw) {
            return id.visibility == .privateAccount ? .privateAccount : .account(id.base58)
        }
        let cleaned = clean(raw)
        if let bytes = hexKey(cleaned) {
            guard isXOnlyKey(bytes) else { return .notKey }
            return .key(accountID(publicKey: bytes))
        }
        let text = cleaned.lowercased()
        guard text.contains(".") || text.contains(":") || text.hasPrefix("localhost"),
              let base = nodeBase(cleaned) else { return .invalid }
        return .node(base)
    }

    /// Whether the field's verb can act: everything but nonsense and a hex
    /// string that is not a key.
    static func arms(_ entry: Entry) -> Bool { entry != .invalid && entry != .notKey }

    /// 32 bytes written as 64 hex characters, `0x` allowed; nil otherwise.
    static func hexKey(_ text: String) -> [UInt8]? {
        var hex = text.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(byte)
            i = j
        }
        return out
    }

    /// A public account's id from its key, as LEZ derives it
    /// (`lee/state_machine/src/signature/public_key.rs`, v0.3.0):
    /// `SHA256("/LEE/v0.3/AccountId/Public/" ‖ five zero bytes ‖ key)`.
    static func accountID(publicKey: [UInt8]) -> String {
        let prefix = Array("/LEE/v0.3/AccountId/Public/".utf8) + [UInt8](repeating: 0, count: 5)
        return base58Encode(Array(SHA256.hash(data: prefix + publicKey)))
    }

    /// Whether 32 bytes are a BIP-340 x-only public key: x below the field
    /// prime and x³ + 7 a square mod p (Euler's criterion). About half of
    /// random 32-byte strings are not, which is what tells a key from other
    /// hex. Plain 256-bit arithmetic, so this file stays Foundation-only.
    static func isXOnlyKey(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 32 else { return false }
        let x = Secp.from(bytes)
        guard Secp.less(x, Secp.p) else { return false }
        let y2 = Secp.add(Secp.mul(Secp.mul(x, x), x), [7, 0, 0, 0])
        return Secp.pow(y2, Secp.halfPMinusOne) == [1, 0, 0, 0]
    }

    /// Whether an address stays on this machine. Anything else reaches a node
    /// over a network — the case the page warns about, because the node's API
    /// answers writes as readily as reads.
    static func isLoopback(_ base: String) -> Bool {
        guard let host = URL(string: base)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasPrefix("127.")
    }

    /// What one read of the node says. `reachable == false` is a reading too:
    /// a node that stopped answering is news, not an error to swallow.
    struct NodeSnapshot: Codable, Equatable {
        var reachable: Bool
        /// `phase`: AwaitingGenesisTime | InitialBlockDownload |
        /// ProlongedBootstrapPeriod | Following. Following is "in sync".
        var phase: String?
        var height: Int?
        var tip: String?
        var peers: Int?
        /// Leader-reward vouchers the node's wallet holds, unclaimed, and what
        /// they are worth together at the tip. nil when the read failed.
        var vouchers: Int?
        var claimable: Decimal?
        /// Whether the node is mining, and whether this network pays for it.
        /// nil when the read failed or the node has no such route. Mining is
        /// OFF at every start and is not saved (measured in source), so a
        /// restart reads as it stopping.
        var mining: Bool?
        var miningPays: Bool?
        /// Mining reward tickets won and waiting to be claimed. A COUNT and
        /// never an amount: the route returns none, and a claim can still
        /// fail (the pool exhausted, the reward below the fee).
        var tickets: Int?

        var synced: Bool { reachable && phase == "Following" }
        static let unreachable = NodeSnapshot(reachable: false)

        /// What to keep after reading `self`: an unreachable reading keeps
        /// everything `last` knew, marked unreachable, so the next reading is
        /// measured against the node as it was, not against a blank.
        func remembering(_ last: NodeSnapshot?) -> NodeSnapshot {
            guard !reachable, var kept = last else { return self }
            kept.reachable = false
            return kept
        }
    }

    /// `/cryptarchia/info`: `{cryptarchia_info: {lib, lib_slot, tip, slot,
    /// height, state}, phase}`. Read nested, and flat as a fallback — the
    /// docs' example and the source agree on nested today, and a flattening
    /// would otherwise read as a node with no height.
    static func nodeInfo(_ json: Any?) -> (phase: String?, height: Int?, tip: String?)? {
        guard let obj = json as? [String: Any] else { return nil }
        let info = obj["cryptarchia_info"] as? [String: Any] ?? obj
        let height = (info["height"] as? NSNumber)?.intValue
        let tip = info["tip"] as? String
        guard height != nil || tip != nil else { return nil }
        return (obj["phase"] as? String, height, tip)
    }

    /// `/network/info`: `n_peers`.
    static func nodePeers(_ json: Any?) -> Int? {
        ((json as? [String: Any])?["n_peers"] as? NSNumber)?.intValue
    }

    /// `/leader/claim/vouchers?tip=`: `{tip, vouchers: [{commitment,
    /// nullifier}], reward_amount, total_claimable}`.
    static func nodeVouchers(_ json: Any?) -> (count: Int, claimable: Decimal)? {
        guard let obj = json as? [String: Any], let list = obj["vouchers"] as? [Any] else { return nil }
        return (list.count, decimal(obj["total_claimable"]) ?? 0)
    }

    /// `/pow/status`: `{is_mining, are_rewards_enabled, auto_claim}`.
    static func nodeMining(_ json: Any?) -> (mining: Bool, pays: Bool?)? {
        guard let obj = json as? [String: Any], let mining = obj["is_mining"] as? Bool else { return nil }
        return (mining, obj["are_rewards_enabled"] as? Bool)
    }

    /// `/pow/rewards/claimable`: `{claimable_tickets, slots_until_expiry}`.
    static func nodeTickets(_ json: Any?) -> Int? {
        ((json as? [String: Any])?["claimable_tickets"] as? NSNumber)?.intValue
    }

    /// What changed between two readings, as rows. Nothing on FIRST sight
    /// (`old == nil`): a node already synced when you started watching did not
    /// just sync, and a voucher already waiting did not just arrive. Peer
    /// counts and heights move every minute and are the roster's, never a row.
    struct NodeEvent: Equatable {
        let kind: String      // offline | back | synced | behind | vouchers | mining | idle | tickets
        let title: String
        let tags: [String]
    }

    /// `old` is the LAST-KNOWN state: a reading taken while the node was
    /// down keeps the phase and vouchers from before (`remembering`), so a
    /// node that comes back in sync, holding the vouchers it held, says only
    /// that it is answering — measured against a stand-in node, the first cut
    /// re-announced both as news.
    static func nodeEvents(old: NodeSnapshot?, new: NodeSnapshot) -> [NodeEvent] {
        guard let old else { return [] }
        var out: [NodeEvent] = []
        if old.reachable && !new.reachable {
            return [NodeEvent(kind: "offline", title: "Your node stopped answering", tags: ["Node", "Offline"])]
        }
        guard new.reachable else { return [] }
        if !old.reachable {
            out.append(NodeEvent(kind: "back", title: "Your node is answering", tags: ["Node"]))
        }
        let wasSynced = old.phase == "Following"
        if new.synced && !wasSynced {
            let at = new.height.map { " — height \(amount(Decimal($0)))" } ?? ""
            out.append(NodeEvent(kind: "synced", title: "Your node is in sync\(at)", tags: ["Node", "Synced"]))
        } else if wasSynced && !new.synced {
            out.append(NodeEvent(kind: "behind", title: "Your node fell behind", tags: ["Node", "Behind"]))
        }
        if let count = new.vouchers, count > (old.vouchers ?? 0), let worth = new.claimable, worth > 0 {
            let noun = count == 1 ? "reward voucher" : "reward vouchers"
            out.append(NodeEvent(kind: "vouchers",
                                 title: "\(count) \(noun) ready — \(amount(worth)) claimable",
                                 tags: ["Rewards", "Voucher"]))
        }
        // Mining and its tickets land only between two readings that BOTH
        // know them: a node read before this route existed, or a read that
        // failed, is first sight, not a change.
        if let was = old.mining, let now = new.mining, was != now {
            out.append(now
                ? NodeEvent(kind: "mining", title: "Your node started mining", tags: ["Rewards", "Mining"])
                : NodeEvent(kind: "idle", title: "Your node stopped mining", tags: ["Rewards"]))
        }
        if let before = old.tickets, let count = new.tickets, count > before {
            let noun = count == 1 ? "mining ticket" : "mining tickets"
            out.append(NodeEvent(kind: "tickets", title: "\(count) \(noun) ready", tags: ["Rewards", "Ticket"]))
        }
        return out
    }

    /// The roster's line for the node.
    static func nodeLine(_ snap: NodeSnapshot?) -> String {
        guard let snap else { return "Not read yet" }
        guard snap.reachable else { return "Not answering" }
        var parts: [String] = [snap.synced ? "In sync" : "Syncing"]
        if let h = snap.height { parts.append("height \(amount(Decimal(h)))") }
        if let p = snap.peers { parts.append(p == 1 ? "1 peer" : "\(p) peers") }
        if snap.mining == true { parts.append("mining") }
        if let v = snap.vouchers, v > 0 { parts.append(v == 1 ? "1 voucher" : "\(v) vouchers") }
        return parts.joined(separator: " · ")
    }
}

/// secp256k1's field, mod p = 2^256 − 2^32 − 977: four 64-bit limbs, least
/// significant first. Just enough for `isXOnlyKey`'s one exponentiation.
private enum Secp {
    typealias U = [UInt64]
    static let p: U = [0xFFFF_FFFE_FFFF_FC2F, .max, .max, .max]
    /// 2^256 mod p, which is what folds a product's high half back in.
    static let fold: UInt64 = 0x1_0000_03D1
    static let halfPMinusOne: U = {
        let m = sub(p, [1, 0, 0, 0])
        return (0..<4).map { i in (m[i] >> 1) | (i < 3 ? m[i + 1] << 63 : 0) }
    }()

    static func from(_ bytes: [UInt8]) -> U {
        (0..<4).map { i in
            bytes[(3 - i) * 8 ..< (3 - i) * 8 + 8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        }
    }

    static func less(_ a: U, _ b: U) -> Bool {
        for i in (0..<4).reversed() where a[i] != b[i] { return a[i] < b[i] }
        return false
    }

    static func sub(_ a: U, _ b: U) -> U {
        var r = a, borrow: UInt64 = 0
        for i in 0..<4 {
            let (d1, o1) = a[i].subtractingReportingOverflow(b[i])
            let (d2, o2) = d1.subtractingReportingOverflow(borrow)
            r[i] = d2
            borrow = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return r
    }

    /// `top · 2^256 + r`, reduced: `top · fold` added back until nothing
    /// overflows, then one or two subtractions of p.
    static func reduce(_ r0: U, top t0: UInt64) -> U {
        var r = r0, top = t0
        while top > 0 {
            let (high, low) = top.multipliedFullWidth(by: fold)
            var carry = high
            let (s0, o0) = r[0].addingReportingOverflow(low)
            r[0] = s0
            carry &+= o0 ? 1 : 0
            for i in 1..<4 {
                let (s, o) = r[i].addingReportingOverflow(carry)
                r[i] = s
                carry = o ? 1 : 0
            }
            top = carry
        }
        while !less(r, p) { r = sub(r, p) }
        return r
    }

    static func add(_ a: U, _ b: U) -> U {
        var r = a, carry: UInt64 = 0
        for i in 0..<4 {
            let (s1, o1) = a[i].addingReportingOverflow(b[i])
            let (s2, o2) = s1.addingReportingOverflow(carry)
            r[i] = s2
            carry = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return reduce(r, top: carry)
    }

    static func mul(_ a: U, _ b: U) -> U {
        var t = [UInt64](repeating: 0, count: 8)
        for i in 0..<4 {
            var carry: UInt64 = 0
            for j in 0..<4 {
                let (high, low) = a[i].multipliedFullWidth(by: b[j])
                let (s1, o1) = t[i + j].addingReportingOverflow(low)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                t[i + j] = s2
                carry = high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            t[i + 4] = carry
        }
        // high · 2^256 + low ≡ low + high · fold
        var r = Array(t[0..<4]), carry: UInt64 = 0
        for i in 0..<4 {
            let (high, low) = t[i + 4].multipliedFullWidth(by: fold)
            let (s1, o1) = r[i].addingReportingOverflow(low)
            let (s2, o2) = s1.addingReportingOverflow(carry)
            r[i] = s2
            carry = high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
        }
        return reduce(r, top: carry)
    }

    static func pow(_ base: U, _ exponent: U) -> U {
        var result: U = [1, 0, 0, 0]
        for i in (0..<4).reversed() {
            for bit in (0..<64).reversed() {
                result = mul(result, result)
                if (exponent[i] >> UInt64(bit)) & 1 == 1 { result = mul(result, base) }
            }
        }
        return result
    }
}
