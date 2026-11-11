import Foundation
import CryptoKit
import CommonCrypto

/// A zk.money link, read without fetching it (2026-10-11). Shared: the app's
/// paste and the share extension both capture links, and BOTH must apply the
/// one rule this exists for:
///
/// - **A payment link** (`…/link#…`, `…/claim#…`) HOLDS funds: everything
///   after the `#` is the claim secret, and whoever has it can take the
///   money. It is a bearer credential, so it never reaches the row — the row
///   keeps the bare URL. A library row syncs to iCloud and lives in
///   Spotlight; a secret there is a secret everywhere. Since prd §1384 the
///   whole link goes to this device's Keychain instead (`ZkMoneyClaims`).
/// - **A request link** asks for money and holds none: base64url CBOR
///   (front-core `requestInlineCodec.ts`) naming the tag, amount, token, note
///   and expiry, which titles the row and dates it. zk.money writes them as
///   `…/pay/<tag>#<fragment>` now (`requestLinkMint.ts`, measured
///   2026-10-17); `…/request#` is the older spelling, read too.
enum ZkMoneyLink {

    static func display(_ tag: String) -> String { "\(tag).zk.money" }


    /// A zk.money link, read without fetching it.
    enum Link: Equatable {
        /// Asks for money; holds none. Every field the sender chose to show.
        case request(tag: String, amount: Decimal?, symbol: String?, note: String?, expires: Date?)
        /// Holds money: its fragment is the claim secret. `kept` is the URL
        /// with the fragment REMOVED — the only form ever stored.
        case payment(kept: String)
        /// A request as zk.money's Share writes it since (prd §1748):
        /// `zk.money/r#…`, a kind byte and a 16-byte seed. It names nothing
        /// by itself; the request is a record on Aztec the seed finds and
        /// opens (`open(fields:short:)`).
        case shortRequest(seed: [UInt8])
    }

    /// **A SHORT LINK (prd §1748, measured 2026-11-11).** `…/r#<17 bytes>`:
    /// kind 1 is a PAYMENT link — its seed is the claim secret, a bearer
    /// credential exactly as a long `/link#` fragment is — and kind 2 a
    /// request, whose seed only reads what the requester chose to show.
    struct Short: Equatable {
        static let payment: UInt8 = 1, request: UInt8 = 2
        let kind: UInt8
        let seed: [UInt8]
    }

