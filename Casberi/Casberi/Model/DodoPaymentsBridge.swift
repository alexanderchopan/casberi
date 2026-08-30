import Foundation
import SwiftData

/// Dodo Payments (2026-08-30) — a Merchant-of-Record payment processor, the
/// "Stripe alternative" indie/AI-first products increasingly bill through.
/// One paste of a read-only API key, plain `TokenSetupScreen`, generic
/// dispatch — the Trello/Cloudflare tier, not Stripe's bespoke screen and
/// room head. Grouped **Work**, beside Stripe/PostHog: this is money a
/// BUSINESS receives, not a personal card's spending (Privacy.com/Gnosis
/// Pay's group, "Wallet") — the request that started this file used Privacy
/// as its point of comparison, and that reference is about the ENGINEERING
/// SHAPE (one key, read-only, lands transactions), not the catalog group.
///
/// **Deliberate divergence from `StripeBridge`'s doctrine, stated so it isn't
/// mistaken for an oversight.** Stripe lands an individual charge NEVER — "a
/// £9 payment is a tally wearing a currency symbol" — because Stripe serves
/// accounts of every size including ones taking thousands of charges a day,
/// and the doctrine's tally test is about VOLUME. Dodo Payments' own pitch
/// ("Billing & Payments Platform for AI-First Companies") targets indie
/// creators and small SaaS founders, i.e. accounts that take a payment
/// occasionally rather than constantly — for that audience a payment
/// arriving IS the news, the same reasoning that already lands every card
/// spend for Privacy.com and Gnosis Pay. So this bridge lands every
/// SUCCEEDED payment, every refund, and (Stripe's shapes, unchanged) a
/// dispute opening, a dispute closing, and a subscription leaving a healthy
/// state. If this bridge is ever pointed at a high-volume account, revisit —
/// the doctrine's reasoning, not this file's precedent, should decide.
///
/// **Why this reads a WINDOW and diffs, never a cursor (the Stripe shape
/// doesn't fit).** Stripe's `/v1/events` is an immutable append-only log — a
/// dispute closing is a SECOND event, so a forward cursor never needs to
/// re-read anything. Dodo's `/payments`, `/disputes`, `/refunds` and
/// `/subscriptions` are plain LISTS reporting an object's CURRENT state, with
/// no event feed and no `updated_at` on a dispute — so a status change on an
/// old dispute is invisible to a cursor keyed on `created_at`. Payments and
/// refunds are near enough to immutable (a payment settles once) that a
/// bounded recent window plus `sourceRef` dedupe is correct; disputes and
/// subscriptions actively mutate, so this keeps a small local map of
/// `id → last-known status` and re-reads the newest page every pass,
/// landing a thing only on a real transition — the same shape
/// `HyperliquidDeFi`'s open-position diff and `PrivacyPoolsBridge`'s
/// pending-review poll already use for exactly this problem.
///
/// **UNMEASURED against a live account (2026-08-30)** — authored from Dodo's
/// public API reference and its Go SDK's resource files, with no key stored
/// and no egress to `live.dodopayments.com` from this host. Every read is a
/// GET, every failure path returns nil or drops the row, and no write verb
/// appears in this file — see the conduct note on `DodoPaymentsFetch`. Two
/// specific unmeasured guesses, called out so a probe run can correct them
/// before they're trusted: (1) the dashboard's exact base URL
/// (`app.dodopayments.com`, inferred from its `/signup` path — no per-object
/// deep link is documented, so every row opens the dashboard root, the
/// Privacy.com shape for the identical reason); (2) whether a dispute's
/// `amount` string (documented only as "a string to accommodate precision")
/// is already a major-unit decimal or needs `StripeMoney`'s minor-unit
/// divisor — this file assumes the former. Run `-dodoPaymentsProbe YES`
/// against a real key and reconcile both before hardening either.
enum DodoPaymentsAccount {

