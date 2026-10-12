import Foundation

/// zFi's order boards on Ethereum, read (2026-10-12, prd §1281): the pure
/// half of `ZFiOrders`. Foundation only, so `zfi-selftest.sh` compiles it
/// whole against replies saved off mainnet.
///
/// zFi (github.com/z-fi/zFi) keeps three books of escrowed orders, each order
/// an ERC-721 receipt the board mints to whoever holds it:
/// • **Swapboard** — fixed-price orders, all-or-part, with an optional
///   expiry. v1 (`0x…ecbf`) is the closed all-or-nothing book; its open
///   orders still hold their escrow, so it is read too.
/// • **Dutchboard** — a lot whose price falls from a start to a floor over a
///   window, then rests at the floor.
/// • **Floorboard** — a standing bid whose price RISES over its window; when
///   the window closes the bid stops filling and its escrow waits.
///
/// Each board keeps the order's maker, seller or bidder IN STEP with the
/// receipt's owner while the order is live (Swapboard: "ownership IS
/// makership"; Dutchboard and Floorboard rewrite the field in
/// `_afterTokenTransfer`), and zeroes it when the order closes. So one read
/// per board, filtered on that field, finds every live order a wallet holds:
/// no `ownerOf`, no logs. MEASURED 2026-10-12: Swapboard 22 orders ever,
/// v1 144, Dutchboard 3, Floorboard 10.
///
/// The boards are read directly rather than through zFi's lenses
/// (`SwapboardView`, `FloorboardView`), because the lenses list only what a
/// taker could fill now: an expired order, a frozen lot or a closed bid
/// drops out of them, and those are exactly the ones whose escrow is waiting
/// for its owner to take it back.
enum ZFiWire {
    static let name = "zFi"

    // Canonical deployments, Etherscan-verified, code read on 2026-10-12.
    static let swapboard = "0x000000da7bb4b2a9e3e80e9a4d4157e26ca6189b"
    static let swapboardV1 = "0x000000ff3d7a2d373615141d7489ca66683dbecf"
    static let dutchboard = "0x000000a213b430d14bae6062c176289b05e04489"
    static let floorboard = "0x00000080198137f790da4c52bb902cf87c276748"

    static let nextOrderId = "0x2a58b330"     // Swapboard v1, v2
    static let nextId = "0x61b8ce8c"          // Dutchboard, Floorboard
    static let symbolCall = "0x95d89b41"
    static let decimalsCall = "0x313ce567"
    private static let getOrders = "03652027"   // getOrders(uint256[])
    private static let getListings = "c4b04518" // getListings(uint256,uint256)
    private static let getBids = "86514e26"     // getBids(uint256,uint256)

    /// The most ids one read asks for. Far above every book measured; a
    /// book past it is read in pages.
    static let page = 256

    static let ether = "0x0000000000000000000000000000000000000000"

    // MARK: - Calls