    static func short(_ raw: String) -> Short? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              isZkMoneyHost(url.host), url.path.lowercased() == "/r",
              let fragment = url.fragment, let bytes = base64url(fragment), bytes.count == 17,
              bytes[0] == Short.payment || bytes[0] == Short.request else { return nil }
        return Short(kind: bytes[0], seed: Array(bytes[1...]))
    }

    static func base64url(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var b64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64).map { [UInt8]($0) }
    }

    static func isZkMoneyHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "zk.money" || host.hasSuffix(".zk.money")
    }

    /// A zk.money link by its address alone, read or not: what To holds
    /// while a request is looked up, which the sentence names and never
    /// spells (prd §1751). A tag (`zac.zk.money`) has no scheme and is not one.
    static func spellsLink(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased().hasPrefix("http") == true else { return false }
        return isZkMoneyHost(url.host)
    }

    static func link(_ raw: String) -> Link? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              isZkMoneyHost(url.host), let fragment = url.fragment, !fragment.isEmpty else { return nil }
        let path = url.path.lowercased()
        let shortLink = short(raw)
        if path.hasSuffix("/link") || path.hasSuffix("/claim") || shortLink?.kind == Short.payment {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.fragment = nil
            return .payment(kept: parts?.string ?? "https://\(url.host ?? "zk.money")\(url.path)")
        }
        if let shortLink, shortLink.kind == Short.request { return .shortRequest(seed: shortLink.seed) }
        let isRequest = path.hasSuffix("/request")
            || (path.hasPrefix("/pay/") && path.split(separator: "/").count == 2)
        guard isRequest, let packet = requestPacket(fragment) else { return nil }
        return packet
    }

    /// The request codec's fields, by integer key (front-core
    /// `requestInlineCodec.ts`, formats 1–4): 3 tag, 4 amount (big-endian
    /// bytes), 5 symbol, 6 note, 7 expiry (epoch ms), 9 decimals.
    ///
    /// **Format 4 (measured 2026-11-11 off a real request, prd §1746):** a
    /// 16-byte request id, an 8-byte field 11 this reader does not use, and
    /// NO symbol: the amount is dollars, as zk.money's own page draws it
    /// ("$0.01"). It is what `zk.money/r#<id>` expands to; the short link
    /// itself holds only the id, looked up on Aztec, and is not read here.
    static func requestPacket(_ fragment: String) -> Link? {
        base64url(fragment).flatMap(requestPacket(bytes:))
    }

    /// The packet itself: a long link's fragment decoded, or what a short
    /// link's record opens to.
    static func requestPacket(bytes: [UInt8]) -> Link? {
        guard bytes.count <= 2048,
              case .map(let map)? = CBOR.decode(bytes),
              case .uint(let format)? = map[1], (1...4).contains(format),
              case .text(let tag)? = map[3] else { return nil }
        var amount: Decimal?
        if case .bytes(let raw)? = map[4] {
            var value = Decimal(0)
            for byte in raw { value = value * 256 + Decimal(byte) }
            if value > 0 {
                // A link that names no decimals is a legacy one, whose
                // amounts were six places (the codec's own rule).
                var decimals = legacyDecimals
                if case .uint(let d)? = map[9] { decimals = Int(d) }
                amount = value / pow(10, decimals)
            }
        }
        var symbol: String?
        if case .text(let s)? = map[5] { symbol = dollarName(s) }
        var note: String?
        if case .text(let n)? = map[6], !n.isEmpty { note = n }
        var expires: Date?
        if case .uint(let ms)? = map[7] { expires = Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
        return .request(tag: tag.lowercased(), amount: amount, symbol: symbol, note: note, expires: expires)
    }

    static let legacyDecimals = 6

    /// **A REQUEST NAMES ITS TOKEN ON AZTEC (prd §1751, measured 2026-11-11
    /// off a real format-3 request; user: "it read the address but not the
    /// amount").** zk.money's dollar there is `oxDAI`, what a deposit of DAI
    /// becomes, and its own payer never reads the symbol: it sends the
    /// amount, plus the fee, in DAI (`accountlessRequest.ts`). Read as DAI
    /// here, so the row, the amount and the fee say what will be sent.
    static func dollarName(_ symbol: String) -> String {
        symbol.caseInsensitiveCompare("oxDAI") == .orderedSame ? "DAI" : symbol
    }

    /// How every request row's title begins: the cheap gate before a row's
    /// link is read again for Pay (prd §1745; `verbs(for:)` runs per row).
    static let requestTitleLead = "Payment request — "

    /// A kept link's title.
    static func title(_ link: Link) -> String {
        switch link {
        case .payment:
            return "zk.money payment link"
        case .request(let tag, let amount, let symbol, _, _):
            // A request that names no token asks in dollars (format 4).
            let what = amount.map { a in symbol.map { s in "\(plain(a)) \(s)" } ?? "$\(plain(a))" }
            return requestTitleLead + (what.map { "\($0) to " } ?? "to ") + display(tag)
        case .shortRequest:
            // Unread: the row names where it is from, and Pay reads the rest.
            return requestTitleLead + "zk.money"
        }
    }

    /// The line a request's body gains once Pay's send is taken (prd §1745).
    static func paidNote(on day: Date) -> String {
        "Paid \(day.formatted(.dateTime.month(.abbreviated).day()))"
    }

    static func plain(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }


    /// Every zk.money payment link in `text`, wherever it stands and however
    /// it is spelled (with or without a scheme, `www.`, `wallet.`), with its
    /// fragment removed; the whole links come back as `secrets`, each with a
    /// scheme. Run over ANY captured text, not only one whose first URL is
    /// zk.money's (review, 2026-10-17): `NSDataDetector` adds a scheme a
    /// pasted `zk.money/link#…` does not have, so a replace keyed on the
    /// detected URL left the secret in the row, and a link after another URL
    /// was never looked at.
    static func scrub(_ text: String) -> (text: String, secrets: [String]) {
        let pattern = #"(?i)\b((?:https?://)?(?:[a-z0-9-]+\.)*zk\.money(?:/[^\s#]*)?/(?:link|claim|r))#([^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let ns = text as NSString
        var secrets: [String] = []
        var out = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let base = ns.substring(with: m.range(at: 1))
            let whole = ns.substring(with: m.range)
            let withScheme = base.lowercased().hasPrefix("http") ? whole : "https://" + whole
            // A short REQUEST keeps its fragment: it is the request, and holds
            // no money. A short PAYMENT link loses it, as a long one does.
            if case .payment? = link(withScheme) { secrets.insert(withScheme, at: 0) }
            else if base.lowercased().hasSuffix("/r") { continue }
            out = (out as NSString).replacingCharacters(in: m.range, with: base)
        }
        return (out, secrets)
    }

    /// What a capture keeps of a zk.money link.
    struct Captured: Equatable {
        /// The row's content: for a payment link, the text with every copy of
        /// the link's fragment removed.
        let content: String
        let title: String
        let note: String?
        /// A payment link whole, for `ZkMoneyClaims` alone. Never a row field.
        let secret: String?
        /// A request's expiry: the row's `dueAt`.
        let expires: Date?
    }

    /// A captured link after this rule: a payment link loses its fragment
    /// everywhere it appears in `text` and hands the whole link back as
    /// `secret` for the Keychain; a request link keeps its text, gains a
    /// title and is dated by its expiry. nil when `url` is not zk.money's.
    /// A payment row's note is the caller's: it depends on whether the
    /// secret was kept (`paymentNote(kept:)`).
    static func capture(url: URL, text: String) -> Captured? {
        guard let link = link(url.absoluteString) else { return nil }
        switch link {
        case .payment:
            let clean = scrub(text)
            return Captured(content: clean.text, title: title(link), note: paymentNote(kept: false),
                            secret: clean.secrets.first ?? url.absoluteString, expires: nil)
        case .request(_, _, _, let note, let expires):
            // The requester's own words and the expiry are the row's body:
            // a title carries one seam (`title-seam-audit.py`).
            var lines: [String] = []
            if let note { lines.append("“\(note)”") }
            if let expires { lines.append("Asks until \(expires.formatted(.dateTime.month(.abbreviated).day()))") }
            let clean = scrub(text)
            return Captured(content: clean.text, title: title(link), note: lines.isEmpty ? nil : lines.joined(separator: "\n"),
                            secret: clean.secrets.first, expires: expires)
        case .shortRequest:
            let clean = scrub(text)
            return Captured(content: clean.text, title: title(link), note: nil, secret: clean.secrets.first, expires: nil)
        }
    }

    /// A payment row's body: where its secret is, or that it was not kept.
    static func paymentNote(kept: Bool) -> String {
 kept
            ? "The claim secret is kept on the device it was saved on, never synced: Claim in zk.money opens it there."
            : "The claim secret after the # was not kept: whoever holds it can take the money, and this library syncs to iCloud. Claim it from where it was sent to you."
    }
}