    static let api = "https://live.dodopayments.com"
    static let dashboardURL = "https://app.dodopayments.com"
    // The literal form `setup-copy-audit.py`'s `stamped_sources` scans for —
    // `TokenBridge.dodoPayments.source` (the rawValue) resolves to this same
    // string at runtime but isn't a literal the audit can see, which is
    // exactly the silent hole `audit_token_sources` exists to catch.
    static let source = "Dodo Payments"

    static var configured: Bool {
        TokenVault.get(TokenBridge.dodoPayments.tokenKey) != nil
    }

    /// How far back the payments/refunds window reaches, every pass — not a
    /// cursor (see the type doc). Bounded to avoid a first connect on a
    /// years-old account landing hundreds of rows as if they all just
    /// happened (the Peer/Privacy Pools "backfill wearing news" rule), and
    /// cheap enough to re-read in full every foreground for the audience
    /// this bridge is built for (occasional payments, not a firehose).
    static let windowDays = 30

    /// Disputes/subscriptions status snapshots — `id → (status, firstSeenAt,
    /// createdAt)` — the state a diff needs and none of it a `Thing`. Wiped
    /// on disconnect; a reconnect (possibly a different account) must not
    /// diff a stranger's disputes against this account's history.
    struct TrackedItem: Codable {
        var status: String
        var firstSeenAt: Date
        /// The object's own `created_at`, when Dodo reports one — preferred
        /// over `firstSeenAt` for a duration clause, since it's the real
        /// moment rather than whenever this app happened to poll.
        var createdAt: Date?
    }

    private static func trackedKey(_ name: String) -> String { "dodopayments.tracked.\(name)" }

    static func tracked(_ name: String) -> [String: TrackedItem] {
        guard let data = UserDefaults.standard.data(forKey: trackedKey(name)),
              let decoded = try? JSONDecoder().decode([String: TrackedItem].self, from: data)
        else { return [:] }
        return decoded
    }

    static func setTracked(_ name: String, _ map: [String: TrackedItem]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: trackedKey(name))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: trackedKey("disputes"))
        UserDefaults.standard.removeObject(forKey: trackedKey("subscriptions"))
    }
}

// MARK: - The reads

enum DodoPaymentsFetch {

    /// Read-only by CONDUCT AND by scope — a Dodo key can be minted with
    /// "Enable write access" left unchecked (the SCOPED grade, Stripe's/
    /// PostHog's rung: a box someone else's page lets you tick, not a scope
    /// Casberi mints itself). This file issues GET only, on the four
    /// endpoints named below, as defense in depth for a key minted with the
    /// box checked by mistake. Do not add a write verb here.
    private static func auth(_ key: String) -> String { "Bearer \(key)" }

    /// Dodo's test keys are (per its own docs and SDKs) prefixed `test_`
    /// against `live_` — UNVERIFIED against a real pair (no confirmed
    /// example was found; re-measure via `-dodoPaymentsProbe`). Refused
    /// before a single request, Stripe's exact reasoning: a corpus of things
    /// that really happened must never carry sandbox money.
    static func isTestKey(_ key: String) -> Bool { key.hasPrefix("test_") }