    static func word(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    /// `getOrders([from, …, to - 1])` on a Swapboard.
    static func ordersCall(from: Int, to: Int) -> String {
        let ids = Array(from..<max(from, to))
        return "0x" + getOrders + word(32) + word(ids.count) + ids.map(word).joined()
    }

    static func listingsCall(from: Int, to: Int) -> String { "0x" + getListings + word(from) + word(to) }
    static func bidsCall(from: Int, to: Int) -> String { "0x" + getBids + word(from) + word(to) }

    // MARK: - Words of a reply

    static func words(_ hex: String?) -> [Substring]? {
        guard let hex, hex.hasPrefix("0x") else { return nil }
        let body = hex.dropFirst(2)
        guard body.count % 64 == 0, body.allSatisfy(\.isHexDigit) else { return nil }
        var out: [Substring] = []
        var i = body.startIndex
        while i < body.endIndex {
            let j = body.index(i, offsetBy: 64)
            out.append(body[i..<j])
            i = j
        }
        return out
    }

    /// A word as a number — exact for every amount a person holds, and never
    /// a trap however large the word.
    static func uint(_ w: Substring) -> Double {
        w.reduce(0.0) { $0 * 16 + Double($1.hexDigitValue ?? 0) }
    }

    /// A word that must be a small number (an offset, a count, a time).
    /// Anything wider than 2^48 is not one: nil, never a trap.
    static func small(_ w: Substring) -> Int? {
        guard w.count == 64, w.prefix(52).allSatisfy({ $0 == "0" }) else { return nil }
        return Int(w.suffix(12), radix: 16)
    }

    static func address(_ w: Substring) -> String? {
        guard w.count == 64, w.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        return "0x" + w.suffix(40).lowercased()
    }

    static func flag(_ w: Substring) -> Bool { small(w).map { $0 != 0 } ?? false }

    static func count(reply hex: String?) -> Int? {
        guard let w = words(hex), w.count == 1 else { return nil }
        return small(w[0])
    }

    static func date(_ w: Substring) -> Date? {
        guard let t = small(w), t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    /// The tuples of a returned array, each `fields` words from its start.
    /// A static tuple (Swapboard's orders) sits inline; a dynamic one
    /// (Dutchboard's listings, Floorboard's bids — each carries an `ids`
    /// array) is reached through an offset. Any offset that is not a whole
    /// word, or points past the reply, ends the read with nothing.
    static func tuples(_ w: [Substring], fields: Int, dynamic: Bool) -> [ArraySlice<Substring>]? {
        guard let head = w.first.flatMap(small), head % 32 == 0 else { return nil }
        let base = head / 32
        guard base < w.count, let n = small(w[base]), n <= 4 * page else { return nil }
        var out: [ArraySlice<Substring>] = []
        for k in 0..<n {
            let start: Int
            if dynamic {
                guard base + 1 + k < w.count, let off = small(w[base + 1 + k]), off % 32 == 0 else { return nil }
                start = base + 1 + off / 32
            } else {
                start = base + 1 + k * fields
            }
            guard start + fields <= w.count else { return nil }
            out.append(w[start..<(start + fields)])
        }
        return out
    }

    // MARK: - Orders

    struct Order: Equatable, Sendable {
        enum Kind: String, Sendable { case sell, auction, bid }
        let kind: Kind
        let board: String
        let id: Int
        let holder: String
        /// What sits on the board in escrow — the holder's, to take back.
        let escrowToken: String
        let escrowRaw: Double
        let escrowIsNFT: Bool
        /// The other side: what a sell asks, or what a bid buys.
        let otherToken: String
        let otherRaw: Double
        let otherIsNFT: Bool
        /// An auction's ask or a bid's offer for the size still open, at the
        /// block read, and where its curve ends. Quote units, raw.
        var now: Double? = nil
        var last: Double? = nil
        var starts: Date? = nil
        var curveEnds: Date? = nil
        /// When it stops filling: a Swapboard order's expiry, a lot's expiry,
        /// a bid's closed window. nil = never.
        var expiry: Date? = nil
        /// The board's own answer to "would a fill succeed at the block read"
        /// (Dutchboard, Floorboard); nil for Swapboard, decided by `expiry`.
        var takeable: Bool? = nil

        var key: String { "\(board):\(id)" }
    }

    /// Swapboard v2's live orders held by `holders`. An order is live while
    /// `active`; an expired one still holds its escrow until cancelled, so it
    /// is kept — its row says so.
    static func swapOrders(reply hex: String?, firstID: Int, holders: Set<String>) -> [Order]? {
        guard let w = words(hex), let rows = tuples(w, fields: 11, dynamic: false) else { return nil }
        var out: [Order] = []
        for (i, f) in rows.enumerated() {
            let f = Array(f)
            guard flag(f[1]), let maker = address(f[0]), holders.contains(maker),
                  let tokenA = address(f[7]), let tokenB = address(f[9]) else { continue }
            let nftA = flag(f[4]), nftB = flag(f[5])
            out.append(Order(kind: .sell, board: swapboard, id: firstID + i, holder: maker,
                             escrowToken: tokenA, escrowRaw: nftA ? 1 : uint(f[8]), escrowIsNFT: nftA,
                             otherToken: tokenB, otherRaw: nftB ? 1 : uint(f[10]), otherIsNFT: nftB,
                             expiry: date(f[3])))
        }
        return out
    }

    /// Swapboard v1's open orders held by `holders`: six fields, no NFTs, no
    /// expiry, all-or-nothing.
    static func swapOrdersV1(reply hex: String?, firstID: Int, holders: Set<String>) -> [Order]? {
        guard let w = words(hex), let rows = tuples(w, fields: 6, dynamic: false) else { return nil }
        var out: [Order] = []
        for (i, f) in rows.enumerated() {
            let f = Array(f)
            guard flag(f[1]), let maker = address(f[0]), holders.contains(maker),
                  let tokenA = address(f[2]), let tokenB = address(f[4]) else { continue }
            out.append(Order(kind: .sell, board: swapboardV1, id: firstID + i, holder: maker,
                             escrowToken: tokenA, escrowRaw: uint(f[3]), escrowIsNFT: false,
                             otherToken: tokenB, otherRaw: uint(f[5]), otherIsNFT: false))
        }
        return out
    }

    /// Dutchboard's live lots held by `holders` (`seller` is zero once a lot
    /// closes). The ask scales the board's price for the full lot down to
    /// what is left, rounding up as the board charges.
    static func auctions(reply hex: String?, holders: Set<String>) -> [Order]? {
        guard let w = words(hex), let rows = tuples(w, fields: 15, dynamic: true) else { return nil }
        var out: [Order] = []
        for f in rows.map(Array.init) {
            guard let id = small(f[0]), let seller = address(f[1]), seller != ether, holders.contains(seller),
                  let token = address(f[2]), let quote = address(f[3]) else { continue }
            let nft = flag(f[4])
            let initial = uint(f[9]), remaining = uint(f[10])
            guard nft || (initial > 0 && remaining > 0) else { continue }
            let share = nft ? 1 : remaining / initial
            let start = date(f[5])
            var o = Order(kind: .auction, board: dutchboard, id: id, holder: seller,
                          escrowToken: token, escrowRaw: nft ? 1 : remaining, escrowIsNFT: nft,
                          otherToken: quote, otherRaw: uint(f[13]) * share, otherIsNFT: false)
            o.now = (uint(f[13]) * share).rounded(.up)
            o.last = uint(f[8]) * share
            o.starts = start
            o.curveEnds = start.flatMap { s in small(f[6]).map { s.addingTimeInterval(TimeInterval($0)) } }
            o.expiry = date(f[11])
            o.takeable = flag(f[14])
            out.append(o)
        }
        return out
    }

    /// Floorboard's live bids held by `holders` (`bidder` is zero once a bid
    /// closes). The escrow is `locked`, in the quote; the offer scales the
    /// board's price for the full size down to what is still wanted.
    static func bids(reply hex: String?, holders: Set<String>) -> [Order]? {
        guard let w = words(hex), let rows = tuples(w, fields: 15, dynamic: true) else { return nil }
        var out: [Order] = []
        for f in rows.map(Array.init) {
            guard let id = small(f[0]), let bidder = address(f[1]), bidder != ether, holders.contains(bidder),
                  let token = address(f[2]), let quote = address(f[3]) else { continue }
            let locked = uint(f[9])
            guard locked > 0 else { continue }
            let initial = uint(f[10]), remaining = uint(f[11])
            let share = initial > 0 ? remaining / initial : 1
            let start = date(f[5])
            let window = small(f[6])
            var o = Order(kind: .bid, board: floorboard, id: id, holder: bidder,
                          escrowToken: quote, escrowRaw: locked, escrowIsNFT: false,
                          otherToken: token, otherRaw: remaining, otherIsNFT: flag(f[4]))
            o.now = uint(f[13]) * share
            o.last = uint(f[8]) * share
            o.starts = start
            o.curveEnds = start.flatMap { s in window.map { s.addingTimeInterval(TimeInterval($0)) } }
            o.expiry = o.curveEnds
            o.takeable = flag(f[14])
            out.append(o)
        }
        return out
    }

    // MARK: - Tokens

    struct Token: Equatable, Sendable {
        let symbol: String
        /// nil for an NFT collection (no `decimals()`), or a token whose
        /// decimals have not been read: its amounts are not drawn.
        let decimals: Int?
    }

    static let etherToken = Token(symbol: "ETH", decimals: 18)

    /// A token's `symbol()` — an ABI string, or the bytes32 some old tokens
    /// return (MKR). A symbol is drawn on a row, so only a short, plain one is
    /// believed: anything else is nil and the row names the address.
    static func symbol(reply hex: String?) -> String? {
        guard let w = words(hex), !w.isEmpty else { return nil }
        var bytes: [UInt8]
        if w.count >= 3, let off = small(w[0]), off == 32, let n = small(w[1]), n > 0, n <= 32 {
            bytes = hexBytes(w[2]).prefix(n).map { $0 }
        } else if w.count == 1 {
            bytes = hexBytes(w[0])
            while bytes.last == 0 { bytes.removeLast() }
        } else {
            return nil
        }
        guard !bytes.isEmpty, bytes.count <= 11,
              let s = String(bytes: bytes, encoding: .ascii),
              s.allSatisfy({ $0.isLetter || $0.isNumber || "._-+$".contains($0) }) else { return nil }
        return s
    }

    static func decimals(reply hex: String?) -> Int? {
        count(reply: hex).flatMap { $0 <= 36 ? $0 : nil }
    }

    private static func hexBytes(_ w: Substring) -> [UInt8] {
        var out: [UInt8] = []
        var i = w.startIndex
        while i < w.endIndex {
            let j = w.index(i, offsetBy: 2)
            out.append(UInt8(w[i..<j], radix: 16) ?? 0)
            i = j
        }
        return out
    }

    // MARK: - Words on the row

    static func shortAddress(_ a: String) -> String { "…" + a.suffix(4) }

    static func symbol(_ token: String, _ tokens: [String: Token]) -> String {
        token == ether ? etherToken.symbol : tokens[token]?.symbol ?? shortAddress(token)
    }

    /// An amount in a token's own units: four significant digits under one,
    /// two places above it.
    static func amount(_ raw: Double, _ token: String, _ tokens: [String: Token], isNFT: Bool = false) -> Double? {
        if isNFT { return raw }
        guard let decimals = token == ether ? 18 : tokens[token]?.decimals else { return nil }
        return raw / pow(10, Double(decimals))
    }

    static func plain(_ value: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "en_US"))
        return value != 0 && abs(value) < 1
            ? value.formatted(style.precision(.significantDigits(1...4)))
            : value.formatted(style.precision(.fractionLength(0...2)))
    }

