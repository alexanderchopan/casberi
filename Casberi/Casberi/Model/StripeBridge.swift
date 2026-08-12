import Foundation
import SwiftData

/// Stripe (2026-07-31) — the money behind what you ship, beside PostHog's
/// numbers. PostHog tells you what people did; this tells you what they paid.
///
/// Stripe INVERTS PostHog's design problem. PostHog is a firehose of counts,
/// and a count is exactly what the module doctrine forbids a thing to be — so
/// that bridge needed a carve-out (annotations, milestones, silence) to find
/// anything thing-shaped at all. Stripe is entirely MONEY MOVING, which is the
/// doctrine's one standing exception: the count IS the event. So its raw
/// objects are already the right shape and no carve-out is needed.
///
/// What that does NOT license is landing every charge. A £9 payment on a busy
/// account is a tally wearing a currency symbol, and a hundred of them a day
/// would bury the feed. The exception is for money whose MOVEMENT is the news,
/// so exactly five shapes land — each one something you would want to be told,
/// and each one rare enough that being told is a service:
///
///   1. **A dispute opened.** The best row Stripe has, and the reason to build
///      this at all: it carries an evidence deadline, so it lands as a
///      reconciling `dueAt` (the ENSExpiry/Aerodrome shape) and shows up in
///      every "what's next" surface the app already has. Missing it costs real
///      money — this is the one row here with a clock.
///   2. **A dispute closed.** Won or lost. The loop-closer for (1).
///   3. **A payout.** "£2,140.00 paid out to your bank" — money actually
///      landing, which is the moment a business feels, not the charge.
///      A failed payout lands too, and matters more.
///   4. **A subscription canceled.** Churn: the silence analog, and the one
///      event here that's bad news arriving quietly.
///   5. **A recurring payment failed.** Dunning. Carries Stripe's own next
///      retry as its `dueAt`, so "what's next" is the retry, not a guess.
///
/// Read-only STRUCTURALLY, like PostHog and unlike `PrivacyBridge` (whose key
/// can't be scoped, so its promise is kept by conduct). Stripe restricted keys
/// carry per-resource permissions, so the setup screen names the read scopes
/// and a key minted that way cannot refund, charge, or issue anything —
/// whatever this file did.
///
/// **Test-mode keys are refused at connect, on purpose.** Every other bridge
/// here would happily read a sandbox; this one must not. The corpus is a record
/// of things that really happened, and pretend money filed beside real money is
/// the fake-status ban (§83) in the one domain where believing it is expensive.
/// `StripeFetch.validate` returns `.testKey` and the screen says why.
///
/// **UNMEASURED against a live account (2026-07-31)** — built from Stripe's
/// public API reference, never run against a real key (none is stored, and the
/// build host has no egress to `api.stripe.com`). Every read is a GET, every
/// failure path returns nil to "nothing new", and no write endpoint is reachable
/// from this file, so it fails safe. Run `-stripeProbe YES` against a real
/// restricted key and reconcile the raw shapes it dumps before trusting any of
/// it — particularly the dispute `evidence_details.due_by` and the subscription
/// event's nested price nickname, which are the two nested reads here.
enum StripeAccount {

    /// Stripe is single-tenant per key — one account, no host field and no
    /// project picker (the two things PostHog needed). The account id is read
    /// off the key itself and never typed.
    private static let accountKey = "stripe.account"
    private static let accountNameKey = "stripe.accountName"
    private static let cursorKey = "stripe.cursor"

    static let api = "https://api.stripe.com/v1"

    static var accountID: String {
        get { UserDefaults.standard.string(forKey: accountKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: accountKey) }
    }

    /// The business name Stripe itself reports, so the seat reads "Acme Inc."
    /// rather than "Stripe". Empty when the restricted key wasn't granted the
    /// account read — which is allowed, and degrades to the plain name rather
    /// than blocking the connect (the scope is a nicety, the events are the
    /// bridge).
    static var accountName: String {
        get { UserDefaults.standard.string(forKey: accountNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: accountNameKey) }
    }

    /// The newest event id already landed. Stripe's forward-polling idiom is
    /// `ending_before=<id>`, which returns strictly NEWER events — so this is a
    /// cursor, not a timestamp, and it never re-reads what it has seen.
    static var cursor: String {
        get { UserDefaults.standard.string(forKey: cursorKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: cursorKey) }
    }

    static var configured: Bool {
        TokenVault.get(TokenBridge.stripe.tokenKey) != nil
    }

    /// Where a landed thing opens. Stripe's dashboard paths are stable and
    /// resource-keyed, so a row goes to the exact object rather than a home
    /// page you then have to search.
    static func dashboardURL(_ path: String) -> String {
        "https://dashboard.stripe.com/\(path)"
    }

    /// Bridge-specific teardown — the account identity and the cursor, neither
    /// of which is a Thing (the `BitrefillBalance.clear()` / `PostHogAccount`
    /// precedent). Without dropping the cursor, reconnecting a DIFFERENT Stripe
    /// account would resume from the previous account's event id and silently
    /// land nothing.
    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: accountKey)
        d.removeObject(forKey: accountNameKey)
        d.removeObject(forKey: cursorKey)
        StripeState.clear()
    }
}

// MARK: - Money

/// Stripe amounts are integers in the currency's SMALLEST unit, and how many
/// of those make a unit is NOT always 100. This is the Gnosis Pay decimals
/// lesson in a new currency: hardcoding 100 renders ¥5,000 as ¥50.00 and
/// د.ب12.500 as د.ب1,250.00 — wrong in both directions, silently, forever.
enum StripeMoney {