    /// Internal, not private — the probe calls this directly so it can report
    /// the REAL status per endpoint (401 vs. 0 vs. something else) rather
    /// than a bare "UNREADABLE" listing every possibility, the way every
    /// other probe in this file naming a raw shape does.
    static func envelope(_ url: String, key: String) async -> (items: [[String: Any]], status: Int) {
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key))
        let items = (json as? [String: Any])?["items"] as? [[String: Any]]
        return (items ?? [], status)
    }

    /// Succeeded payments from the last `windowDays`, newest first, paged up
    /// to `maxPages`. `nil` only on a read failure (bad key, unreachable) —
    /// an empty-but-successful page returns `[]`, which `refresh` reads as
    /// "up to date" rather than "couldn't connect".
    static func payments(key: String) async -> [[String: Any]]? {
        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-Double(DodoPaymentsAccount.windowDays) * 86_400))
        var all: [[String: Any]] = []
        var page = 0
        let maxPages = 3
        while page < maxPages {
            let url = "\(DodoPaymentsAccount.api)/payments?status=succeeded&created_at_gte=\(since)&page_size=100&page_number=\(page)"
            let (items, status) = await envelope(url, key: key)
            guard status == 200 else { return page == 0 ? nil : all }
            all.append(contentsOf: items)
            guard items.count == 100 else { break }
            page += 1
        }
        if page >= maxPages {
            NSLog("[Casberi] dodoPayments: payments backlog deeper than %d pages this window — older rows wait for next pass", maxPages)
        }
        return all
    }

    /// Refunds from the last `windowDays`, every status (a refund is rare
    /// enough that even a pending/failed one is worth a row, unlike a
    /// succeeded payment where only the succeeded ones are news).
    static func refunds(key: String) async -> [[String: Any]]? {
        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-Double(DodoPaymentsAccount.windowDays) * 86_400))
        let url = "\(DodoPaymentsAccount.api)/refunds?created_at_gte=\(since)&page_size=100&page_number=0"
        let (items, status) = await envelope(url, key: key)
        return status == 200 ? items : nil
    }

    /// The newest page of disputes, UNFILTERED by date — a dispute can stay
    /// open for weeks, and this file has no signal for how long, so bounding
    /// by recency risks losing one mid-resolution. One page (100) is the
    /// Trello tier's bound: plenty for the account sizes this bridge targets.
    static func disputes(key: String) async -> [[String: Any]]? {
        let url = "\(DodoPaymentsAccount.api)/disputes?page_size=100&page_number=0"
        let (items, status) = await envelope(url, key: key)
        return status == 200 ? items : nil
    }

    static func subscriptions(key: String) async -> [[String: Any]]? {
        let url = "\(DodoPaymentsAccount.api)/subscriptions?page_size=100&page_number=0"
        let (items, status) = await envelope(url, key: key)
        return status == 200 ? items : nil
    }

    // MARK: Probe

    /// `-dodoPaymentsProbe YES` — the measure tool for an UNMEASURED API.
    /// Connect first (`-tokenBridge "Dodo Payments:<live_…>"`), then this
    /// reads the STORED key and NSLogs the RAW shapes per endpoint — HTTP
    /// status (so 401 wrong-key and 0 unreachable stay distinct), the raw
    /// field set on the first row of each, and one line per row for
    /// payments/refunds/disputes/subscriptions with the title each would
    /// land wearing. One NSLog per line on purpose — a joined multi-line
    /// message truncates in the log reader (the `-todayProbe` lesson).
    /// Reads only; never advances the tracked-status maps, so it can be
    /// re-run without disturbing what the real sweep would land next.
    static func probe() async {
        guard let key = TokenVault.get(TokenBridge.dodoPayments.tokenKey) else {
            NSLog("[Casberi] dodoPaymentsProbe: no stored key (connect via -tokenBridge \"Dodo Payments:<key>\")")
            return
        }
        if isTestKey(key) {
            NSLog("[Casberi] dodoPaymentsProbe: STORED KEY LOOKS LIKE TEST MODE — the real sweep refuses these")
        }

        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-Double(DodoPaymentsAccount.windowDays) * 86_400))

        let payments = await envelope("\(DodoPaymentsAccount.api)/payments?status=succeeded&created_at_gte=\(since)&page_size=100&page_number=0", key: key)
        NSLog("[Casberi] dodoPaymentsProbe payments: HTTP %d · %d in the %d-day window (401 wrong key · 0 unreachable)",
              payments.status, payments.items.count, DodoPaymentsAccount.windowDays)
        for row in payments.items {
            guard let shaped = DodoPaymentsShape.payment(row) else {
                NSLog("[Casberi] dodoPaymentsRow| payment UNSHAPED fields=%@", Array(row.keys).sorted().joined(separator: ","))
                continue
            }
            NSLog("[Casberi] dodoPaymentsRow| payment → %@", shaped.title)
        }

        let refunds = await envelope("\(DodoPaymentsAccount.api)/refunds?created_at_gte=\(since)&page_size=100&page_number=0", key: key)
        NSLog("[Casberi] dodoPaymentsProbe refunds: HTTP %d · %d in the %d-day window",
              refunds.status, refunds.items.count, DodoPaymentsAccount.windowDays)
        for row in refunds.items {
            guard let shaped = DodoPaymentsShape.refund(row) else { continue }
            NSLog("[Casberi] dodoPaymentsRow| refund → %@", shaped.title)
        }

        let disputes = await envelope("\(DodoPaymentsAccount.api)/disputes?page_size=100&page_number=0", key: key)
        NSLog("[Casberi] dodoPaymentsProbe disputes: HTTP %d · %d total", disputes.status, disputes.items.count)
        for row in disputes.items {
            let id = (row["dispute_id"] as? String) ?? "?"
            let status = (row["dispute_status"] as? String) ?? "?"
            NSLog("[Casberi] dodoPaymentsRow| dispute id=%@ status=%@ amount=%@ currency=%@",
                  id, status,
                  String(describing: row["amount"] ?? "nil"),
                  (row["currency"] as? String) ?? "?")
        }

        let subs = await envelope("\(DodoPaymentsAccount.api)/subscriptions?page_size=100&page_number=0", key: key)
        NSLog("[Casberi] dodoPaymentsProbe subscriptions: HTTP %d · %d total", subs.status, subs.items.count)
        for row in subs.items {
            let id = (row["subscription_id"] as? String) ?? "?"
            let status = (row["status"] as? String) ?? "?"
            NSLog("[Casberi] dodoPaymentsRow| subscription id=%@ status=%@ next_billing=%@",
                  id, status, String(describing: row["next_billing_date"] ?? "nil"))
        }
    }
}