// MARK: - A short link's record (prd §1748)

extension ZkMoneyLink {
    /// Opens one record a short link's tag found on Aztec, as zk.money's own
    /// wallet does (`unpack`, measured 2026-11-11), or nil for anything that
    /// is not this link's: fifteen fields, each 31 bytes under a zero byte;
    /// twelve bytes of nonce, then AES-256-CTR under a key HKDF-SHA256 draws
    /// from the seed. Inside: the payload's length, an Ed25519 key whose
    /// hash's first sixteen bytes ARE the seed, its signature over the
    /// payload, the payload, zeros. So a record under the right tag written
    /// by anyone who did not hold the link's secret key opens to nothing.
    static func open(fields: [String], short: Short) -> [UInt8]? {
        guard fields.count == 15, short.seed.count == 16 else { return nil }
        var sealed: [UInt8] = []
        for field in fields {
            guard let bytes = fieldBytes(field), bytes[0] == 0 else { return nil }
            sealed += bytes[1...]
        }
        let nonce = Array(sealed[..<12]), cipher = Array(sealed[12...])
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(short.seed)),
                                         info: Data("zk.money link cipher".utf8) + [1, short.kind], outputByteCount: 32)
        guard let plain = aesCTR(cipher, key: key.withUnsafeBytes { [UInt8]($0) }, counter: nonce + [0, 0, 0, 0]),
              plain.count == 453 else { return nil }
        let length = Int(plain[0]) << 8 | Int(plain[1])
        guard length <= 355, plain[(98 + length)...].allSatisfy({ $0 == 0 }) else { return nil }
        let publicKey = Array(plain[2..<34]), signature = Array(plain[34..<98]), payload = Array(plain[98..<(98 + length)])
        guard Array(SHA256.hash(data: Data(publicKey)).prefix(16)) == short.seed,
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKey)),
              signer.isValidSignature(Data(signature), for: Data("zk.money link".utf8) + [1, short.kind] + payload) else { return nil }
        return payload
    }

    /// A field as its 32 bytes, from the node's 0x-hex.
    private static func fieldBytes(_ field: String) -> [UInt8]? {
        var hex = field.lowercased().hasPrefix("0x") ? String(field.dropFirst(2)) : field
        guard !hex.isEmpty, hex.count <= 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        hex = String(repeating: "0", count: 64 - hex.count) + hex
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

    /// AES-256 in counter mode, the counter a 16-byte big-endian block.
    private static func aesCTR(_ input: [UInt8], key: [UInt8], counter: [UInt8]) -> [UInt8]? {
        guard key.count == kCCKeySizeAES256, counter.count == kCCBlockSizeAES128 else { return nil }
        var cryptor: CCCryptorRef?
        guard CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                                      counter, key, key.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor) == kCCSuccess,
              let cryptor else { return nil }
        defer { CCCryptorRelease(cryptor) }
        var out = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        guard CCCryptorUpdate(cryptor, input, input.count, &out, out.count, &moved) == kCCSuccess, moved == input.count else { return nil }
        return out
    }
}