    /// Currencies Stripe treats as having NO minor unit — the amount is already
    /// whole. Stripe's own documented set.
    private static let zeroDecimal: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA",
        "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
    ]

    /// Currencies with THREE minor digits. Stripe documents these as needing
    /// the amount rounded to the nearest 10 (a trailing zero), but the scale
    /// for display is still 1000.
    private static let threeDecimal: Set<String> = [
        "BHD", "JOD", "KWD", "OMR", "TND",
    ]

    static func divisor(for currency: String) -> Decimal {
        let code = currency.uppercased()
        if zeroDecimal.contains(code) { return 1 }
        if threeDecimal.contains(code) { return 1000 }
        return 100
    }

    /// "£49.00" / "¥5,000" — the amount in its own currency, never a faked "$".
    /// Falls back to "<code> <amount>" for a currency the formatter doesn't
    /// know, which is honest rather than mislabelled.
    static func text(_ minor: Int, currency: String) -> String {
        let code = currency.uppercased()
        let value = Decimal(minor) / divisor(for: code)
        guard !code.isEmpty else { return "\(value)" }
        return value.formatted(.currency(code: code))
    }

    /// The same amount as a NUMBER, for `Thing.priceValue` (2026-08-12).
    ///
    /// Until now every Stripe amount existed only inside `text`'s output —
    /// so the money was in the corpus as characters and nothing could add,
    /// compare or re-format it. Recovering it meant parsing our own
    /// formatting back, which means inverting the two tables above AND
    /// recovering an ISO code from a symbol, and "$" is ambiguous across USD,
    /// CAD, AUD and more. The raw minor units are right here; they just were
    /// never kept.
    ///
    /// `priceValue`/`priceCurrency` are EXISTING fields already in the
    /// deployed CloudKit schema (`CD_priceValue`, `CD_priceCurrency` — Gnosis
    /// Pay and Apple Wallet have used them since they shipped), so this is a
    /// stamp, not a migration: no new property, no Production deploy.
    ///
    /// Note this does NOT join Stripe to `Corpus.cardSpendSources` — that
    /// membership test is `kind == .transaction` AND a source allowlist, and
    /// every Stripe row is a `.link`. "What did I spend?" cannot start
    /// counting disputes.
    static func value(_ minor: Int, currency: String) -> Double? {
        guard !currency.isEmpty else { return nil }
        return NSDecimalNumber(
            decimal: Decimal(minor) / divisor(for: currency.uppercased())
        ).doubleValue
    }
}

// MARK: - The silence alarm

/// "No payments in 14 hours — normally one every 20 minutes."
///
/// The most valuable thing this bridge can say, and the one thing Stripe's own
/// dashboard will not tell you: your checkout is broken. PostHog's silence
/// detector is the direct ancestor — a watched thing that STOPS is news, and
/// the whole difficulty is not crying wolf.
///
/// Pure by design (timestamps in, verdict out) so the judgement can be checked
/// without an account, which matters more here than anywhere else in the file:
/// a false alarm about your revenue is worse than no alarm at all.
enum StripeSilence {

    /// Never alarm before this, whatever the rate. A quiet lunchtime is not an
    /// outage, and an alert that can fire an hour after a blip is an alert
    /// people turn off.
    static let floor: TimeInterval = 6 * 3600

    /// And never take longer than this to notice. Without a ceiling, a business
    /// taking one payment a week would wait months for its alarm — technically
    /// proportionate, practically useless.
    static let ceiling: TimeInterval = 72 * 3600

    /// How many typical gaps must pass before quiet counts as broken.
    static let factor: Double = 8

    /// The sample must carry at least this many payments, or there's no rate to
    /// measure and no business being interrupted.
    static let minCharges = 20

    /// …and the account must have been active recently. A shop that closed in
    /// March is not an outage in July, and telling it that its payments stopped
    /// would be both true and useless.
    static let dormantAfter: TimeInterval = 14 * 86_400

    struct Verdict: Equatable {
        var quiet: Bool
        /// The median gap between payments — what "normally" means, in words
        /// the row can use.
        var typicalGap: TimeInterval
        var since: TimeInterval
    }

    /// `timestamps` in any order; `now` injected so this is testable.
    /// Returns nil when there's no honest verdict to give — too few payments,
    /// or an account that already stopped trading long ago.
    static func verdict(timestamps: [Date], now: Date) -> Verdict? {
        let sorted = timestamps.sorted()
        guard sorted.count >= minCharges, let newest = sorted.last else { return nil }

        let since = now.timeIntervalSince(newest)
        // Dormant, not broken. Measured from the sample's newest payment, so a
        // long-dead account never alarms and a busy one never trips this.
        guard since < dormantAfter else { return nil }

        // The MEDIAN gap, not the mean: one overnight lull in an otherwise
        // busy day would drag a mean far enough to mask a real outage, and one
        // burst would shrink it enough to invent one.
        var gaps: [TimeInterval] = []
        for i in 1..<sorted.count {
            gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]))
        }
        let ordered = gaps.sorted()
        guard !ordered.isEmpty else { return nil }
        let median = ordered.count % 2 == 1
            ? ordered[ordered.count / 2]
            : (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2
        guard median > 0 else { return nil }

        let threshold = min(max(median * factor, floor), ceiling)
        return Verdict(quiet: since > threshold, typicalGap: median, since: since)
    }

    /// "normally one every 20 minutes" — the clause that makes the
    /// alarm mean something. A bare "no payments in 14 hours" is unreadable
    /// without knowing whether 14 hours is unusual for THIS account.
    static func rateText(_ gap: TimeInterval) -> String {
        switch gap {
        case ..<3600:   String(localized: "one every \(max(1, Int(gap / 60))) minute")
        case ..<86_400: String(localized: "one every \(max(1, Int(gap / 3600))) hour")
        default:        String(localized: "one every \(max(1, Int(gap / 86_400))) day")
        }
    }

    /// "14 hours" — the same vocabulary, for how long it's been.
    static func sinceText(_ since: TimeInterval) -> String {
        since < 86_400
            ? String(localized: "\(max(1, Int(since / 3600))) hour")
            : String(localized: "\(max(1, Int(since / 86_400))) day")
    }
}

// MARK: - The payout-runway alert

/// "Your Stripe payout runway is low" (2026-08-09) — the balance's own
/// low-crossing alert, `BitrefillBalance.checkLow`'s shape applied to
/// `StripeState.Balance` instead of a personal top-up account.
///
/// **This is money you've EARNED and are waiting to be paid out, not a
/// prepaid quota** — nothing here is "running out of credits", and the copy
/// says "payout runway" on purpose rather than borrowing OpenRouter's
/// language for a completely different kind of number. Conflating the two
/// would be exactly the §83 fake-status problem this codebase names
/// everywhere else: a balance reading near zero and a service about to stop
/// answering questions are not the same fact wearing different words.
///
/// **The false alarm this had to be built to avoid, and could not fully
/// solve — documented rather than hidden.** Most Stripe accounts sweep their
/// `available` balance to (near) zero automatically on every scheduled
/// payout, which is a completely healthy, ordinary state — not evidence of
/// anything. Two guards cut the false-positive rate without claiming to
/// eliminate it: (1) reads AVAILABLE + PENDING together, not available
/// alone, since pending money is already collected and still arriving, so a
/// business mid-payout-cycle with a healthy pending balance is not "running
/// low" even while available briefly reads near zero; (2) requires the same
/// activity gate `StripeSilence` uses (`verdict != nil` — real, recent
/// charge volume, not a dormant or brand-new account) before it will say
/// anything at all. What it does NOT solve: an active business on a daily
/// automatic payout schedule with thin margins could still see this fire on
/// a normal day. Re-measure against a real account before trusting the
/// fraction below — it is a guess, not a measured threshold, exactly like
/// every other number in this file's UNMEASURED-against-a-live-account
/// ceiling.
enum StripeRunway {
    /// Under 10% of the account's own recent high (available+pending
    /// combined) — a guess, `BitrefillBalance.lowFraction`'s reasoning:
    /// relative to the account's OWN history, since there's no absolute
    /// dollar figure that means the same thing for a $50/month side project
    /// and a business clearing six figures.
    static let lowFraction = 0.1
    /// The smallest high-water mark worth alarming about, in the primary
    /// currency's own MAJOR units (compared after `StripeMoney.divisor`
    /// converts minor→major, so it means roughly the same thing across a
    /// zero-decimal currency like JPY and a three-decimal one like BHD as it
    /// does for USD) — below this the account has never held enough for
    /// "running low" to mean anything. A guess, not measured.
    static let minimumHigh = 20.0

