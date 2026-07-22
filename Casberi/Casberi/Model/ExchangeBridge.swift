import Foundation
import CryptoKit

/// Read-only exchange balances (2026-07-21, prd §163).
///
/// The blind spot this closes: most people's crypto is not all onchain. A
/// portfolio built only from watched addresses is quietly wrong for anyone
/// whose main holding sits on an exchange, and §155 already ruled that the
/// combined read IS what the wallet room is — so an exchange balance merges
/// into the same total and the same treemap, wearing its venue the way a
/// wallet wears its face.
///
/// **What the permission check is for — and what it is NOT for** (corrected
/// 2026-07-21, user: "how would someone be able to trade, we don't even have a
/// wallet"). An earlier version of this comment claimed the wallet room's
/// "watching can never trade or move funds" promise came to rest on the key's
/// scope. That was wrong, and worth recording so it isn't re-argued. The
/// promise holds for the reason it always did: the app has NO capability to
/// trade. There is no signing path anywhere in it — no `personal_sign`, no
/// `eth_sendTransaction`, and WalletConnect proposes `methods: []` — and no
/// order, withdrawal or transfer endpoint is reachable from this file. Adding
/// a key does not change any of that.
///
/// The check earns its place for a narrower and less dramatic reason: **blast
/// radius**. An API key is a bearer credential — whoever holds it can use it,
/// whatever this app's code does. A key that can withdraw turns a keychain
/// leak, a bad backup or a compromised device from a privacy problem into a
/// funds-loss one. Refusing it means Casberi never holds more power than the
/// feature needs. It also catches the likelier case by far: people reuse the
/// key they already made, and that key usually has trading on, because trading
/// is what they made it for.
///
/// The gate **fails closed**, which is the part that makes it worth anything:
/// an unreachable check, an unparseable answer, or a permission string we do
/// not recognise all mean REFUSE. Deny-by-unknown specifically — an allowlist
/// that ignored unknown values would silently admit whatever permission the
/// exchange adds next.
///
/// Nothing here can place an order even if a key somehow got through: no
/// order, withdrawal or transfer endpoint is reachable from this file.
enum ExchangeBridge {

    enum Venue: String, CaseIterable {
        case kraken, coinbase
        var display: String { self == .kraken ? "Kraken" : "Coinbase" }
        /// Where the person's key is stored (TokenVault, Keychain-backed).
        var vaultKey: String { "exchange.\(rawValue)" }
    }

    /// One balance, in the neutral shape `WalletPortfolio` merges.
    struct Holding {
        let symbol: String
        let amount: Double
        let venue: Venue
    }

    /// What asking the exchange about a key returned. There is deliberately no
    /// `.probablyFine` — a key is admitted only when the venue affirmatively
    /// said it cannot trade or move funds.
    enum KeyVerdict: Equatable {
        /// Verified: the key holds only permissions we recognise as read-only.
        case readOnly
        /// Verified, and it can do more than read — the offending permissions,
        /// named, so the setup screen can say WHICH box to untick.
        case tooPowerful([String])
        /// Could not verify. Refused, with the reason to show.
        case unverifiable(String)
    }

    // MARK: - Kraken

    /// The permissions a purely-reading key may hold. Everything else — and
    /// anything not on this list at all — disqualifies.
    ///
    /// Note `create-ws-token` is deliberately ABSENT despite sounding passive:
    /// a WebSocket token inherits the key's own rights, so admitting it would
    /// move the trading question somewhere this file cannot see.
    ///
    /// Deposit/withdraw HISTORY is read through `query-ledger`, never through
    /// the Deposit/Withdraw permissions — on Kraken those same permissions gate
    /// the transfers themselves, so telling someone to enable "Withdraw Funds"
    /// just to see their history would hand over the exact power this checks
    /// for (measured against Kraken's permission→endpoint mapping).
    static let krakenReadOnlyPermissions: Set<String> = [
        "query-funds", "query-open-trades", "query-closed-trades",
        "query-ledger", "export-data",
    ]