    static func phrase(_ raw: Double?, _ token: String, _ tokens: [String: Token], isNFT: Bool = false) -> String? {
        guard let raw, let v = amount(raw, token, tokens, isNFT: isNFT) else { return nil }
        return "\(plain(v)) \(symbol(token, tokens))"
    }

    static func title(_ o: Order, _ tokens: [String: Token]) -> String {
        let escrow = symbol(o.escrowToken, tokens), other = symbol(o.otherToken, tokens)
        switch o.kind {
        case .sell:
            return o.escrowIsNFT ? String(localized: "Sell \(escrow) #\(o.id) for \(other)")
                                 : String(localized: "Sell \(escrow) for \(other)")
        case .auction:
            return String(localized: "Auction \(escrow) for \(other)")
        case .bid:
            let n = phrase(o.otherRaw, o.otherToken, tokens, isNFT: o.otherIsNFT) ?? other
            return String(localized: "Bid for \(n)")
        }
    }

    /// Whether the order has stopped filling with its escrow still on the
    /// board — money waiting for the holder to take it back.
    static func needsYou(_ o: Order, now: Date = .now) -> Bool {
        switch o.kind {
        case .sell:
            return o.expiry.map { $0 < now } ?? false
        case .auction, .bid:
            guard o.takeable == false else { return false }
            if let s = o.starts, s > now { return false }
            return o.kind == .bid || (o.expiry.map { $0 < now } ?? false)
        }
    }