    /// `reading` is inout for the same reason `silenceThings` takes it that
    /// way: both the bucket and the high-water mark live with the balance,
    /// and both are readings of the same windowed pass. Returns nil unless
    /// there's a genuine NEW crossing to report.
    static func check(reading: inout StripeState.Balance, pulse: [Date]?) -> Thing? {
        // The activity gate: no real charge history, no runway opinion.
        guard let pulse, StripeSilence.verdict(timestamps: pulse, now: .now) != nil else {
            return nil
        }
        var combined: [String: Int] = [:]
        for (c, v) in reading.available { combined[c, default: 0] += v }
        for (c, v) in reading.pending   { combined[c, default: 0] += v }
        guard !combined.isEmpty else { return nil }

        var high = reading.highCombined
        for (c, v) in combined { high[c] = max(high[c] ?? 0, v) }
        reading.highCombined = high

        // The currency this business is actually measured in — its biggest
        // historical balance, not necessarily its biggest CURRENT one (a
        // currency that's momentarily ahead only because everything else
        // just got paid out shouldn't steal the read).
        guard let (primary, primaryHigh) = high.max(by: { $0.value < $1.value }), primaryHigh > 0
        else { return nil }
        let primaryHighMajor = (Decimal(primaryHigh) / StripeMoney.divisor(for: primary)) as NSDecimalNumber
        guard primaryHighMajor.doubleValue >= minimumHigh else {
            reading.runwayLow = false
            return nil
        }

        let current = combined[primary] ?? 0
        guard Double(current) < Double(primaryHigh) * lowFraction else {
            reading.runwayLow = false
            return nil
        }
        guard !reading.runwayLow else { return nil }
        reading.runwayLow = true

        let text = StripeMoney.text(current, currency: primary)
        let title = "Your Stripe payout runway is low — \(text) available and pending"
        return Thing(kind: .reminder, title: IngestSupport.titleLine(title),
                    content: StripeAccount.dashboardURL("balance"),
                    source: StripeWatch.source, capturedAt: .now,
                    tags: ["Runway"],
                    sourceRef: "stripe:runway:low:\(Int(Date.now.timeIntervalSince1970))")
    }
}

// MARK: - Per-account state (not Things)

/// What the bridge knows between refreshes that isn't a Thing: the balance
/// reading. A balance is a STATE (§216) — a ten-minute-old figure is dated, not
/// wrong — so it sits behind a window and updates in place, and it never lands
/// as a row. Wiped on disconnect.
enum StripeState {

    struct Balance: Codable {
        /// currency code → minor units, summed across Stripe's per-currency
        /// buckets.
        var available: [String: Int] = [:]
        var pending: [String: Int] = [:]
        /// When the money already in flight lands, per Stripe's own
        /// `arrival_date` — never computed, never guessed.
        var arrivesAt: Date?
        var fetchedAt: Date?
        /// Whether a silence has already been reported for the outage the
        /// account is currently in, cleared the moment payments resume — one
        /// alert per outage, not per pass. The PostHog `silent` contract, and
        /// a Bool for the same reason: the alert's own day is stamped into its
        /// sourceRef, so a stored "since" would be a field nothing reads.
        var silent: Bool = false
        /// The payout-runway alert's own bucket (2026-08-09, `StripeRunway`)
        /// — the `silent` shape applied to a low balance: one alert per
        /// crossing, cleared the moment the balance recovers.
        var runwayLow: Bool = false
        /// The highest AVAILABLE+PENDING this account has shown since Casberi
        /// started watching it, in MINOR UNITS, per currency — the runway
        /// alert's own high-water mark (`BitrefillBalance.checkLow`'s shape).
        /// Not the account's real historical peak; a reconnect resets it.
        var highCombined: [String: Int] = [:]
    }

    private static let key = "stripe.balance"

