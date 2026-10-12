import Foundation

/// A zk.money link, read without fetching it (2026-10-11). Shared: the app's
/// paste and the share extension both capture links, and BOTH must apply the
/// one rule this exists for:
///
/// - **A payment link** (`…/link#…`, `…/claim#…`) HOLDS funds: everything
///   after the `#` is the claim secret, and whoever has it can take the
///   money. It is a bearer credential, so it is never kept — the row keeps
///   the bare URL and says the secret was not kept. A library row syncs to
///   iCloud and lives in Spotlight; a secret there is a secret everywhere.
/// - **A request link** (`…/request#<fragment>`) asks for money and holds
///   none: base64url CBOR (front-core `requestInlineCodec.ts`) naming the
///   tag, amount, token, note and expiry, which titles the row.
enum ZkMoneyLink {

    static func display(_ tag: String) -> String { "\(tag).zk.money" }


    /// A zk.money link, read without fetching it.
    enum Link: Equatable {
        /// Asks for money; holds none. Every field the sender chose to show.
        case request(tag: String, amount: Decimal?, symbol: String?, note: String?, expires: Date?)
        /// Holds money: its fragment is the claim secret. `kept` is the URL
        /// with the fragment REMOVED — the only form ever stored.
        case payment(kept: String)
    }

    static func isZkMoneyHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "zk.money" || host.hasSuffix(".zk.money")
    }

    static func link(_ raw: String) -> Link? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              isZkMoneyHost(url.host), let fragment = url.fragment, !fragment.isEmpty else { return nil }
        let path = url.path.lowercased()
        if path.hasSuffix("/link") || path.hasSuffix("/claim") {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.fragment = nil
            return .payment(kept: parts?.string ?? "https://\(url.host ?? "zk.money")\(url.path)")
        }
        guard path.hasSuffix("/request"), let packet = requestPacket(fragment) else { return nil }
        return packet
    }

    /// The request codec's fields, by integer key (front-core
    /// `requestInlineCodec.ts`, formats 1–3): 3 tag, 4 amount (big-endian
    /// bytes), 5 symbol, 6 note, 7 expiry (epoch ms), 9 decimals.
    static func requestPacket(_ fragment: String) -> Link? {
        guard fragment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var b64 = fragment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), data.count <= 2048,
              case .map(let map)? = CBOR.decode([UInt8](data)),
              case .uint(let format)? = map[1], (1...3).contains(format),
              case .text(let tag)? = map[3] else { return nil }
        var amount: Decimal?
        if case .bytes(let raw)? = map[4] {
            var value = Decimal(0)
            for byte in raw { value = value * 256 + Decimal(byte) }
            if value > 0 {
                var decimals = 18
                if case .uint(let d)? = map[9] { decimals = Int(d) }
                amount = value / pow(10, decimals)
            }
        }
        var symbol: String?
        if case .text(let s)? = map[5] { symbol = s }
        var note: String?
        if case .text(let n)? = map[6], !n.isEmpty { note = n }
        var expires: Date?
        if case .uint(let ms)? = map[7] { expires = Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
        return .request(tag: tag.lowercased(), amount: amount, symbol: symbol, note: note, expires: expires)
    }

    /// A kept link's title.
    static func title(_ link: Link) -> String {
        switch link {
        case .payment:
            return "zk.money payment link"
        case .request(let tag, let amount, let symbol, _, _):
            let what = amount.map { "\(plain($0)) \(symbol ?? "")".trimmingCharacters(in: .whitespaces) }
            return "Payment request — " + (what.map { "\($0) to " } ?? "to ") + display(tag)
        }
    }

    static func plain(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }


    /// A captured link's (content, title, note) after this rule: a payment
    /// link loses its fragment everywhere it appears in `text`, and its note
    /// (the row's body) says so; a request link keeps its text and gains a
    /// title. nil when `url` is not zk.money's.
    static func capture(url: URL, text: String) -> (content: String, title: String, note: String?)? {
        guard let link = link(url.absoluteString) else { return nil }
        switch link {
        case .payment(let kept):
            return (text.replacingOccurrences(of: url.absoluteString, with: kept), title(link), paymentNote)
        case .request(_, _, _, let note, let expires):
            // The requester's own words and the expiry are the row's body:
            // a title carries one seam (`title-seam-audit.py`).
            var lines: [String] = []
            if let note { lines.append("“\(note)”") }
            if let expires { lines.append("Asks until \(expires.formatted(.dateTime.month(.abbreviated).day()))") }
            return (text, title(link), lines.isEmpty ? nil : lines.joined(separator: "\n"))
        }
    }

    /// Why a saved payment link cannot be opened from here.
    static let paymentNote = "The claim secret after the # was not kept: whoever holds it can take the money, and this library syncs to iCloud. Claim it from where it was sent to you."
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
