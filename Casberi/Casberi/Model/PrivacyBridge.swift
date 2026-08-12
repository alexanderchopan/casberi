import Foundation
import SwiftData

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
    ///
    /// Repairs already-landed rows on the way past (see `repairLanded`) — the
    /// shared `TokenIngest.insert` skips a ref it has already seen, so this is
    /// the only point in the pass where a stored Privacy row and the payload
    /// that describes it are both in hand.
    static func things(token: String) async -> [Thing]? {
        // result=APPROVED: land real purchases, not blocked/declined attempts
        // (a decline may be worth surfacing later — held as a re-measure
        // question, not guessed at here). page_size caps the backfill.
        let url = "\(api)/transactions?result=APPROVED&page_size=50"
        guard let rows = await list(url, token: token) else { return nil }
        let shaped = rows.compactMap(txnThing)
        await repairLanded(shaped)
        return shaped
    }

    /// A purchase: "Netflix.com · $12.99", dated when Privacy recorded it.
    /// The amount is the settled amount once known, else the authorization
    /// amount — both are integer CENTS in the card's (USD) currency. Privacy
    /// exposes no per-transaction permalink, so the row opens the Privacy
    /// dashboard where the transaction lives (re-measure item: confirm a
    /// deep-linkable transaction URL exists before promising one).
    ///
    /// `.transaction`, not `.link` (user ruling, 2026-08-06). It landed as a
    /// `.link` for the dashboard URL above — but that URL names the account,
    /// not the purchase, so the row was a link that didn't link to the thing,
    /// and it answered "show my links" in the retriever instead of the kind it
    /// actually is. `content` stays the dashboard URL, which is still the best
    /// place a tap can go.
    ///
    /// The amount also rides `priceValue`/`priceCurrency` now. It used to
    /// exist ONLY inside the formatted title, which meant every spend rollup
    /// in the app skipped these rows — money in the corpus that no total could
    /// reach without re-parsing prose, the one thing money arithmetic here
    /// never does. An unreadable amount stays nil on both fields rather than
    /// landing a 0: an unread amount is not a free purchase.
    private static func txnThing(_ txn: [String: Any]) -> Thing? {
        guard let id = txn["token"] as? String else { return nil }
        let merchant = txn["merchant"] as? [String: Any]
        let name = (merchant?["descriptor"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Privacy transaction"
        let cents = centsFor(txn)
        let title = cents.flatMap(money).map { "\(name) · \($0)" } ?? name
        let thing = Thing(
            kind: .transaction,
            title: IngestSupport.titleLine(title),
            content: "https://privacy.com/account",
            source: "Privacy",
            capturedAt: IngestSupport.isoDate(txn["created"]) ?? .now,
            sourceRef: "privacy:txn:\(id)"
        )
        applyAmount(cents, to: thing)
        applyMerchant(name, to: thing)
        thing.tags = settlementTags(txn)
        return thing
    }

    /// The merchant as a FIELD, not only as the head of a joined title
    /// (2026-08-12, prd §368).
    ///
    /// It was read here and thrown away: `merchant.descriptor` went into the
    /// title string and nowhere else, so the sheet could not name who you paid
    /// without slicing a localized string back apart — the §340 bug this app
    /// has already paid for twice. `transferCounterparty` is the field Apple
    /// Wallet has stamped the same fact into since §317; one meaning, one home,
    /// so a purchase sheet can never disagree with itself about who it was.
    ///
    /// Normalized through `AppleWalletRoom.normalizeMerchant` for the reason
    /// that function exists: a card descriptor is a processor's string, so
    /// `SQ *BLUE BOTTLE` and `BLUE BOTTLE` are one merchant filed as two, and
    /// the failure to fear is not a prefix that fails to strip (which reads as
    /// two shops, visibly) but a strip that MERGES two real merchants, which
    /// renders perfectly. Privacy descriptors carry exactly the same shapes as
    /// the bank descriptors that table was measured against.
    private static func applyMerchant(_ raw: String, to thing: Thing) {
        let name = AppleWalletRoom.normalizeMerchant(raw)
            .trimmingCharacters(in: .whitespaces)
        thing.transferCounterparty = name.isEmpty ? nil : name
    }

    /// Settled, or still an authorization.
    ///
    /// **The §317 lesson in a second seat.** `centsFor` prefers
    /// `settled_amount` and falls back to `amount`, so the payload already
    /// distinguishes a final charge from one that can still change — and the
    /// distinction was collapsed into one number with nothing left to say
    /// which. A receipt that states an authorization as though it were final
    /// is claiming a figure it doesn't have.
    ///
    /// English facet tags (§308/§340), so the reading survives a language
    /// change; a row that answers neither gets no badge rather than a
    /// defaulted "Settled", which would be the fake status this app's design
    /// law bans on the one screen about money.
    private static func settlementTags(_ txn: [String: Any]) -> [String] {
        let settled = (txn["settled_amount"] as? Int).map { $0 > 0 } ?? false
        return ["Card", settled ? "Settled" : "Pending"]
    }

    /// The charge in integer CENTS — the settled amount once Privacy knows it,
    /// else the authorization amount — or nil when neither field reads as a
    /// positive integer.
    ///
    /// RE-MEASURE QUESTION, held rather than guessed at: what a RETURN looks
    /// like here. Privacy's docs don't say whether a refund arrives as its own
    /// `result=APPROVED` row, as a negative amount, or only as a settled
    /// amount that contradicts its authorization — and this fallback would
    /// land a return wearing its positive authorization amount, i.e. reading
    /// as a purchase. No "Refund" tag is invented for a shape nobody here has
    /// seen; `-privacyProbe` prints the raw amount/status/type fields of the
    /// newest rows precisely so a key can answer this, and the answer belongs
    /// in this function before any total treats these rows as signed.
    private static func centsFor(_ txn: [String: Any]) -> Int? {
        (txn["settled_amount"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            ?? (txn["amount"] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The comparable amount, written to both price fields together — a value
    /// with no currency can't be re-formatted or summed, so neither lands
    /// without the other. USD by the same card-currency assumption `money`
    /// makes below, and it is UNMEASURED for the same reason.
    private static func applyAmount(_ cents: Int?, to thing: Thing) {
        guard let cents, cents > 0 else {
            thing.priceValue = nil
            thing.priceCurrency = nil
            return
        }
        thing.priceValue = Double(cents) / 100.0
        thing.priceCurrency = "USD"
    }

    /// Repairs Privacy rows already in the corpus from the SAME payload this
    /// pass just read — the heal-on-the-dedupe-hit pattern the social bridges
    /// use, and load bearing for exactly their reason: `TokenIngest.insert`
    /// drops a `sourceRef` it has already seen, so without this a row landed
    /// before 2026-08-06 would stay a `.link` with no `priceValue` forever and
    /// only rows landed afterwards would carry numbers — a corpus silently
    /// half-covered, which every total would read as complete.
    ///
    /// It reads `SharedStore.live`'s own main context rather than opening one
    /// (`WalletBackgroundRefresh.runNotifySweep`'s rule: two containers over
    /// one store file is two contexts that disagree) — `TokenIngest` inserts
    /// into that same context, so the repair and the landing can't diverge.
    ///
    /// Its ceiling, stated because it is real: it reaches only the rows this
    /// pass's own page describes (`page_size=50`). A purchase older than that
    /// window is never re-described by the API, so it keeps whatever it landed
    /// with — the same page-window ceiling every enrichment heal here has.
    @MainActor
    private static func repairLanded(_ fresh: [Thing]) {
        guard let context = SharedStore.live?.mainContext else { return }
        let stored = IngestSupport.thingsByRef(context, source: "Privacy")
        guard !stored.isEmpty else { return }
        var changed = false
        for row in fresh {
            guard let ref = row.sourceRef, let landed = stored[ref], landed.isLive
            else { continue }
            if landed.kind != .transaction { landed.kind = .transaction; changed = true }
            if landed.priceValue != row.priceValue {
                landed.priceValue = row.priceValue
                changed = true
            }
            if landed.priceCurrency != row.priceCurrency {
                landed.priceCurrency = row.priceCurrency
                changed = true
            }
            // The merchant and the settlement state, for the same reason the
            // three lines above exist: without this only rows landed after
            // 2026-08-12 could name who you paid, and a corpus half-covered
            // reads as complete — the sheet would simply fall back to the
            // title on the older half and nothing would say why.
            if landed.transferCounterparty != row.transferCounterparty {
                landed.transferCounterparty = row.transferCounterparty
                changed = true
            }
            if landed.tags != row.tags {
                landed.tags = row.tags
                changed = true
            }
        }
        if changed { context.saveHonestly() }
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
    ///
    /// It prints a LINE PER ROW rather than only the first, and prints every
    /// amount-ish and outcome-ish field raw, because the open question this
    /// bridge cannot answer from the docs is what a RETURN looks like (see
    /// `centsFor`): whether it arrives as its own row, as a negative amount,
    /// or as a settled amount below its authorization. A single row can't show
    /// that; a page can. One NSLog per row on purpose — a joined multi-line
    /// message gets truncated by the log reader (the `-todayProbe` lesson).
    static func probe() async {
        guard let token = TokenVault.get(TokenBridge.privacy.tokenKey) else {
            NSLog("[Casberi] privacyProbe: no stored key (connect via -tokenBridge \"Privacy:<key>\")")
            return
        }
        let url = "\(api)/transactions?result=APPROVED&page_size=25"
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: "api-key \(token)")
        guard status == 200 else {
            NSLog("[Casberi] privacyProbe: HTTP %d (401 wrong key · 404/410 endpoint gone · 0 unreachable)", status)
            return
        }
        let root = json as? [String: Any]
        let rows = (json as? [[String: Any]]) ?? (root?["data"] as? [[String: Any]]) ?? []
        let envelope = root.map { Array($0.keys).sorted().joined(separator: ",") } ?? "bare-array"
        NSLog("[Casberi] privacyProbe: HTTP 200 · envelope={%@} · %d txns", envelope, rows.count)
        for txn in rows {
            let merchant = (txn["merchant"] as? [String: Any])?["descriptor"] as? String ?? "—"
            NSLog("[Casberi] privacyTxn| merchant=%@ amount=%@ settled=%@ authorization=%@ result=%@ status=%@ type=%@ created=%@ fields={%@}",
                  merchant,
                  String(describing: txn["amount"] ?? "nil"),
                  String(describing: txn["settled_amount"] ?? "nil"),
                  String(describing: txn["authorization_amount"] ?? "nil"),
                  String(describing: txn["result"] ?? "nil"),
                  String(describing: txn["status"] ?? "nil"),
                  String(describing: txn["type"] ?? "nil"),
                  String(describing: txn["created"] ?? "nil"),
                  Array(txn.keys).sorted().joined(separator: ","))
        }
    }
}