    static func balance() -> Balance {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Balance.self, from: data)
        else { return Balance() }
        return decoded
    }

    static func set(_ balance: Balance) {
        guard let data = try? JSONEncoder().encode(balance) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// "£2,140.00 available" — the seat's proof line and the setup screen's one
    /// live figure. Nil when nothing has been read yet, so the UI shows the
    /// connected state without inventing a zero.
    static func availableText() -> String? {
        let available = balance().available.filter { $0.value != 0 }
        guard !available.isEmpty else { return nil }
        return available.sorted { $0.key < $1.key }
            .map { StripeMoney.text($0.value, currency: $0.key) }
            .joined(separator: " · ")
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - The reads

enum StripeFetch {

    /// Why a connect attempt failed, so the screen can say the true thing.
    /// A rejected key, a key that works but is pointed at the sandbox, and an
    /// unreachable network are three different mistakes with three different
    /// fixes — collapsing them into "couldn't connect" is the failure mode the
    /// Privacy.com probe exists to avoid.
    enum Outcome: Equatable {
        case ok(account: String, name: String)
        /// The key is a `*_test_*` one. Refused by design — see the type doc.
        case testKey
        /// 401: Stripe rejected the key outright.
        case rejected
        /// 403: the key is valid but wasn't granted the events read, which is
        /// the one permission this bridge cannot work without.
        case missingScope
        case unreachable
    }

    private static func auth(_ key: String) -> String { "Bearer \(key)" }

    /// The event types this bridge lands, filtered SERVER-side. `/v1/events`
    /// carries every event the account emits — a busy account would spend a
    /// whole page on `charge.succeeded` noise and push the one dispute off the
    /// end. Asking for only these makes a single page a wide window.
    static let watchedTypes = [
        "charge.dispute.created",
        "charge.dispute.closed",
        "payout.paid",
        "payout.failed",
        "customer.subscription.deleted",
        "invoice.payment_failed",
        // The loop-closer, and the ONLY type here that isn't news on its own:
        // every recurring invoice succeeds eventually, so landing all of these
        // would be the charge firehose by another name. It lands only when a
        // FAILURE for the same invoice is already in the corpus — see
        // `Shaped.requiresPrior`.
        "invoice.payment_succeeded",
    ]

    /// The pulse read behind the silence alarm — the last 100 successful
    /// payments, timestamps only. Separate from the event page on purpose:
    /// these never LAND (a charge is a tally, the doctrine's whole point), they
    /// exist solely to answer "is money still arriving at the rate it used to?"
    ///
    /// One request, hard-capped at 100. It costs the same whether the account
    /// takes ten payments a year or ten a minute, and 100 is enough to measure
    /// a rate in either case.
    static func chargePulse(key: String) async -> [Date]? {
        let url = "\(StripeAccount.api)/events?limit=100&types[]=charge.succeeded"
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key))
        guard status == 200, let root = json as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }
        return data.compactMap { date($0["created"]) }
    }

    /// When the money already on its way actually lands. Stripe knows this and
    /// says so (`arrival_date`), and a pending balance without it is a number
    /// you can't plan around — "£2,140" answers how much and leaves when
    /// hanging, which is the half people actually need.
    ///
    /// Reads a handful and takes the soonest still in flight, because the list
    /// is newest-CREATED first and the newest payout is not necessarily the
    /// next to arrive.
    static func nextArrival(key: String) async -> Date? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(StripeAccount.api)/payouts?limit=5", auth: auth(key))
        guard status == 200, let root = json as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }
        return data
            .filter { ["pending", "in_transit"].contains(($0["status"] as? String) ?? "") }
            .compactMap { date($0["arrival_date"]) }
            .min()
    }

    /// A test-mode key, read off the key itself rather than from a response —
    /// so the refusal happens before a single request is made. Stripe spells
    /// both restricted and secret keys with the mode in the prefix
    /// (`rk_test_`, `sk_test_`).
    static func isTestKey(_ key: String) -> Bool {
        key.hasPrefix("rk_test_") || key.hasPrefix("sk_test_")
            || key.hasPrefix("pk_test_")
    }

    /// Validates a pasted key by doing the one read the bridge actually needs
    /// — a single event — rather than by reading the account. A restricted key
    /// may legitimately withhold the account scope while granting events, and
    /// validating on `/v1/account` would reject a key that works perfectly.
    /// The account read follows only to LEARN THE NAME, and its failure is not
    /// an error.
    static func validate(key: String) async -> Outcome {
        guard !isTestKey(key) else { return .testKey }

        let (_, status) = await IngestSupport.getJSONStatus(
            "\(StripeAccount.api)/events?limit=1", auth: auth(key))
        switch status {
        case 200: break
        case 401: return .rejected
        case 403: return .missingScope
        default:  return .unreachable
        }

        let identity = await account(key: key)
        return .ok(account: identity?.id ?? "", name: identity?.name ?? "")
    }

    /// The account's own id and display name. Optional by design: a restricted
    /// key without the account scope still runs this bridge, it just doesn't
    /// get to say whose money it is.
    static func account(key: String) async -> (id: String, name: String)? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(StripeAccount.api)/account", auth: auth(key))
        guard status == 200, let root = json as? [String: Any] else { return nil }
        let id = (root["id"] as? String) ?? ""
        // `settings.dashboard.display_name` is what the merchant themselves
        // chose to be called; `business_profile.name` is the legal-ish one.
        // Prefer the chosen name, the way every other bridge prefers a handle
        // over an id.
        let settings = root["settings"] as? [String: Any]
        let dashboard = settings?["dashboard"] as? [String: Any]
        let profile = root["business_profile"] as? [String: Any]
        let name = (dashboard?["display_name"] as? String)
            ?? (profile?["name"] as? String)
            ?? (root["email"] as? String) ?? ""
        return (id, name)
    }

    /// The account balance, per currency. Stripe returns `available` and
    /// `pending` as ARRAYS of per-currency buckets, not a scalar — an account
    /// taking money in three currencies has three of each, and summing them
    /// into one number would invent an exchange rate nobody quoted.
    static func balance(key: String) async -> StripeState.Balance? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(StripeAccount.api)/balance", auth: auth(key))
        guard status == 200, let root = json as? [String: Any] else { return nil }

        func bucket(_ name: String) -> [String: Int] {
            var totals: [String: Int] = [:]
            for row in (root[name] as? [[String: Any]]) ?? [] {
                guard let currency = row["currency"] as? String else { continue }
                totals[currency, default: 0] += intValue(row["amount"])
            }
            return totals
        }
        var reading = StripeState.Balance()
        reading.available = bucket("available")
        reading.pending = bucket("pending")
        reading.fetchedAt = .now
        return reading
    }

    /// One page of events, newest first, filtered to `watchedTypes`.
    ///
    /// `after` is Stripe's `ending_before` — an event id, and everything
    /// returned is strictly newer than it. `olderThan` is `starting_after`,
    /// which walks DOWN from there: in a newest-first list, "after" means
    /// further along, i.e. older. The pair is what lets `StripeIngest` page
    /// through a backlog without ever re-reading what it has.
    ///
    /// Returns the events, whether Stripe has more behind them, AND whether
    /// the cursor itself was rejected: the event log retains 30 days, so a
    /// cursor from a long-quiet account eventually names an event that no
    /// longer exists and the call 400s. That is recoverable (drop the cursor,
    /// read a fresh page) but only if the caller can tell it apart from a real
    /// failure — hence the flag rather than a bare nil.
    static func events(key: String, after cursor: String, olderThan: String? = nil,
                       limit: Int = 100) async -> (events: [[String: Any]],
                                                   hasMore: Bool, staleCursor: Bool)? {
        var url = "\(StripeAccount.api)/events?limit=\(limit)"
        for type in watchedTypes {
            let encoded = type.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? type
            url += "&types[]=\(encoded)"
        }
        if !cursor.isEmpty { url += "&ending_before=\(cursor)" }
        if let olderThan, !olderThan.isEmpty { url += "&starting_after=\(olderThan)" }

        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key))
        // A 400 with a cursor set is the retention case above. Without a
        // cursor there is nothing to blame it on, so it stays a plain failure.
        if status == 400, !cursor.isEmpty { return ([], false, true) }
        guard status == 200, let root = json as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }
        return (data, (root["has_more"] as? Bool) ?? false, false)
    }

    static func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }

    /// A Stripe unix timestamp — seconds, always, across every object.
    static func date(_ any: Any?) -> Date? {
        let seconds = intValue(any)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}

// MARK: - Shaping an event into a thing

/// The five shapes, each turning one Stripe event into one row. Split out of
/// the sweep so the mapping is readable on its own and testable without a
/// network: every function here is pure — event dictionary in, `Shaped` out.
enum StripeShape {