// MARK: - Shaping a payload into a thing

enum DodoPaymentsShape {

    struct Shaped {
        var title: String
        var tag: String
        var facets: [String] = []
        var when: Date
        var dueAt: Date?
        var counterparty: String?
        var amountMajor: Double?
        var currency: String?
    }

    /// Dodo's timestamps are ISO 8601 strings, unlike Stripe's unix seconds.
    /// Internal, not private — `DodoPaymentsIngest`'s dispute diff needs it
    /// too, to judge whether a first-sighting is recent.
    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return ISO8601DateFormatter().date(from: s)
            ?? IngestSupport.isoDate(s)
    }

    /// A payment's `total_amount` is an integer in the currency's smallest
    /// unit — the exact shape Stripe's amounts take, and Dodo's own
    /// `payment_provider` field (stripe/adyen/dodo) suggests it inherited the
    /// convention. Reuses `StripeMoney` rather than a second currency table.
    static func payment(_ row: [String: Any]) -> Shaped? {
        guard let id = row["payment_id"] as? String, !id.isEmpty else { return nil }
        let minor = intValue(row["total_amount"])
        let currency = (row["currency"] as? String) ?? ""
        let customer = row["customer"] as? [String: Any]
        let name = (customer?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let text = currency.isEmpty ? nil : StripeMoney.text(minor, currency: currency)
        let title = [name, text].compactMap { $0 }.joined(separator: " · ")
        return Shaped(
            title: title.isEmpty ? "Payment received" : title,
            tag: "Payment",
            when: date(row["created_at"]) ?? .now,
            counterparty: name,
            amountMajor: currency.isEmpty ? nil : StripeMoney.value(minor, currency: currency),
            currency: currency.isEmpty ? nil : currency.uppercased()
        )
    }

    static func refund(_ row: [String: Any]) -> Shaped? {
        guard let id = row["refund_id"] as? String, !id.isEmpty else { return nil }
        let status = (row["status"] as? String) ?? ""
        let currency = (row["currency"] as? String) ?? ""
        let amount = row["amount"]
        var title = "Refund"
        var amountMajor: Double?
        if let currency = row["currency"] as? String, !currency.isEmpty, amount != nil {
            let minor = intValue(amount)
            title += " · \(StripeMoney.text(minor, currency: currency))"
            amountMajor = StripeMoney.value(minor, currency: currency)
        }
        if let reason = row["reason"] as? String, !reason.isEmpty { title += " — \(reason)" }
        // English facet, never localized (§308/§340) — the outcome must
        // survive a language change, and "succeeded" reads as the healthy
        // default so it earns no facet of its own.
        let facets = status.isEmpty || status == "succeeded" ? [] : [status.capitalized]
        return Shaped(
            title: title, tag: "Refund", facets: facets,
            when: date(row["created_at"]) ?? .now,
            amountMajor: amountMajor,
            currency: currency.isEmpty ? nil : currency.uppercased()
        )
    }

    /// Dispute AMOUNT arrives as a STRING ("to accommodate precision", per
    /// Dodo's own docs) with no confirmation of whether it's already a
    /// major-unit decimal or needs `StripeMoney`'s minor-unit divisor. This
    /// assumes the former — a plain decimal — which is the more common shape
    /// for a string-typed money field; UNMEASURED, see the type doc.
    private static func disputeAmount(_ row: [String: Any]) -> (major: Double, text: String)? {
        guard let raw = row["amount"] as? String, let decimal = Decimal(string: raw),
              let currency = row["currency"] as? String, !currency.isEmpty
        else { return nil }
        let major = NSDecimalNumber(decimal: decimal).doubleValue
        let text = PriceFormat.string(major, currency: currency) ?? "\(currency) \(raw)"
        return (major, text)
    }

    /// "Opened" the first time a dispute is seen in `dispute_opened`, if it's
    /// recent — an older one already open when this bridge connects is a
    /// backfill, not news (the Privacy Pools "an alert older than a day
    /// seeds its status silently" rule).
    static func disputeOpened(_ row: [String: Any]) -> Shaped? {
        let money = disputeAmount(row)
        let title = "Dispute opened" + (money.map { " · \($0.text)" } ?? "")
        return Shaped(title: title, tag: "Dispute", facets: ["Opened"],
                      when: date(row["created_at"]) ?? .now,
                      amountMajor: money?.major,
                      currency: (row["currency"] as? String)?.uppercased())
    }

    static func disputeClosed(_ row: [String: Any], openedAt: Date?) -> Shaped? {
        let status = (row["dispute_status"] as? String) ?? ""
        let verb: String
        let facet: String
        switch status {
        case "dispute_won":       verb = "Dispute won";       facet = "Won"
        case "dispute_lost":      verb = "Dispute lost";      facet = "Lost"
        case "dispute_accepted":  verb = "Dispute accepted";  facet = "Accepted"
        case "dispute_cancelled": verb = "Dispute cancelled"; facet = "Cancelled"
        case "dispute_expired":   verb = "Dispute expired";   facet = "Expired"
        default:                 verb = "Dispute closed";     facet = "Closed"
        }
        let money = disputeAmount(row)
        var title = verb + (money.map { " · \($0.text)" } ?? "")
        let when = date(row["created_at"]) ?? .now
        if let openedAt, let clause = lasted(from: openedAt, to: when) { title += " — \(clause)" }
        return Shaped(title: title, tag: "Dispute", facets: [facet], when: when,
                      amountMajor: money?.major,
                      currency: (row["currency"] as? String)?.uppercased())
    }

    /// Only the states worth a nudge — `pending`/`active` are the healthy
    /// steady state and never alarm.
    static func subscriptionAlarm(_ row: [String: Any]) -> Shaped? {
        let status = (row["status"] as? String) ?? ""
        let verb: String
        let facet: String
        let stillRecoverable: Bool
        switch status {
        case "cancelled": verb = "Subscription canceled"; facet = "Cancelled"; stillRecoverable = false
        case "expired":   verb = "Subscription expired";  facet = "Expired";   stillRecoverable = false
        case "failed":    verb = "Subscription payment failed"; facet = "Failed"; stillRecoverable = true
        case "on_hold":   verb = "Subscription on hold";  facet = "OnHold";    stillRecoverable = true
        case "paused":    verb = "Subscription paused";   facet = "Paused";    stillRecoverable = true
        default: return nil
        }
        let customer = row["customer"] as? [String: Any]
        let name = (customer?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = name.map { "\(verb) · \($0)" } ?? verb
        let due = stillRecoverable ? DodoPaymentsShape.date(row["next_billing_date"]) : nil
        return Shaped(title: title, tag: "Subscription", facets: [facet],
                      when: .now, dueAt: due, counterparty: name)
    }

    /// "6 days after it opened" — the Stripe/Hyperliquid held-duration rule:
    /// never invented, always measured against the app's own record of when
    /// the earlier moment really happened.
    private static func lasted(from opened: Date, to closed: Date) -> String? {
        let seconds = closed.timeIntervalSince(opened)
        guard seconds >= 3600 else { return nil }
        return seconds < 86_400
            ? String(localized: "\(max(1, Int(seconds / 3600))) hour after it opened")
            : String(localized: "\(max(1, Int(seconds / 86_400))) day after it opened")
    }

    private static func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }
}