    /// Kraken's `API-Sign`: base64( HMAC-SHA512( uriPath ‖ SHA256(nonce ‖ body),
    /// base64-decoded secret ) ).
    ///
    /// Pure and separately testable on purpose — it is asserted against
    /// Kraken's own published worked example, so a refactor that breaks the
    /// byte order fails loudly instead of turning into an "Invalid signature"
    /// mystery at connect time.
    ///
    /// `body` must be the EXACT string sent as the request body. Rebuilding it
    /// from a dictionary is the classic way this drifts: re-encoding can reorder
    /// fields or renormalise numbers, and the signature then covers bytes the
    /// server never saw.
    static func krakenSignature(path: String, nonce: String, body: String,
                                secret: String) -> String? {
        guard let secretData = Data(base64Encoded: secret),
              let pathData = path.data(using: .utf8),
              let payload = (nonce + body).data(using: .utf8)
        else { return nil }
        let inner = Data(SHA256.hash(data: payload))          // raw digest, never hex
        let mac = HMAC<SHA512>.authenticationCode(for: pathData + inner,
                                                  using: SymmetricKey(data: secretData))
        return Data(mac).base64EncodedString()
    }

    /// A monotonically increasing nonce. Milliseconds since epoch, Kraken's own
    /// recommendation — and `UInt64` because a `Double` loses integer precision
    /// above 2^53 and a repeated nonce is rejected.
    private static func nonce() -> String {
        String(UInt64(Date().timeIntervalSince1970 * 1000))
    }