    struct Shaped {
        var title: String
        var url: String
        var tag: String
        var when: Date
        /// The clock, where the object has one — a dispute's evidence deadline
        /// or an invoice's next retry. Nil for everything that has already
        /// finished happening.
        var dueAt: Date?
        /// The dashboard URL of the EARLIER row this one closes out, when it
        /// closes one. Both halves of a dispute (and both halves of a failed
        /// then recovered payment) name the same object, so the URL is already
        /// the join key — no second field on `Thing`, no id parsing.
        ///
        /// Found → the title gains how long the worry lasted, grounded in the
        /// app's OWN record of when it told you (the Hyperliquid held-duration
        /// rule: never a duration the API didn't give us and we didn't watch).
        var resolves: String?
        /// …and when the earlier row is the only reason this one is news at
        /// all. A dispute closing is news whether or not we saw it open; an
        /// invoice succeeding is news ONLY if we said it failed, because
        /// otherwise it's every recurring payment ever taken.
        var requiresPrior = false
        /// Worth a berry shower. Money arriving, a dispute won, a payment
        /// recovered — never a dispute opening, and never a cancellation.
        var celebrates = false
        /// The outcome as a STABLE, never-localized marker (2026-08-12).
        ///
        /// `tag` says which KIND of money event this is ("Dispute"), and for
        /// three of them that is not enough to know how it went — won and
        /// lost are both "Dispute", a payout that failed and one that paid
        /// are both "Payout". Until now the direction lived only inside the
        /// localized title, which is exactly the trap prd §340 documented for
        /// Cursor: read it back and a device that changed language reports
        /// every past loss as a win.
        ///
        /// So it is landed as a tag, in English, never localized — Cursor's
        /// `facetTag` precedent — which `WorkStage` reads and which doubles
        /// as a §308 facet ("stripe disputes lost").
        var facets: [String] = []
        /// The amount, in the currency's own minor units, and its ISO code —
        /// kept so the row can carry a real number (see `StripeMoney.value`).
        /// Nil for the shapes that name no single amount (churn, silence).
        var amountMinor: Int?
        var currency: String?
    }

    /// The event's payload object. Every Stripe event nests it identically.
    private static func object(_ event: [String: Any]) -> [String: Any] {
        ((event["data"] as? [String: Any])?["object"] as? [String: Any]) ?? [:]
    }

    private static func money(_ payload: [String: Any],
                              amountKey: String = "amount") -> String {
        StripeMoney.text(StripeFetch.intValue(payload[amountKey]),
                         currency: (payload["currency"] as? String) ?? "")
    }

    /// The same two numbers `money` formats, kept raw for `Shaped.amountMinor`
    /// — read from the identical keys so the row's number and its sentence can
    /// never disagree about which amount they mean.
    private static func amount(_ payload: [String: Any],
                               amountKey: String = "amount") -> (Int, String) {
        (StripeFetch.intValue(payload[amountKey]),
         (payload["currency"] as? String) ?? "")
    }

    /// A deadline in words, month and day — never a bare weekday. The Aerodrome
    /// lesson: "respond by Wed" is ambiguous for anything more than a few days
    /// out, and reads as already-past exactly when it matters most.
    private static let deadlineFormat: Date.FormatStyle =
        .dateTime.month(.abbreviated).day()

    static func shape(_ event: [String: Any]) -> Shaped? {
        guard let type = event["type"] as? String else { return nil }
        let payload = object(event)
        let when = StripeFetch.date(event["created"]) ?? .now
        let id = (payload["id"] as? String) ?? ""

        switch type {
        case "charge.dispute.created":
            // The evidence deadline is the whole point of this row. It nests
            // one level down, and if it's missing the row still lands — a
            // dispute you don't know about is worse than one without a clock.
            let details = payload["evidence_details"] as? [String: Any]
            let due = StripeFetch.date(details?["due_by"])
            var title = "Dispute opened · \(money(payload))"
            if let due { title += " — evidence due \(due.formatted(deadlineFormat))" }
            let (minor, code) = amount(payload)
            return Shaped(title: title,
                          url: StripeAccount.dashboardURL("disputes/\(id)"),
                          tag: "Dispute", when: when, dueAt: due,
                          amountMinor: minor, currency: code)

        case "charge.dispute.closed":
            // `status` carries the outcome. "won"/"lost" are the two that mean
            // something; anything else (withdrawn, a Stripe-side close) is
            // reported in Stripe's own word rather than guessed at.
            let status = (payload["status"] as? String) ?? ""
            let verb = switch status {
            case "won":  "Dispute won"
            case "lost": "Dispute lost"
            default:     "Dispute closed"
            }
            let url = StripeAccount.dashboardURL("disputes/\(id)")
            // The direction as a stable marker beside the localized verb —
            // "withdrawn" and any Stripe-side close get NEITHER, so the sheet
            // says the neutral "Dispute opened"'s sibling rather than
            // inventing a win or a loss we were never told about.
            let outcome = switch status {
            case "won":  ["Won"]
            case "lost": ["Lost"]
            default:     [String]()
            }
            let (minor, code) = amount(payload)
            return Shaped(title: "\(verb) · \(money(payload))",
                          url: url,
                          tag: "Dispute", when: when, dueAt: nil,
                          // Enrich-if-found, never required: a dispute closing
                          // is news even if we never saw it open.
                          resolves: url, celebrates: status == "won",
                          facets: outcome, amountMinor: minor, currency: code)

        case "payout.paid":
            let (minor, code) = amount(payload)
            return Shaped(title: "\(money(payload)) paid out to your bank",
                          url: StripeAccount.dashboardURL("payouts/\(id)"),
                          tag: "Payout", when: when, dueAt: nil, celebrates: true,
                          amountMinor: minor, currency: code)

        case "invoice.payment_succeeded":
            // News only as a RECOVERY. Every recurring invoice succeeds, so
            // without `requiresPrior` this is the charge firehose wearing a
            // friendlier name — see `watchedTypes`.
            let url = StripeAccount.dashboardURL("invoices/\(id)")
            let (minor, code) = amount(payload, amountKey: "amount_paid")
            return Shaped(title: "Payment recovered · \(money(payload, amountKey: "amount_paid"))",
                          url: url,
                          tag: "Dunning", when: when, dueAt: nil,
                          resolves: url, requiresPrior: true, celebrates: true,
                          facets: ["Recovered"], amountMinor: minor, currency: code)

        case "payout.failed":
            // Stripe's own failure sentence when it gives one — it names the
            // fix ("account closed", "insufficient funds"), which a generic
            // "payout failed" would throw away.
            let reason = (payload["failure_message"] as? String)
                ?? (payload["failure_code"] as? String)
            var title = "Payout failed · \(money(payload))"
            if let reason, !reason.isEmpty { title += " — \(reason)" }
            let (minor, code) = amount(payload)
            return Shaped(title: title,
                          url: StripeAccount.dashboardURL("payouts/\(id)"),
                          tag: "Payout", when: when, dueAt: nil,
                          facets: ["Failed"], amountMinor: minor, currency: code)

        case "customer.subscription.deleted":
            // The event object is the subscription, which names its customer
            // by ID only — so there is no name to show without a second read
            // per event, and an id is not a name. The plan's own nickname is
            // the one human string already in the payload; without it the row
            // says the plain true thing.
            let items = (payload["items"] as? [String: Any])?["data"] as? [[String: Any]]
            let price = items?.first?["price"] as? [String: Any]
            let nickname = (price?["nickname"] as? String)
                ?? ((payload["plan"] as? [String: Any])?["nickname"] as? String)
            let title = nickname.map { "Subscription canceled · \($0)" }
                ?? "Subscription canceled"
            return Shaped(title: title,
                          url: StripeAccount.dashboardURL("subscriptions/\(id)"),
                          tag: "Churn", when: when, dueAt: nil)

        case "invoice.payment_failed":
            // `amount_due` rather than `amount` — an invoice's `amount` field
            // doesn't exist, and the money at stake is what's still owed.
            let retry = StripeFetch.date(payload["next_payment_attempt"])
            var title = "Payment failed · \(money(payload, amountKey: "amount_due"))"
            if let retry { title += " — retries \(retry.formatted(deadlineFormat))" }
            let (minor, code) = amount(payload, amountKey: "amount_due")
            return Shaped(title: title,
                          url: StripeAccount.dashboardURL("invoices/\(id)"),
                          tag: "Dunning", when: when, dueAt: retry,
                          amountMinor: minor, currency: code)

        default:
            // A type we didn't ask for. Reachable only if Stripe widens what
            // `types[]` matches; dropping it is correct and silent.
            return nil
        }
    }
}

