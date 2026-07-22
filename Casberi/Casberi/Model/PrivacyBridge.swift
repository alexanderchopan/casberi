import Foundation

/// Privacy (2026-07-22) — Privacy.com virtual cards, read side only.
/// A personal API key (privacy.com account → API on a paid plan) reads your
/// card transactions over the `Authorization: api-key <key>` scheme against
/// `api.privacy.com/v1`: each approved purchase lands as a thing wearing its
/// merchant and amount. Nothing here ever creates, closes, or funds a card.
///
/// Honesty ceiling — the divergence from every other key bridge, stated so a
/// future edit can't quietly erase it: Privacy's API key is NOT scoped
/// read-only. The same key that lists transactions can also issue and close
/// cards and move money on the account. Every other keyed bridge here holds a
/// credential that CANNOT execute (Bitrefill/Bankr mint read-only keys, 1Claw
/// hands out grants, the wallet reads are keyless). Here the "can't spend"
/// promise is kept by CONDUCT, not by the credential: this file only ever
/// issues `GET /v1/transactions`, and the catalog/setup copy says so plainly.
/// Do not add a call to any write endpoint (`POST /v1/card`, `.../simulate/…`,
/// etc.) — that would make the Wallet-style "read-only" promise false.
///
/// UNMEASURED against the live API (2026-07-22): built from Privacy's public
/// developer docs (api.privacy.com/v1/transactions, `data` envelope, amounts
/// in integer cents, `merchant.descriptor`/`mcc`, `created` ISO8601). The org
/// egress policy blocked api.privacy.com from the build host, so the response
/// shape below is the documented one, not a measured one — run `-privacyProbe`
/// on a device/sim that can reach the host and reconcile before hardening.
enum PrivacyFetch {

    static let api = "https://api.privacy.com/v1"

    /// True for a transaction thing's ref — the classification a lede/feed
    /// filter would need, owned here beside the ref it mints.
    static func isTxnRef(_ ref: String?) -> Bool {
        ref?.hasPrefix("privacy:txn:") ?? false
    }

    /// Approved card transactions, newest first. Returns nil only when the
    /// read fails (no key / rejected key / network) — the honest
    /// token-rejected signal TokenIngest words as "check the token".
    static func things(token: String) async -> [Thing]? {
        // result=APPROVED: land real purchases, not blocked/declined attempts
        // (a decline may be worth surfacing later — held as a re-measure
        // question, not guessed at here). page_size caps the backfill.
        let url = "\(api)/transactions?result=APPROVED&page_size=50"
        guard let rows = await list(url, token: token) else { return nil }
        return rows.compactMap(txnThing)
    }

    /// A purchase: "Netflix.com · $12.99", dated when Privacy recorded it.
    /// The amount is the settled amount once known, else the authorization
    /// amount — both are integer CENTS in the card's (USD) currency. Privacy
    /// exposes no per-transaction permalink, so the row opens the Privacy
    /// dashboard where the transaction lives (re-measure item: confirm a
    /// deep-linkable transaction URL exists before promising one).
    private static func txnThing(_ txn: [String: Any]) -> Thing? {
        guard let id = txn["token"] as? String else { return nil }
        let merchant = txn["merchant"] as? [String: Any]
        let name = (merchant?["descriptor"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Privacy transaction"
        let cents = (txn["settled_amount"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            ?? (txn["amount"] as? Int) ?? 0
        let title = money(cents).map { "\(name) · \($0)" } ?? name
        return Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: "https://privacy.com/account",
            source: "Privacy",
            capturedAt: IngestSupport.isoDate(txn["created"]) ?? .now,
            sourceRef: "privacy:txn:\(id)"
        )
    }

    /// "$12.99" from integer cents, via the shared product formatter so a
    /// Privacy row reads a price exactly as a Bitrefill/Shopify row does.
    /// Privacy cards are USD; a merchant's own currency is a separate field
    /// (`merchant_currency`) we don't quote here — the card amount is what you
    /// were charged. Returns nil for a zero amount rather than "$0.00".
    private static func money(_ cents: Int) -> String? {
        guard cents > 0 else { return nil }
        return PriceFormat.string(Double(cents) / 100.0, currency: "USD")
    }

    /// The v1 list envelope — `{"data": […], "total_entries": …, "page": …}` —
    /// with a fallback for a bare array, so a wrapper change degrades to "no
    /// rows", never a crash. Mirrors BitrefillFetch.list.
    private static func list(_ url: String, token: String) async -> [[String: Any]]? {
        let root = await IngestSupport.getJSON(url, auth: "api-key \(token)")
        if let bare = root as? [[String: Any]] { return bare }
        return (root as? [String: Any])?["data"] as? [[String: Any]]
    }

    /// `-privacyProbe YES` — the measure tool for an UNMEASURED API. Connect
    /// first via `-tokenBridge "Privacy:<key>"`, then this reads the STORED key
    /// and NSLogs the RAW shape: the HTTP status (so 401 wrong-key, 404/410
    /// endpoint-gone, and 0 unreachable stay distinct), the envelope keys, the
    /// landed count, and the first transaction's fields (merchant descriptor,
    /// amount, status, created) so the documented shape can be reconciled with
    /// the live one before this bridge is trusted. Reads only — never a write.
    static func probe() async {
        guard let token = TokenVault.get(TokenBridge.privacy.tokenKey) else {
            NSLog("[Casberi] privacyProbe: no stored key (connect via -tokenBridge \"Privacy:<key>\")")
            return
        }
        let url = "\(api)/transactions?result=APPROVED&page_size=5"
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: "api-key \(token)")
        guard status == 200 else {
            NSLog("[Casberi] privacyProbe: HTTP %d (401 wrong key · 404/410 endpoint gone · 0 unreachable)", status)
            return
        }
        let root = json as? [String: Any]
        let rows = (json as? [[String: Any]]) ?? (root?["data"] as? [[String: Any]]) ?? []
        let envelope = root.map { Array($0.keys).sorted().joined(separator: ",") } ?? "bare-array"
        NSLog("[Casberi] privacyProbe: HTTP 200 · envelope={%@} · %d txns", envelope, rows.count)
        if let first = rows.first {
            let merchant = (first["merchant"] as? [String: Any])?["descriptor"] as? String ?? "—"
            NSLog("[Casberi] privacyProbe first → merchant=%@ amount=%@ settled=%@ status=%@ created=%@ fields={%@}",
                  merchant,
                  String(describing: first["amount"] ?? "nil"),
                  String(describing: first["settled_amount"] ?? "nil"),
                  String(describing: first["status"] ?? first["result"] ?? "nil"),
                  String(describing: first["created"] ?? "nil"),
                  Array(first.keys).sorted().joined(separator: ","))
        }
    }
}