// MARK: - CBOR, the slice a request link uses

/// Just enough CBOR (RFC 8949) for a request link: unsigned ints, byte and
/// text strings, one map with integer keys, a tag around it and a whole
/// float64 — what cbor-x (the reference encoder) writes. Anything else is
/// refused, as the reference decoder refuses an unknown key.
enum CBOR: Equatable {
    case uint(UInt64)
    case bytes([UInt8])
    case text(String)
    case map([UInt64: CBOR])

    static func decode(_ bytes: [UInt8]) -> CBOR? {
        var i = 0
        guard let value = item(bytes, &i, depth: 0), i == bytes.count else { return nil }
        return value
    }

    private static func length(_ b: [UInt8], _ i: inout Int, _ info: UInt8) -> UInt64? {
        switch info {
        case 0...23: return UInt64(info)
        case 24, 25, 26, 27:
            let n = 1 << Int(info - 24)
            guard i + n <= b.count else { return nil }
            var v: UInt64 = 0
            for k in 0..<n { v = v << 8 | UInt64(b[i + k]) }
            i += n
            return v
        default: return nil
        }
    }

    private static func item(_ b: [UInt8], _ i: inout Int, depth: Int) -> CBOR? {
        guard i < b.count, depth < 4 else { return nil }
        let major = b[i] >> 5, info = b[i] & 0x1f
        i += 1
        guard let n = length(b, &i, info) else { return nil }
        switch major {
        case 0: return .uint(n)
        case 2, 3:
            guard n <= 4096, i + Int(n) <= b.count else { return nil }
            let slice = Array(b[i..<(i + Int(n))])
            i += Int(n)
            if major == 2 { return .bytes(slice) }
            return String(bytes: slice, encoding: .utf8).map(CBOR.text)
        case 6:
            // A tag wraps one item: cbor-x writes a `Map` as tag 259
            // ("map with any keys", measured), which reads as the map itself.
            return item(b, &i, depth: depth + 1)
        case 7 where info == 27:
            // cbor-x writes an integer past 2³² as a float64 (the expiry in
            // epoch ms, measured); read back only when it is whole.
            let d = Double(bitPattern: n)
            guard d >= 0, d < 1.8e19, d == d.rounded() else { return nil }
            return .uint(UInt64(d))
        case 5:
            guard n <= 32 else { return nil }
            var map: [UInt64: CBOR] = [:]
            for _ in 0..<n {
                guard case .uint(let key)? = item(b, &i, depth: depth + 1),
                      let value = item(b, &i, depth: depth + 1) else { return nil }
                map[key] = value
            }
            return .map(map)
        default: return nil
        }
    }
}