    /// The row's line: where the order stands, in the board's own terms.
    static func state(_ o: Order, _ tokens: [String: Token], now: Date = .now) -> String {
        let back = String(localized: "cancel to reclaim")
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        switch o.kind {
        case .sell:
            if needsYou(o, now: now) { return String(localized: "Expired") + " · " + back }
            let ask = phrase(o.otherRaw, o.otherToken, tokens, isNFT: o.otherIsNFT)
            return ask.map { String(localized: "Open · asks \($0)") } ?? String(localized: "Open")
        case .auction, .bid:
            if let s = o.starts, s > now { return String(localized: "Starts \(s.formatted(short))") }
            if needsYou(o, now: now) {
                return (o.kind == .bid ? String(localized: "Closed") : String(localized: "Expired")) + " · " + back
            }
            guard o.takeable == true else { return String(localized: "Paused") }
            // The price is in the quote: what an auction is paid in, what a
            // bid pays with (its escrow).
            let quote = o.kind == .bid ? o.escrowToken : o.otherToken
            let current = phrase(o.now, quote, tokens), end = phrase(o.last, quote, tokens)
            // One line on the row, so the curve's end date is left to the
            // board's own page.
            if let e = o.curveEnds, e > now, let current, let end {
                return o.kind == .bid
                    ? String(localized: "Rising · now \(current), up to \(end)")
                    : String(localized: "Falling · now \(current), floor \(end)")
            }
            if let end {
                return o.kind == .bid ? String(localized: "Open · bids \(end)") : String(localized: "At its floor · \(end)")
            }
            return String(localized: "Open")
        }
    }
}