    private static func krakenPost(_ path: String, key: String, secret: String,
                                   fields: [String: String] = [:]) async -> [String: Any]? {
        let n = nonce()
        // Built ONCE and both signed and sent — see `krakenSignature`.
        var body = "nonce=\(n)"
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) { body += "&\(k)=\(v)" }
        guard let signature = krakenSignature(path: path, nonce: n, body: body, secret: secret),
              let url = URL(string: "https://api.kraken.com" + path)
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }

    /// Asks Kraken what the key may do. `GetApiKeyInfo` itself requires NO
    /// permissions (documented), so this works on the most restricted key a
    /// person can make — which is what lets the check run BEFORE any read.
    static func verifyKraken(key: String, secret: String) async -> KeyVerdict {
        guard let root = await krakenPost("/0/private/GetApiKeyInfo", key: key, secret: secret)
        else { return .unverifiable(String(localized: "Couldn't reach Kraken to check this key.")) }
        if let errors = root["error"] as? [String], !errors.isEmpty {
            // Includes the case where Kraken doesn't know this endpoint —
            // it was added 2026-03-11, so an older-than-expected deployment
            // must refuse rather than assume.
            return .unverifiable(String(localized: "Kraken rejected the key check: \(errors.joined(separator: ", "))"))
        }
        guard let result = root["result"] as? [String: Any],
              let permissions = result["permissions"] as? [String] else {
            return .unverifiable(String(localized: "Kraken didn't say what this key can do."))
        }
        let disqualifying = permissions.filter { !krakenReadOnlyPermissions.contains($0) }
        return disqualifying.isEmpty ? .readOnly : .tooPowerful(disqualifying.sorted())
    }

    /// Balances, once the key has been verified. Never called with an
    /// unverified key — `connect` gates on the verdict.
    static func krakenBalances(key: String, secret: String) async -> [Holding]? {
        guard let root = await krakenPost("/0/private/Balance", key: key, secret: secret),
              (root["error"] as? [String])?.isEmpty ?? true,
              let result = root["result"] as? [String: Any] else { return nil }
        return result.compactMap { symbol, raw in
            // Kraken returns amounts as STRINGS, and its own asset codes
            // ("XXBT", "ZUSD") carry a legacy class prefix the rest of the app
            // has never heard of.
            guard let amount = Double((raw as? String) ?? ""), amount > 0 else { return nil }
            return Holding(symbol: normalizeKrakenAsset(symbol), amount: amount, venue: .kraken)
        }
    }

    /// Kraken's legacy asset codes → the symbols every other surface uses. The
    /// `X`/`Z` prefixes are its own ISO-4217-style classing (X = crypto, Z =
    /// fiat) and appear on the older listings only, so the prefix is stripped
    /// only where doing so leaves a symbol we'd recognise — blindly dropping a
    /// leading X would turn XCN and XTZ into CN and TZ.
    static func normalizeKrakenAsset(_ raw: String) -> String {
        let known = ["XXBT": "BTC", "XBT": "BTC", "XETH": "ETH", "XXRP": "XRP",
                     "XLTC": "LTC", "XXLM": "XLM", "XXMR": "XMR", "XZEC": "ZEC",
                     "XDG": "DOGE", "XXDG": "DOGE",
                     "ZUSD": "USD", "ZEUR": "EUR", "ZGBP": "GBP", "ZJPY": "JPY",
                     "ZCAD": "CAD", "ZAUD": "AUD"]
        if let mapped = known[raw] { return mapped }
        // Staked/earning variants are the same asset to a portfolio ("ETH.S",
        // "DOT.S", "USDC.M") — the suffix says where it sits, not what it is.
        if let dot = raw.firstIndex(of: ".") {
            return normalizeKrakenAsset(String(raw[raw.startIndex..<dot]))
        }
        return raw
    }

    // MARK: - Coinbase

    /// Coinbase reports its powers separately. Only the two that can MOVE money
    /// out disqualify: trade and transfer.
    ///
    /// `can_receive` was disqualifying here at first, on the reasoning that it
    /// is "a funds-movement right". That reasoning doesn't survive the
    /// blast-radius test above: receiving is inbound, so it cannot lose anyone
    /// money, and refusing it buys nothing. It could easily COST something — if
    /// Coinbase sets that bit on ordinary view keys, the gate would reject
    /// perfectly safe keys and the failure would be undiagnosable from the
    /// setup screen. Held to the rule that a check must refuse a real power, not
    /// merely a named one.
    static func verifyCoinbase(keyName: String, privateKey: String) async -> KeyVerdict {
        guard let jwt = coinbaseJWT(keyName: keyName, privateKey: privateKey,
                                    method: "GET", path: "/api/v3/brokerage/key_permissions")
        else { return .unverifiable(String(localized: "That doesn't look like a Coinbase API key.")) }
        guard let url = URL(string: "https://api.coinbase.com/api/v3/brokerage/key_permissions")
        else { return .unverifiable(String(localized: "Couldn't reach Coinbase to check this key.")) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unverifiable(String(localized: "Couldn't reach Coinbase to check this key.")) }
        guard let canView = root["can_view"] as? Bool else {
            return .unverifiable(String(localized: "Coinbase didn't say what this key can do."))
        }
        var disqualifying: [String] = []
        if root["can_trade"] as? Bool == true { disqualifying.append("trade") }
        if root["can_transfer"] as? Bool == true { disqualifying.append("transfer") }
        if !disqualifying.isEmpty { return .tooPowerful(disqualifying) }
        return canView ? .readOnly
                       : .unverifiable(String(localized: "That key can't read anything — give it View access."))
    }

    /// A CDP JWT: ES256 over the request, valid two minutes. Coinbase expired
    /// the old HMAC keys in February 2025, so this is the only scheme the
    /// consumer/Advanced Trade surface accepts.
    ///
    /// The `uri` claim binds the token to ONE method and path, which is why it
    /// is built per request rather than cached.
    static func coinbaseJWT(keyName: String, privateKey: String,
                            method: String, path: String,
                            now: Date = .now, nonceHex: String? = nil) -> String? {
        guard let signingKey = try? P256.Signing.PrivateKey(pemRepresentation: privateKey)
        else { return nil }
        let issued = Int(now.timeIntervalSince1970)
        let header: [String: Any] = [
            "alg": "ES256", "kid": keyName, "typ": "JWT",
            "nonce": nonceHex ?? String(UInt64.random(in: .min ... .max), radix: 16),
        ]
        let claims: [String: Any] = [
            "sub": keyName, "iss": "cdp", "nbf": issued, "exp": issued + 120,
            "uri": "\(method) api.coinbase.com\(path)",
        ]
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let claimsData = try? JSONSerialization.data(withJSONObject: claims)
        else { return nil }
        let signingInput = base64URL(headerData) + "." + base64URL(claimsData)
        guard let inputData = signingInput.data(using: .utf8),
              let signature = try? signingKey.signature(for: inputData)
        else { return nil }
        // JOSE wants the raw r‖s pair, NOT the DER encoding `derRepresentation`
        // would hand back — a DER signature is a valid ECDSA signature that
        // every JWT verifier rejects.
        return signingInput + "." + base64URL(signature.rawRepresentation)
    }

    static func coinbaseBalances(keyName: String, privateKey: String) async -> [Holding]? {
        let path = "/api/v3/brokerage/accounts"
        guard let jwt = coinbaseJWT(keyName: keyName, privateKey: privateKey,
                                    method: "GET", path: path),
              let url = URL(string: "https://api.coinbase.com" + path)
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = root["accounts"] as? [[String: Any]] else { return nil }
        return accounts.compactMap { account in
            guard let balance = account["available_balance"] as? [String: Any],
                  let symbol = balance["currency"] as? String,
                  let amount = Double((balance["value"] as? String) ?? ""), amount > 0
            else { return nil }
            return Holding(symbol: symbol, amount: amount, venue: .coinbase)
        }
    }

    /// JWT's base64url: standard base64 with the two URL-unsafe characters
    /// swapped and the padding dropped.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Pricing

    /// USD for a set of symbols, from Kraken's KEYLESS public ticker — one
    /// request for every symbol, no account, and it prices BOTH venues (a
    /// balance is the same asset wherever it sits).
    ///
    /// The price is the **bid/ask midpoint**, never `c` (last trade). §83 is
    /// explicit: a last trade can be stale and quoting it is the dishonest
    /// read; the live book's own bracket is the honest one. A book missing
    /// either side prices nothing rather than half of something — the same
    /// empty-bracket rule that ruling already records.
    ///
    /// **Keyed off the ANSWER, not the request** (measured 2026-07-21): asking
    /// for `ETHUSD` returns a result keyed `XETHZUSD`, and `XBTUSD` returns
    /// `XXBTZUSD` — Kraken answers in its own canonical pair names. Reading the
    /// response by the string we asked with finds nothing at all. This is the
    /// same lesson `WalletIngest` records for Jupiter's token search.
    /// Two keyless requests, deliberately: `AssetPairs` says which asset each
    /// returned pair is FOR, and `Ticker` says what it costs.
    ///
    /// The second request is not laziness — it is the fix for a bug this code
    /// had twice. Splitting the pair NAME to recover the base looks trivial and
    /// cannot be made correct: "XTZUSD" is Tezos, whose symbol ends in Z, so
    /// stripping the `ZUSD` quote yields "XT"; and "USDTZUSD" is USDT with a
    /// `ZUSD` quote and no `X` prefix, defeating the refinement that fixed
    /// Tezos. Measured against `AssetPairs`, "SOLUSD" ALSO has quote `ZUSD` —
    /// the name simply doesn't encode the boundary. Kraken declares `base`
    /// itself, so the answer is asked for rather than parsed.
    static func krakenPrices(symbols: Set<String>) async -> [String: Double] {
        // USD is already USD; asking would be a pair that doesn't exist.
        let wanted = symbols.filter { $0 != "USD" }
        guard !wanted.isEmpty else { return [:] }
        // Kraken wants XBT in a pair name even though it answers XXBT.
        let pairs = wanted.map { ($0 == "BTC" ? "XBT" : $0) + "USD" }
            .sorted().joined(separator: ",")
        async let basesCall = krakenResult("AssetPairs", pairs: pairs)
        async let tickerCall = krakenResult("Ticker", pairs: pairs)
        let (bases, ticker) = await (basesCall, tickerCall)
        guard let bases, let ticker else { return [:] }

        var out: [String: Double] = [:]
        for (returnedPair, raw) in ticker {
            guard let quote = raw as? [String: Any],
                  let base = ((bases[returnedPair] as? [String: Any])?["base"]) as? String,
                  let ask = Double(((quote["a"] as? [Any])?.first as? String) ?? ""),
                  let bid = Double(((quote["b"] as? [Any])?.first as? String) ?? ""),
                  ask > 0, bid > 0 else { continue }
            out[normalizeKrakenAsset(base)] = (ask + bid) / 2
        }
        return out
    }

    private static func krakenResult(_ endpoint: String, pairs: String) async -> [String: Any]? {
        guard let url = URL(string: "https://api.kraken.com/0/public/\(endpoint)?pair=\(pairs)"),
              let root = await IngestSupport.getJSON(url) as? [String: Any]
        else { return nil }
        return root["result"] as? [String: Any]
    }

    /// Every connected venue's balances, priced. A holding the book can't
    /// price is DROPPED rather than counted at zero — a zero would quietly
    /// shrink the combined total and make the treemap lie about shares.
    static func pricedBalances() async -> [(symbol: String, usd: Double, venue: Venue)] {
        let held = await allBalances()
        guard !held.isEmpty else { return [] }
        let prices = await krakenPrices(symbols: Set(held.map(\.symbol)))
        return held.compactMap { holding in
            // A fiat balance is its own value; everything else needs a book.
            let unit = holding.symbol == "USD" ? 1 : prices[holding.symbol]
            guard let unit, unit > 0 else { return nil }
            return (holding.symbol, holding.amount * unit, holding.venue)
        }
    }

    // MARK: - Connect

    /// Verifies first, stores only on `.readOnly`. The order is the whole
    /// design: a key that can trade is never written to the vault at all, so
    /// there is no window in which one exists on the device.
    @MainActor
    static func connect(_ venue: Venue, key: String, secret: String) async -> KeyVerdict {
        let verdict: KeyVerdict
        switch venue {
        case .kraken:   verdict = await verifyKraken(key: key, secret: secret)
        case .coinbase: verdict = await verifyCoinbase(keyName: key, privateKey: secret)
        }
        if verdict == .readOnly {
            TokenVault.set("\(key)\n\(secret)", for: venue.vaultKey)
        }
        return verdict
    }

    /// The stored credential pair, or nil when that venue isn't connected.
    static func credentials(_ venue: Venue) -> (key: String, secret: String)? {
        guard let stored = TokenVault.get(venue.vaultKey) else { return nil }
        // The secret is a PEM for Coinbase and therefore multi-line — so only
        // the FIRST newline separates the pair.
        guard let split = stored.firstIndex(of: "\n") else { return nil }
        return (String(stored[stored.startIndex..<split]),
                String(stored[stored.index(after: split)...]))
    }

    /// Every connected venue's balances, for `WalletPortfolio` to merge.
    static func allBalances() async -> [Holding] {
        var out: [Holding] = []
        for venue in Venue.allCases {
            guard let (key, secret) = credentials(venue) else { continue }
            let held: [Holding]?
            switch venue {
            case .kraken:   held = await krakenBalances(key: key, secret: secret)
            case .coinbase: held = await coinbaseBalances(keyName: key, privateKey: secret)
            }
            out.append(contentsOf: held ?? [])
        }
        return out
    }
}