// MARK: - The sweep

enum StripeIngest {

    @MainActor private static var running = false

    /// The most urgent bad news the last pass landed, or nil if it was all
    /// good news (or nothing). Read by `StripeScreen` so a sync the person
    /// asked for answers in the right register: money arriving already rains
    /// via `SourceMoments`, and money being challenged must never rain — it
    /// gets the honest failure tone and says what happened.
    ///
    /// A one-slot mirror of the pass, not a log: the feed holds the history,
    /// this only has to survive from the `await` to the line that reads it.
    @MainActor private(set) static var lastPassAlarm: String?

    /// How stale the balance may be before it's re-read. The §216 split: the
    /// balance is a STATE, the events are EVENTS. Events are read every pass,
    /// unwindowed — a dispute deadline must not wait ten minutes.
    static var balanceWindow: TimeInterval = 600

    /// Reads new events (always) and the balance (behind the window), lands
    /// whatever counts as news, and returns how much did. nil is the honest
    /// "couldn't read" — no key, rejected key, or offline.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard StripeAccount.configured,
              let key = TokenVault.get(TokenBridge.stripe.tokenKey) else { return nil }
        running = true
        defer { running = false }
        // Cleared up front: a pass that lands nothing must not leave the last
        // pass's alarm standing for the screen to re-announce.
        lastPassAlarm = nil

        // The three reads are independent — the event page doesn't wait behind
        // the balance, the pulse doesn't wait behind either, and one failing
        // never invalidates the others.
        let stale = staleBalance()
        async let balanceTask = stale ? StripeFetch.balance(key: key) : nil
        async let arrivalTask = stale ? StripeFetch.nextArrival(key: key) : nil
        async let pulseTask = stale ? StripeFetch.chargePulse(key: key) : nil
        let page = await eventPage(key: key)

        // `silence` in name only by history — it now carries every alert
        // that rides the balance window (the payments-silence alarm AND the
        // payout-runway one below), not just the first.
        var silence: [Thing] = []
        if var reading = await balanceTask {
            reading.arrivesAt = await arrivalTask
            // The silence verdict rides the balance window rather than the
            // event pass: it's a STATE too (an account either is or isn't
            // taking money right now), and it costs a request the events don't.
            reading.silent = StripeState.balance().silent
            // The runway bucket + high-water mark are STATE the same way —
            // carried forward from the persisted reading before this pass's
            // fresh `StripeFetch.balance` (which built a brand-new `Balance()`
            // with neither field set) can overwrite them.
            reading.runwayLow = StripeState.balance().runwayLow
            reading.highCombined = StripeState.balance().highCombined
            let pulse = await pulseTask
            silence = silenceThings(pulse, reading: &reading)
            if let runway = StripeRunway.check(reading: &reading, pulse: pulse) {
                silence.append(runway)
            }
            StripeState.set(reading)
        }

        // The events read failed but the pulse may still have found silence —
        // which is exactly the case worth reporting, since "Stripe is quiet"
        // and "we couldn't reach Stripe" look identical from the feed.
        guard let page else {
            let inserted = insert(silence, context: context)
            lastPassAlarm = inserted.first?.title
            return inserted.isEmpty ? nil : inserted.count
        }

        // What's already landed, keyed by the object each row points at — the
        // lookup behind the loop-closers. One fetch of this bridge's own rows,
        // not one per event being resolved.
        let prior = priorMoments(context: context)