// MARK: - The sweep

enum DodoPaymentsIngest {

    @MainActor private static var running = false

    /// Reads all four resources, lands what's news, and returns how much did.
    /// `nil` is the honest "couldn't read" — no key, a test-mode key, a
    /// rejected key, or the network — which the generic `TokenSetupScreen`
    /// words as "check the token".
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard let key = TokenVault.get(TokenBridge.dodoPayments.tokenKey) else { return nil }
        guard !DodoPaymentsFetch.isTestKey(key) else { return nil }
        running = true
        defer { running = false }

        // The four reads are independent — one failing never blocks another,
        // matching Stripe's reasoning for splitting its own reads.
        async let paymentsTask = DodoPaymentsFetch.payments(key: key)
        async let refundsTask = DodoPaymentsFetch.refunds(key: key)
        async let disputesTask = DodoPaymentsFetch.disputes(key: key)
        async let subscriptionsTask = DodoPaymentsFetch.subscriptions(key: key)

        let payments = await paymentsTask
        let refunds = await refundsTask
        let disputes = await disputesTask
        let subscriptions = await subscriptionsTask

        // Every read failing at once is the "couldn't connect" case the
        // generic screen needs a nil for; any one succeeding means the key
        // works and this pass has real, if partial, news to report.
        guard payments != nil || refunds != nil || disputes != nil || subscriptions != nil
        else { return nil }