        var landed = silence
        // Refs worth a shower, decided while shaping but FIRED only for the
        // rows that actually turn out to be new. A stale cursor makes the sweep
        // re-read a window it has already seen (by design — that's what makes
        // recovery safe), and re-raining over payouts from last week would be
        // the delight equivalent of crying wolf.
        var celebrating: Set<String> = []
        for event in page {
            // Defensive: a live-mode restricted key only ever sees live events,
            // so this can't normally fire — but pretend money landing beside
            // real money is the one mistake this bridge must not make, and the
            // check costs nothing.
            if let live = event["livemode"] as? Bool, !live { continue }
            guard let id = event["id"] as? String,
                  let shaped = StripeShape.shape(event) else { continue }

            var title = shaped.title
            if let resolves = shaped.resolves {
                let opened = prior[resolves]
                // A recovery with nothing to recover FROM isn't news — it's an
                // ordinary successful payment, and the doctrine says a payment
                // is a tally.
                if shaped.requiresPrior && opened == nil { continue }
                if let opened, let clause = lasted(from: opened, to: shaped.when) {
                    title += " — \(clause)"
                }
            }

            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(title),
                content: shaped.url,
                source: StripeWatch.source,
                capturedAt: shaped.when,
                tags: [shaped.tag] + shaped.facets,
                sourceRef: "stripe:event:\(id)"
            )
            thing.dueAt = shaped.dueAt
            // The amount as a number, not just as characters inside the title
            // (2026-08-12). Both fields or neither: a value with no currency
            // is a bare number the sheet would have to guess a symbol for, and
            // guessing "$" is the §83 fake status in the one domain where
            // believing it is expensive.
            if let minor = shaped.amountMinor, let code = shaped.currency,
               let value = StripeMoney.value(minor, currency: code) {
                thing.priceValue = value
                thing.priceCurrency = code.uppercased()
            }
            landed.append(thing)
            if shaped.celebrates, let ref = thing.sourceRef { celebrating.insert(ref) }
        }
        let inserted = insert(landed, context: context)
        for thing in inserted where celebrating.contains(thing.sourceRef ?? "") {
            SourceMoments.shared.fire(thing.title, source: StripeWatch.source)
        }
        // Newest-first, and silence sorts ahead of everything because it was
        // prepended — so the one line the screen shows is the one that matters
        // most.
        lastPassAlarm = inserted.first { !celebrating.contains($0.sourceRef ?? "") }?.title
        let added = inserted.count

        // The cursor advances only AFTER the rows are safely in the context —
        // moving it first would mean a crash (or a failed save) between the two
        // silently skipped that window forever, and the window in question is
        // money. Advanced even when every event shaped to nil, so a page of
        // types we chose not to land can't be re-read on every pass; and taken
        // from the NEWEST event, which is the page's first element since Stripe
        // orders newest-first.
        if let newest = page.first?["id"] as? String { StripeAccount.cursor = newest }
        return added
    }

    private static func staleBalance() -> Bool {
        guard let fetched = StripeState.balance().fetchedAt else { return true }
        return Date.now.timeIntervalSince(fetched) >= balanceWindow
    }

    /// How many pages of backlog one pass will walk. A page is 100 events of
    /// the six watched types, so five pages is 500 — far past what any real
    /// account produces between foregrounds, and past a 30-day first sight for
    /// all but the largest. It exists as a BOUND, not a target.
    private static let maxPages = 5

    /// Every event newer than the cursor, walking Stripe's pagination, and
    /// recovering from a cursor Stripe has forgotten.
    ///
    /// The walk is the fix for a real gap: one page held 100 events, and the
    /// cursor then jumped to the newest of them — so an account that produced
    /// 101 watched events between two foregrounds would have had the oldest
    /// silently skipped, permanently. For a bridge whose whole subject is
    /// money that would be the worst possible failure, and a quiet one.
    ///
    /// Retention is the other recovery: 30 days, so an account that emits none
    /// of these types for a month holds a cursor that 400s every pass and would
    /// never land anything again. Dropping it and re-reading is the fix, and
    /// the ref-based dedupe in `land` is what makes re-reading safe.
    private static func eventPage(key: String) async -> [[String: Any]]? {
        var cursor = StripeAccount.cursor
        guard var page = await StripeFetch.events(key: key, after: cursor) else { return nil }
        if page.staleCursor {
            cursor = ""
            StripeAccount.cursor = ""
            guard let fresh = await StripeFetch.events(key: key, after: "") else { return nil }
            page = fresh
        }

        var all = page.events
        var pages = 1
        while page.hasMore, pages < maxPages, let oldest = all.last?["id"] as? String {
            guard let next = await StripeFetch.events(key: key, after: cursor,
                                                      olderThan: oldest) else { break }
            guard !next.events.isEmpty else { break }
            all.append(contentsOf: next.events)
            page = next
            pages += 1
        }
        // A backlog deeper than the bound is reported rather than silently
        // truncated (the no-silent-caps rule) — the cursor still advances to
        // the newest, so the remainder is what this pass could not reach.
        if page.hasMore, pages >= maxPages {
            NSLog("[Casberi] stripe: backlog deeper than %d pages — %d read this pass, older events skipped",
                  maxPages, all.count)
        }
        return all
    }

    /// Lands what's new, and hands back exactly what it inserted — the callers
    /// need the rows, not just the count, so a celebration can be tied to a row
    /// that really is new rather than to one the sweep merely re-read.
    ///
    /// Nothing HEALS here, unlike PostHog's annotations: a Stripe event is
    /// immutable and stamped with the moment it happened, and the follow-on
    /// state (a dispute being won) arrives as its OWN event rather than as a
    /// rewrite of the first one. So a known ref is simply skipped.
    @MainActor
    private static func insert(_ incoming: [Thing], context: ModelContext) -> [Thing] {
        let existing = IngestSupport.existingSourceRefs(context, source: StripeWatch.source)
        var added: [Thing] = []
        for item in incoming {
            guard let ref = item.sourceRef, !existing.contains(ref) else { continue }
            context.insert(item)
            SpotlightIndex.index([item])
            added.append(item)
        }
        if !added.isEmpty { context.saveHonestly() }
        return added
    }

    // MARK: The loop-closers

    /// Every object this bridge has already said something about, mapped to
    /// when it FIRST said it — the dashboard URL is the join key, since both
    /// halves of a dispute (and both halves of a failed-then-recovered payment)
    /// point at the same object.
    ///
    /// Earliest wins: once a dispute has both an opened and a closed row, the
    /// opened one is the moment the worry started, which is the only date a
    /// duration can honestly be measured from.
    @MainActor
    private static func priorMoments(context: ModelContext) -> [String: Date] {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stripe" })
        var earliest: [String: Date] = [:]
        for thing in ((try? context.fetch(descriptor)) ?? []) where thing.isLive {
            let url = thing.content
            guard !url.isEmpty else { continue }
            if let seen = earliest[url], seen <= thing.capturedAt { continue }
            earliest[url] = thing.capturedAt
        }
        return earliest
    }

    /// "6 days after it opened" — how long the worry lasted, measured against
    /// the app's OWN record of when it told you, never a duration invented from
    /// a field Stripe didn't send (the Hyperliquid held-duration rule).
    ///
    /// Nil under an hour: a dispute opened and closed inside the same sweep has
    /// no duration worth reporting, and "0 days after it opened" is noise.
    private static func lasted(from opened: Date, to closed: Date) -> String? {
        let seconds = closed.timeIntervalSince(opened)
        guard seconds >= 3600 else { return nil }
        return seconds < 86_400
            ? String(localized: "\(max(1, Int(seconds / 3600))) hour after it opened")
            : String(localized: "\(max(1, Int(seconds / 86_400))) day after it opened")
    }

    // MARK: Silence

    /// "No payments in 14 hours — normally one every 20 minutes."
    ///
    /// Lands at most once per outage and clears itself the moment money starts
    /// arriving again, so a long weekend is one row rather than one per
    /// foreground. `reading` is inout because the flag lives with the balance:
    /// both are readings of the same account, taken in the same windowed pass.
    private static func silenceThings(_ pulse: [Date]?,
                                      reading: inout StripeState.Balance) -> [Thing] {
        // A failed pulse read is not silence — it's not knowing, and the two
        // must never be confused when the answer is "your revenue stopped".
        guard let pulse, let verdict = StripeSilence.verdict(timestamps: pulse, now: .now)
        else { return [] }

        guard verdict.quiet else {
            reading.silent = false
            return []
        }
        guard !reading.silent else { return [] }
        reading.silent = true

        let title = "No payments in \(StripeSilence.sinceText(verdict.since))"
            + " — normally \(StripeSilence.rateText(verdict.typicalGap))"
        return [Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: StripeAccount.dashboardURL("payments"),
            source: StripeWatch.source,
            capturedAt: .now,
            tags: ["Silence"],
            // Stamped with the DAY, so one outage spanning a restart can't land
            // twice, and a genuinely new outage tomorrow still can.
            sourceRef: "stripe:silence:\(dayStamp(.now))"
        )]
    }

    private static let dayStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayStamp(_ date: Date) -> String {
        dayStampFormatter.string(from: date)
    }

    // MARK: Probe

    /// `-stripeProbe YES` — the measure tool for an UNMEASURED API. Connect
    /// first (`-tokenBridge "Stripe:<rk_live_key>"`), then this reads the
    /// STORED key and NSLogs the RAW shapes: HTTP status per endpoint (so 401
    /// wrong-key, 403 missing-scope and 0 unreachable stay distinct), the
    /// resolved account, the balance buckets, the payout-runway crossing
    /// decision (2026-08-09), and one line PER event with the title it would
    /// land wearing.
    ///
    /// One NSLog per line on purpose — a joined multi-line message gets
    /// truncated by the log reader (the `-todayProbe` lesson).
    ///
    /// Reads only; never a write. Running it does NOT advance the cursor, so a
    /// probe can be re-run against the same window as often as needed.
    static func probe() async {
        guard let key = TokenVault.get(TokenBridge.stripe.tokenKey) else {
            NSLog("[Casberi] stripeProbe: no stored key (connect via -tokenBridge \"Stripe:<rk_live_…>\")")
            return
        }
        NSLog("[Casberi] stripeProbe: account=%@ name=%@ cursor=%@",
              StripeAccount.accountID.isEmpty ? "—" : StripeAccount.accountID,
              StripeAccount.accountName.isEmpty ? "—" : StripeAccount.accountName,
              StripeAccount.cursor.isEmpty ? "(none — first sight)" : StripeAccount.cursor)

        if StripeFetch.isTestKey(key) {
            NSLog("[Casberi] stripeProbe: STORED KEY IS TEST MODE — connect refuses these; nothing below is real money")
        }

        let (_, status) = await IngestSupport.getJSONStatus(
            "\(StripeAccount.api)/events?limit=1", auth: "Bearer \(key)")
        NSLog("[Casberi] stripeProbe events endpoint: HTTP %d (401 wrong key · 403 missing scope · 0 unreachable)", status)

        if let identity = await StripeFetch.account(key: key) {
            NSLog("[Casberi] stripeProbe account: %@ · %@", identity.id, identity.name.isEmpty ? "—" : identity.name)
        } else {
            NSLog("[Casberi] stripeProbe account: UNREADABLE (the account scope is optional — events still work)")
        }

        if var reading = await StripeFetch.balance(key: key) {
            NSLog("[Casberi] stripeProbe balance available: %@",
                  reading.available.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ") )
            NSLog("[Casberi] stripeProbe balance pending: %@",
                  reading.pending.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ") )
            // The runway crossing decision, over the STORED bucket/high-water
            // mark (so re-running this probe doesn't reset history) — does
            // NOT persist the result, so a probe run can't itself land a
            // duplicate alert the real sweep would also want to land.
            reading.runwayLow = StripeState.balance().runwayLow
            reading.highCombined = StripeState.balance().highCombined
            let pulse = await StripeFetch.chargePulse(key: key)
            let activity = pulse.flatMap { StripeSilence.verdict(timestamps: $0, now: .now) }
            NSLog("[Casberi] stripeProbe runway: activityGate=%@ (needs %d+ recent charges, not dormant)",
                  activity != nil ? "PASS" : "no charge history yet — runway stays silent",
                  StripeSilence.minCharges)
            if let runway = StripeRunway.check(reading: &reading, pulse: pulse) {
                NSLog("[Casberi] stripeProbe runway: WOULD LAND → %@", runway.title)
            } else {
                NSLog("[Casberi] stripeProbe runway: nothing to land (no activity yet, not low, or already alerted) high=%@",
                      reading.highCombined.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
            }
        } else {
            NSLog("[Casberi] stripeProbe balance: UNREADABLE")
        }

        guard let page = await StripeFetch.events(key: key, after: StripeAccount.cursor) else {
            NSLog("[Casberi] stripeProbe events: UNREADABLE")
            return
        }
        NSLog("[Casberi] stripeProbe events: %d in this page%@%@",
              page.events.count,
              page.hasMore ? " (MORE behind it — the sweep pages through)" : "",
              page.staleCursor ? " (CURSOR STALE — past Stripe's 30-day retention)" : "")
        for event in page.events {
            let type = (event["type"] as? String) ?? "?"
            guard let shaped = StripeShape.shape(event) else {
                NSLog("[Casberi] stripeEvent| %@ → UNSHAPED", type)
                continue
            }
            NSLog("[Casberi] stripeEvent| %@ → %@ [%@]%@", type, shaped.title, shaped.tag,
                  shaped.dueAt.map { " due=\(ISO8601DateFormatter().string(from: $0))" } ?? "")
        }
    }
}

// MARK: - The seat

enum StripeWatch {

    static let source = "Stripe"

    /// The seat rule, owned in one place: connected while a key exists. Unlike
    /// PostHog there is no watch list to also require — Stripe has one account
    /// and the events arrive whether or not you've picked anything, so a key
    /// alone is a bridge that really reads something.
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard StripeAccount.configured else {
            store.remove(TokenBridge.stripe.bridgeID)
            return
        }
        let name = StripeAccount.accountName
        let balance = StripeState.availableText()
        let proof = [name.isEmpty ? nil : name, balance.map { String(localized: "\($0) available") }]
            .compactMap { $0 }.joined(separator: " · ")
        store.registerConnected(
            id: TokenBridge.stripe.bridgeID, name: source,
            proof: proof.isEmpty ? String(localized: "Connected") : proof,
            // The read-only promise has ONE home (`TokenBridge.canLine`), the
            // PostHog contract — a second copy here would be the only reader of
            // a string nothing else renders, and the two would drift.
            can: [TokenBridge.stripe.canLine])
    }
}