        var landed: [Thing] = []

        for row in payments ?? [] {
            guard let id = row["payment_id"] as? String,
                  let shaped = DodoPaymentsShape.payment(row) else { continue }
            landed.append(thing(shaped, kind: .transaction,
                                sourceRef: "dodopayments:payment:\(id)"))
        }

        for row in refunds ?? [] {
            guard let id = row["refund_id"] as? String,
                  let shaped = DodoPaymentsShape.refund(row) else { continue }
            landed.append(thing(shaped, kind: .transaction,
                                sourceRef: "dodopayments:refund:\(id)"))
        }

        if let disputes { landed.append(contentsOf: diffDisputes(disputes)) }
        if let subscriptions { landed.append(contentsOf: diffSubscriptions(subscriptions)) }

        return insert(landed, context: context)
    }

    /// Diffs the newest dispute page against the locally tracked status map,
    /// landing an "opened" or "closed" thing only on a real transition — see
    /// the type doc on why this can't be a cursor.
    private static func diffDisputes(_ rows: [[String: Any]]) -> [Thing] {
        var tracked = DodoPaymentsAccount.tracked("disputes")
        var landed: [Thing] = []
        let terminal: Set<String> = ["dispute_won", "dispute_lost", "dispute_accepted",
                                     "dispute_cancelled", "dispute_expired"]
        for row in rows {
            guard let id = row["dispute_id"] as? String, !id.isEmpty else { continue }
            let status = (row["dispute_status"] as? String) ?? ""
            let createdAt = DodoPaymentsShape.date(row["created_at"])

            if let known = tracked[id] {
                guard known.status != status else { continue }
                if terminal.contains(status), let shaped = DodoPaymentsShape.disputeClosed(
                    row, openedAt: known.createdAt ?? known.firstSeenAt) {
                    landed.append(thing(shaped, kind: .reminder,
                                        sourceRef: "dodopayments:dispute:\(id):closed"))
                }
                tracked[id] = DodoPaymentsAccount.TrackedItem(
                    status: status, firstSeenAt: known.firstSeenAt, createdAt: known.createdAt)
            } else {
                // First sighting. Alarm only for a genuinely fresh open —
                // older-than-a-day means this bridge just connected onto a
                // dispute that predates it, which is a backfill, not news.
                let recent = createdAt.map { Date.now.timeIntervalSince($0) < 86_400 } ?? false
                if status == "dispute_opened", recent,
                   let shaped = DodoPaymentsShape.disputeOpened(row) {
                    landed.append(thing(shaped, kind: .reminder,
                                        sourceRef: "dodopayments:dispute:\(id):opened"))
                }
                tracked[id] = DodoPaymentsAccount.TrackedItem(
                    status: status, firstSeenAt: .now, createdAt: createdAt)
            }
        }
        DodoPaymentsAccount.setTracked("disputes", tracked)
        return landed
    }

    /// The subscription shape of the same diff — every first sighting seeds
    /// silently (a subscription's CURRENT status on first sight says nothing
    /// about whether it just changed), and only a transition into an
    /// alarm-worthy status lands.
    private static func diffSubscriptions(_ rows: [[String: Any]]) -> [Thing] {
        var tracked = DodoPaymentsAccount.tracked("subscriptions")
        var landed: [Thing] = []
        for row in rows {
            guard let id = row["subscription_id"] as? String, !id.isEmpty else { continue }
            let status = (row["status"] as? String) ?? ""
            defer {
                tracked[id] = DodoPaymentsAccount.TrackedItem(
                    status: status, firstSeenAt: tracked[id]?.firstSeenAt ?? .now, createdAt: nil)
            }
            guard let known = tracked[id], known.status != status else { continue }
            guard let shaped = DodoPaymentsShape.subscriptionAlarm(row) else { continue }
            // Stamped with the status so a subscription that later re-enters
            // the SAME alarm state (on_hold → active → on_hold) lands again.
            landed.append(thing(shaped, kind: .reminder,
                                sourceRef: "dodopayments:subscription:\(id):\(status)"))
        }
        DodoPaymentsAccount.setTracked("subscriptions", tracked)
        return landed
    }

    private static func thing(_ shaped: DodoPaymentsShape.Shaped, kind: ThingKind, sourceRef: String) -> Thing {
        let t = Thing(kind: kind,
                      title: IngestSupport.titleLine(shaped.title),
                      content: DodoPaymentsAccount.dashboardURL,
                      source: DodoPaymentsAccount.source,
                      capturedAt: shaped.when,
                      tags: [shaped.tag] + shaped.facets,
                      sourceRef: sourceRef)
        t.dueAt = shaped.dueAt
        t.transferCounterparty = shaped.counterparty
        if let amount = shaped.amountMajor, let currency = shaped.currency {
            t.priceValue = amount
            t.priceCurrency = currency
        }
        return t
    }

    @MainActor
    private static func insert(_ incoming: [Thing], context: ModelContext) -> Int {
        let existing = IngestSupport.existingSourceRefs(context, source: DodoPaymentsAccount.source)
        var added = 0
        for item in incoming {
            guard let ref = item.sourceRef, !existing.contains(ref) else { continue }
            context.insert(item)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }
}
