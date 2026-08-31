import Foundation
import SwiftData

/// Polar (2026-08-30) — a Merchant-of-Record billing platform built for
/// developers, the seat GitHub/Vercel/Cursor's own audience increasingly bills
/// through (indie SaaS, open-source maintainers, digital products). Grouped
/// **Work**, deliberately NOT Wallet — see the note on `DodoPaymentsAccount`,
/// added the same day: that bridge lands EVERY payment because its own
/// doctrine is "money in reach reads like card spending", while this one
/// follows `StripeBridge`'s doctrine exactly (below). The group follows the
/// BEHAVIOR, not the category: a bridge that lands every transaction is
/// Wallet, a bridge that alarms rarely is Work, and this is built to be the
/// second kind.
///
/// **The doctrine, inherited whole from Stripe.** A count is exactly what the
/// module doctrine forbids a thing to be, and an individual order is a tally
/// wearing a currency symbol. So no order, payment or subscription renewal
/// ever lands just for succeeding — only money whose MOVEMENT is itself the
/// news:
///
///   1. **A dispute opened.** Polar has no dedicated disputes endpoint — a
///      chargeback arrives nested on the refund it produced
///      (`Refund.dispute`), but the SHAPE is Stripe's exactly: a status, an
///      evidence deadline (`evidence_due_by`), a resolution. It lands as a
///      reconciling `dueAt` the same way.
///   2. **A dispute closed.** Won or lost. The loop-closer for (1).
///   3. **A refund succeeded or failed.** Money actually leaving — Stripe's
///      payout analog. (Polar's own payout-to-your-bank schedule is not a
///      readable resource — see `PolarFetch`'s doc.)
///   4. **A subscription enters a bad state**
///      (past_due/canceled/unpaid/incomplete_expired) **or recovers from
///      one.** Churn and dunning in one pair, since Polar's richer status
///      enum (eight states against Stripe's binary
///      canceled/payment-failed) collapses naturally into "healthy" and
///      "not", and the interesting news is crossing that line in either
///      direction.
///
/// **Deliberately NOT built, unlike Stripe: the payments-silence alarm and
/// the payout-runway alert.** Both are real, dated ADDITIONS Stripe earned
/// over two separate sessions (§250, then 2026-08-09) — not core to landing a
/// room at all. Building four solid shapes beats a sloppier six; either can
/// follow the exact precedent here if this bridge earns it later.
///
/// **Read-only STRUCTURALLY, Stripe's/PostHog's grade — not Dodo's SCOPED
/// box.** Polar's Organization Access Tokens carry real PER-RESOURCE scopes,
/// and this bridge needs exactly three: `refunds:read`, `subscriptions:read`,
/// and `organizations:read` (a nicety — see `validate`). A token minted with
/// only those three physically cannot issue a refund, cancel a subscription,
/// or create a product, whatever this file does — no `orders:read` at all,
/// since no order is ever read (see `PolarIngest.refresh`).
///
/// **No test-mode key to refuse, and that is a STRONGER guarantee than
/// Stripe's prefix check, not a missing one.** Stripe's `rk_test_`/`sk_test_`
/// keys authenticate against the SAME host as live keys and return sandbox
/// data with no visible difference — so this app has to refuse them by
/// reading the prefix. Polar's sandbox is a WHOLLY SEPARATE HOST
/// (`sandbox-api.polar.sh`) with its own token namespace; a sandbox token
/// simply 401s against `api.polar.sh` (per Polar's own docs: "access tokens
/// obtained in Production are not usable in the Sandbox environment"). So the
/// host boundary already does what Stripe's prefix check exists to do, and
/// there is no `PolarFetch.isTestKey` here on purpose — see `validate`.
///
/// **The status code alone still can't tell "malformed" from "sandbox" from
/// "revoked" apart, but Polar's error BODY usually can (2026-08-31).**
/// `IngestSupport.getJSONStatus` drops the response body on any non-200,
/// which made a 401 undiagnosable from either side of the screen — the app
/// could only ever show the generic hedge above, and there was no way for
/// anyone (developer included) to see what Polar actually said. `validate`
/// now reads through `getJSONBody` (`postJSONBody`'s GET analog) and
/// `PolarFetch.errorDetail` pulls Polar's own reason string out of the body
/// when one is present, which the setup screen appends to the generic
/// message. Best-effort, not confirmed against a live rejection — see the
/// UNMEASURED paragraph below.
///
/// **MEASURED against a live account (2026-08-31), and it found a real bug
/// on the first run: every collection endpoint here needs its TRAILING
/// SLASH.** `GET /v1/refunds?limit=1` 307-redirects to `/v1/refunds/?limit=1`
/// (Polar is built on FastAPI, whose router 307s on a trailing-slash
/// mismatch by default) — and `IngestSupport`'s shared session, which has no
/// redirect delegate, follows that redirect the way `URLSession` always
/// does: by building a fresh request that DROPS the `Authorization` header,
/// even though the redirect stays on the same host. The result is a plain,
/// unauthenticated request that Polar correctly answers `401 Unauthorized`
/// — indistinguishable, from the outside, from a genuinely bad token. A
/// perfectly good Production key with every scope checked reproduced this
/// exactly; adding the trailing slash to every collection URL below (never
/// needed on `/refunds/{id}`, which doesn't redirect) took the same request
/// to `200`. Caught by comparing the app's own network read against a raw
/// `curl` of the identical URL — `curl` reproduces the same silent drop on
/// redirect, so the tell was the bare 307 on the FIRST hop, not anything
/// `curl -L` or the app showed after following it. One guess remains
/// unconfirmed and named so a probe run can catch it: whether Metrics'
/// `monthly_recurring_revenue` is minor-unit cents (this file's assumption,
/// matching Order's own amount fields) or already a major-unit decimal. Run
/// `-polarProbe YES` against a real key and reconcile it.
enum PolarAccount {

    /// Polar is single-tenant per key, Stripe's exact shape — one account, no
    /// host field, no project picker.
    private static let orgNameKey = "polar.orgName"
    private static let orgSlugKey = "polar.orgSlug"

    static let api = "https://api.polar.sh/v1"

    /// The organization's display name, read off `/v1/organizations` — empty
    /// when unread, which degrades to the plain seat name rather than
    /// blocking connect (Stripe's "the scope is a nicety" rule).
    static var orgName: String {
        get { UserDefaults.standard.string(forKey: orgNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: orgNameKey) }
    }

    /// The org's dashboard slug, for building a real deep link rather than
    /// always landing on the dashboard root (Dodo Payments'/Privacy.com's
    /// fallback for the identical reason: no per-object URL is documented).
    static var orgSlug: String {
        get { UserDefaults.standard.string(forKey: orgSlugKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: orgSlugKey) }
    }

    static var configured: Bool {
        TokenVault.get(TokenBridge.polar.tokenKey) != nil
    }

    /// A dashboard path under the org's own slug, or the bare root when the
    /// slug hasn't been read yet — never a link that 404s. `path` carries a
    /// LEADING slash, e.g. "/sales".
    static func dashboardURL(_ path: String = "") -> String {
        guard !orgSlug.isEmpty else { return "https://polar.sh/dashboard" }
        return "https://polar.sh/dashboard/\(orgSlug)\(path)"
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: orgNameKey)
        UserDefaults.standard.removeObject(forKey: orgSlugKey)
        PolarState.clear()
        PolarAccount.clearTracked()
    }

    // MARK: - Tracked status maps (Dodo Payments' exact shape)

    /// Disputes and subscriptions MUTATE with no event log to follow, so a
    /// diff against a locally kept `id → last-known status` map is how this
    /// file notices a transition — `DodoPaymentsAccount.TrackedItem`'s
    /// reasoning, unchanged.
    struct TrackedItem: Codable {
        var status: String
        var firstSeenAt: Date
        var createdAt: Date?
    }

    private static func trackedKey(_ name: String) -> String { "polar.tracked.\(name)" }

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

    static func clearTracked() {
        UserDefaults.standard.removeObject(forKey: trackedKey("disputes"))
        UserDefaults.standard.removeObject(forKey: trackedKey("subscriptions"))
    }
}

// MARK: - Per-account state (not Things)

/// The MRR + active-subscriber reading — a STATE (§216), not an event, so it
/// sits behind a freshness window and updates in place. Stripe's
/// `StripeState.Balance` shape, with a revenue reading in place of a cash
/// balance: Polar is a subscription-first platform, so "how much recurring
/// revenue is live right now" is the figure that means what a bank balance
/// means on Stripe's card.
enum PolarState {

    struct Reading: Codable {
        /// Minor units, in `currency` — see the type doc's second UNMEASURED
        /// guess.
        var mrrMinor: Int?
        var currency: String = "USD"
        var activeSubscriptions: Int?
        var fetchedAt: Date?
    }

    private static let key = "polar.reading"

    static func reading() -> Reading {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Reading.self, from: data)
        else { return Reading() }
        return decoded
    }

    static func set(_ reading: Reading) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// "$482.00" — nil when never read, which must never render as zero
    /// (Stripe's `availableText` rule).
    static func mrrText() -> String? {
        let r = reading()
        guard let minor = r.mrrMinor else { return nil }
        return StripeMoney.text(minor, currency: r.currency)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - The reads

enum PolarFetch {

    /// Read-only by SCOPE (see the type doc) — this file issues GET only, on
    /// the four endpoints below, as defense in depth. Do not add a write verb.
    private static func auth(_ key: String) -> String { "Bearer \(key)" }

    enum Outcome: Equatable {
        case ok(orgID: String, name: String, slug: String)
        /// 401: a sandbox token against the production host, or a plain
        /// rejection — Polar's own isolation makes these the same failure
        /// AT THE STATUS-CODE LEVEL (see the type doc), but the response
        /// BODY usually names which one. `detail` carries that reason,
        /// straight from Polar's own words, when the body decodes to one —
        /// nil only when it doesn't (an empty body, an unrecognized shape),
        /// in which case the UI falls back to the old generic hedge.
        case rejected(detail: String?)
        /// 403: the token is valid but missing a scope this bridge needs.
        case missingScope(detail: String?)
        case unreachable
    }

    /// Is this pasted string the SAME token twice, with no separator?
    /// (2026-08-31 — the actual cause behind the first "Polar didn't accept
    /// that token" report, measured: a stored key of 106 characters that was
    /// one 53-character token concatenated with itself.)
    ///
    /// A double paste is invisible in a `secure: true` field — the dots just
    /// look long — and it produces a plain 401 whose message then sends
    /// somebody hunting for a Sandbox/Production mixup they never made. It is
    /// worth catching BEFORE the request, because the app can say exactly what
    /// happened where Polar can only say "Unauthorized".
    ///
    /// **Deliberately shape-independent — no prefix rule.** `TokenBridge`'s
    /// own `.cursor` placeholder comment states the reason: a check built on
    /// one observed token shape reads as a validation rule and would have
    /// someone believing a perfectly good key is the wrong one the day Polar
    /// mints a different prefix. This asks only whether the string is its own
    /// first half twice, which no real single token can be, and which stays
    /// true whatever Polar's tokens come to look like. It generalizes to every
    /// keyed bridge here; wired to Polar alone for now because Polar is where
    /// it was measured.
    static func isDoubled(_ token: String) -> Bool {
        let count = token.count
        guard count >= 2, count.isMultiple(of: 2) else { return false }
        let half = token.index(token.startIndex, offsetBy: count / 2)
        return token[token.startIndex..<half] == token[half...]
    }

    /// Reads a Polar error body's reason, trying every field name this API's
    /// public docs and its `polar-js` SDK error types show — UNMEASURED
    /// against a live rejection (this bridge's whole type doc), so this is a
    /// best-effort net rather than a confirmed single key. `detail` can be a
    /// STRING (FastAPI's own shape, which Polar is built on) or an ARRAY of
    /// validation-error objects (FastAPI's 422 shape); only the string form
    /// is surfaced; nil otherwise rather than guessing at a stitched-together
    /// summary of the array form.
    static func errorDetail(_ json: Any?) -> String? {
        guard let root = json as? [String: Any] else { return nil }
        for key in ["detail", "error_description", "message", "error"] {
            if let s = root[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    /// Validates a pasted token by reading Refunds — one of the two
    /// resources this bridge actually needs (Stripe's "validate on the read
    /// you actually need" rule; a token might withhold `organizations:read`
    /// while granting everything else, so validating on that would reject a
    /// perfectly good token). The organization read follows only to LEARN
    /// THE NAME AND SLUG, and its failure is not an error.
    static func validate(key: String) async -> Outcome {
        let (json, status) = await IngestSupport.getJSONBody(
            "\(PolarAccount.api)/refunds/?limit=1", auth: auth(key))
        switch status {
        case 200: break
        case 401: return .rejected(detail: errorDetail(json))
        case 403: return .missingScope(detail: errorDetail(json))
        default:  return .unreachable
        }
        let org = await organization(key: key)
        return .ok(orgID: org?.id ?? "", name: org?.name ?? "", slug: org?.slug ?? "")
    }

    /// The organization's own id, name and dashboard slug. An org-scoped
    /// token's `/v1/organizations` list holds exactly one entry — its own —
    /// per Polar's docs.
    static func organization(key: String) async -> (id: String, name: String, slug: String)? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(PolarAccount.api)/organizations/?limit=1", auth: auth(key))
        guard status == 200, let root = json as? [String: Any],
              let items = root["items"] as? [[String: Any]], let org = items.first
        else { return nil }
        return ((org["id"] as? String) ?? "",
                (org["name"] as? String) ?? "",
                (org["slug"] as? String) ?? "")
    }

    /// The MRR + active-subscriber reading, over TODAY alone — `totals` is
    /// the range's aggregate rather than a per-day series, so a one-day range
    /// is the CURRENT snapshot rather than a sum across days (which would
    /// double an MRR figure that is already a point-in-time reading, not a
    /// flow).
    static func metrics(key: String) async -> PolarState.Reading? {
        let day = ISO8601DateFormatter.polarDay.string(from: .now)
        let url = "\(PolarAccount.api)/metrics/?start_date=\(day)&end_date=\(day)&interval=day"
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key))
        guard status == 200, let root = json as? [String: Any],
              let totals = root["totals"] as? [String: Any] else { return nil }
        var reading = PolarState.Reading()
        if let mrr = totals["monthly_recurring_revenue"] {
            reading.mrrMinor = PolarShape.intValue(mrr)
        }
        if let active = totals["active_subscriptions"] {
            reading.activeSubscriptions = PolarShape.intValue(active)
        }
        // Never confirmed on the wire (the type doc's second UNMEASURED
        // guess) — every currency-bearing object elsewhere in this API
        // carries its OWN `currency` field, and Metrics carries none, so
        // "USD" is a default rather than a read.
        reading.currency = "USD"
        reading.fetchedAt = .now
        return reading
    }

    /// One page of a list endpoint, `items`/`pagination` envelope (Polar's
    /// documented shape, distinct from Dodo's `items`-only one).
    static func envelope(_ url: String, key: String) async -> (items: [[String: Any]], status: Int) {
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key))
        let items = (json as? [String: Any])?["items"] as? [[String: Any]]
        return (items ?? [], status)
    }

    /// Refunds, newest first — walked page by page, stopping as soon as a
    /// FULL page contains nothing new. That early exit is sound because the
    /// sort is strictly `-created_at`: once a page is entirely refs this
    /// bridge already knows, every refund behind it is older still and
    /// therefore known too. `knownRefs` is asked fresh per page rather than
    /// once, so a burst deeper than one page is still walked correctly.
    /// `dispute` rides the SAME row (Polar has no separate disputes
    /// endpoint — see the type doc), so this is also the only read that can
    /// ever see one.
    static func refunds(key: String, knownRefs: () -> Set<String>) async -> [[String: Any]]? {
        await walk(resource: "refunds", key: key, sortField: "created_at", knownRefs: knownRefs) { row in
            (row["id"] as? String).map { "polar:refund:\($0)" }
        }
    }

    /// How many pages one pass will walk, Stripe's bound-not-target rule: a
    /// page is 100 rows, so three pages is 300 — far past what a single
    /// foreground pass needs to catch up on for the audience this bridge
    /// targets, and a deeper backlog is REPORTED rather than silently
    /// truncated (see the NSLog below).
    private static let maxPages = 3

    private static func walk(resource: String, key: String, sortField: String,
                             knownRefs: () -> Set<String>,
                             ref: @escaping ([String: Any]) -> String?) async -> [[String: Any]]? {
        var all: [[String: Any]] = []
        var page = 1
        while page <= maxPages {
            let url = "\(PolarAccount.api)/\(resource)/?sorting=-\(sortField)&limit=100&page=\(page)"
            let (items, status) = await envelope(url, key: key)
            guard status == 200 else { return page == 1 ? nil : all }
            all.append(contentsOf: items)
            let known = knownRefs()
            let sawNew = items.contains { ref($0).map { !known.contains($0) } ?? true }
            guard sawNew, items.count == 100 else { break }
            page += 1
        }
        if page > maxPages {
            NSLog("[Casberi] polar: %@ backlog deeper than %d pages this pass — older rows wait for next pass",
                  resource, maxPages)
        }
        return all
    }

    /// A single refund, by id — used to re-check a TRACKED disputed refund
    /// that may have scrolled out of the newest-page window (see
    /// `PolarIngest.diffDisputes`), rather than trusting the page walk alone
    /// to ever see its resolution again.
    static func refund(id: String, key: String) async -> [String: Any]? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(PolarAccount.api)/refunds/\(id)", auth: auth(key))
        guard status == 200 else { return nil }
        return json as? [String: Any]
    }

    /// Subscriptions filtered SERVER-SIDE to the unhealthy statuses —
    /// Stripe's `types[]` trick applied to a `status[]` filter: reading only
    /// these means a page never needs to hold every ACTIVE subscriber to
    /// find the handful that need attention.
    static let unhealthyStatuses = ["past_due", "canceled", "unpaid", "incomplete_expired"]

    static func unhealthySubscriptions(key: String) async -> [[String: Any]]? {
        var url = "\(PolarAccount.api)/subscriptions/?sorting=-started_at&limit=100"
        for status in unhealthyStatuses { url += "&status[]=\(status)" }
        let (items, status) = await envelope(url, key: key)
        return status == 200 ? items : nil
    }

    static func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }
}

private extension ISO8601DateFormatter {
    /// `YYYY-MM-DD` for the metrics endpoint's `start_date`/`end_date`, which
    /// documents an `RFCDate` (a bare date, no time) rather than a full
    /// timestamp — a plain `ISO8601DateFormatter` would append one and 400.
    static let polarDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Shaping a payload into a thing

enum PolarShape {

    struct Shaped {
        var title: String
        var url: String
        var tag: String
        var facets: [String] = []
        var when: Date
        var dueAt: Date?
        /// The dashboard URL of the earlier row this one closes out — a
        /// dispute's opened↔closed pair, Stripe's exact join key.
        var resolves: String?
        var requiresPrior = false
        var amountMinor: Int?
        var currency: String?
    }

    static func intValue(_ any: Any?) -> Int { PolarFetch.intValue(any) }

    /// Polar's timestamps are ISO 8601 strings (unlike Stripe's unix
    /// seconds) — Dodo Payments' exact reader.
    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return ISO8601DateFormatter().date(from: s) ?? IngestSupport.isoDate(s)
    }

    private static func money(_ minor: Int, currency: String) -> String {
        StripeMoney.text(minor, currency: currency)
    }

    private static let deadlineFormat: Date.FormatStyle =
        .dateTime.month(.abbreviated).day()

    // MARK: Disputes (nested on a refund)

    static func disputeOpened(_ dispute: [String: Any]) -> Shaped? {
        guard let id = dispute["id"] as? String, !id.isEmpty else { return nil }
        _ = id // existence check only — the sourceRef is keyed by the refund id
        let minor = intValue(dispute["amount"])
        let currency = (dispute["currency"] as? String) ?? ""
        let due = date(dispute["evidence_due_by"])
        var title = "Dispute opened" + (currency.isEmpty ? "" : " · \(money(minor, currency: currency))")
        if let due { title += " — evidence due \(due.formatted(deadlineFormat))" }
        return Shaped(title: title,
                      url: PolarAccount.dashboardURL("/finance/refunds"),
                      tag: "Dispute", facets: ["Opened"],
                      when: date(dispute["created_at"]) ?? .now, dueAt: due,
                      amountMinor: currency.isEmpty ? nil : minor,
                      currency: currency.isEmpty ? nil : currency.uppercased())
    }

    static func disputeClosed(_ dispute: [String: Any], openedAt: Date?) -> Shaped? {
        guard let id = dispute["id"] as? String, !id.isEmpty else { return nil }
        _ = id // existence check only — the sourceRef is keyed by the refund id
        let status = (dispute["status"] as? String) ?? ""
        let verb: String
        let facet: String
        switch status {
        case "won":  verb = "Dispute won";  facet = "Won"
        case "lost": verb = "Dispute lost"; facet = "Lost"
        default:     verb = "Dispute closed"; facet = "Closed"
        }
        let minor = intValue(dispute["amount"])
        let currency = (dispute["currency"] as? String) ?? ""
        let url = PolarAccount.dashboardURL("/finance/refunds")
        let when = date(dispute["created_at"]) ?? .now
        var title = verb + (currency.isEmpty ? "" : " · \(money(minor, currency: currency))")
        if let openedAt, let clause = lasted(from: openedAt, to: when) { title += " — \(clause)" }
        return Shaped(title: title, url: url, tag: "Dispute", facets: [facet], when: when,
                      resolves: url,
                      amountMinor: currency.isEmpty ? nil : minor,
                      currency: currency.isEmpty ? nil : currency.uppercased())
    }

    // MARK: Refunds

    static func refund(_ row: [String: Any]) -> Shaped? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        _ = id // existence check only — the sourceRef is built by the caller
        let status = (row["status"] as? String) ?? ""
        guard status == "succeeded" || status == "failed" else { return nil }
        let minor = intValue(row["amount"])
        let currency = (row["currency"] as? String) ?? ""
        var title = status == "failed" ? "Refund failed" : "Refund"
        if !currency.isEmpty { title += " · \(money(minor, currency: currency))" }
        if let reason = row["reason"] as? String, !reason.isEmpty, reason != "customer_request" {
            title += " — \(reason.replacingOccurrences(of: "_", with: " "))"
        }
        return Shaped(title: title,
                      url: PolarAccount.dashboardURL("/finance/refunds"),
                      tag: "Refund",
                      facets: status == "failed" ? ["Failed"] : [],
                      when: date(row["created_at"]) ?? .now,
                      amountMinor: currency.isEmpty ? nil : minor,
                      currency: currency.isEmpty ? nil : currency.uppercased())
    }

    // MARK: Subscriptions

    static func subscriptionAlarm(_ row: [String: Any]) -> Shaped? {
        let status = (row["status"] as? String) ?? ""
        let verb: String
        let facet: String
        switch status {
        case "past_due":           verb = "Subscription payment failed"; facet = "PastDue"
        case "canceled":           verb = "Subscription canceled";       facet = "Cancelled"
        case "unpaid":             verb = "Subscription unpaid";         facet = "Unpaid"
        case "incomplete_expired": verb = "Subscription never started";  facet = "Expired"
        default: return nil
        }
        let product = row["product"] as? [String: Any]
        let name = (product?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = name.map { "\(verb) · \($0)" } ?? verb
        return Shaped(title: title,
                      url: PolarAccount.dashboardURL("/subscriptions"),
                      tag: "Subscription", facets: [facet], when: .now)
    }

    /// "Subscription recovered · Pro plan" — the loop-closer for a tracked
    /// subscription that has simply stopped appearing in the unhealthy-status
    /// query, which can only mean it moved to a healthy status (active/
    /// trialing) — see `PolarIngest.diffSubscriptions`.
    static func subscriptionRecovered(productName: String?) -> Shaped {
        let title = productName.map { "Subscription recovered · \($0)" } ?? "Subscription recovered"
        return Shaped(title: title, url: PolarAccount.dashboardURL("/subscriptions"),
                      tag: "Subscription", facets: ["Recovered"], when: .now)
    }

    /// "6 days after it opened" — Stripe's held-duration rule, measured
    /// against this app's own record of when it first said so.
    private static func lasted(from opened: Date, to closed: Date) -> String? {
        let seconds = closed.timeIntervalSince(opened)
        guard seconds >= 3600 else { return nil }
        return seconds < 86_400
            ? String(localized: "\(max(1, Int(seconds / 3600))) hour after it opened")
            : String(localized: "\(max(1, Int(seconds / 86_400))) day after it opened")
    }
}

// MARK: - The sweep

enum PolarIngest {

    @MainActor private static var running = false

    /// Reads refunds (their own news, and disputes nest on them) and
    /// unhealthy subscriptions, lands what counts as news, and returns how
    /// much did. nil is the honest "couldn't read". No individual order is
    /// ever read for landing — the doctrine's whole point.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard PolarAccount.configured,
              let key = TokenVault.get(TokenBridge.polar.tokenKey) else { return nil }
        running = true
        defer { running = false }

        let existingRefs = { IngestSupport.existingSourceRefs(context, source: PolarWatch.source) }

        let stale = staleReading()
        async let metricsTask = stale ? PolarFetch.metrics(key: key) : nil
        async let refundsTask = PolarFetch.refunds(key: key, knownRefs: existingRefs)
        async let subsTask = PolarFetch.unhealthySubscriptions(key: key)

        if let reading = await metricsTask { PolarState.set(reading) }

        let refunds = await refundsTask
        let subs = await subsTask

        // Every read failing at once is "couldn't connect"; any one
        // succeeding means the key works and this pass has real news.
        guard refunds != nil || subs != nil else { return nil }

        var landed: [Thing] = []
        if let refunds { landed.append(contentsOf: shapeRefunds(refunds)) }
        landed.append(contentsOf: await diffDisputes(refunds ?? [], key: key))
        if let subs { landed.append(contentsOf: diffSubscriptions(subs)) }

        return insert(landed, context: context)
    }

    private static func staleReading() -> Bool {
        guard let fetched = PolarState.reading().fetchedAt else { return true }
        return Date.now.timeIntervalSince(fetched) >= 600
    }

    private static func shapeRefunds(_ rows: [[String: Any]]) -> [Thing] {
        rows.compactMap { row -> Thing? in
            guard let id = row["id"] as? String, let shaped = PolarShape.refund(row) else { return nil }
            return thing(shaped, sourceRef: "polar:refund:\(id)")
        }
    }

    /// Diffs every dispute seen on the newest refunds page against the
    /// locally tracked status map, landing "opened" or "closed" only on a
    /// real transition — Dodo Payments' diff shape, applied to a dispute
    /// nested on a refund rather than its own resource.
    ///
    /// A disputed refund that has scrolled out of the page window (buried by
    /// refund volume since it was first tracked) is re-checked by ID
    /// directly, one request per still-open tracked dispute — bounded by how
    /// many disputes can possibly be open at once, which for the accounts
    /// this bridge targets is small. Without this, a dispute could vanish
    /// from view mid-resolution and its "won"/"lost" row would never land.
    private static func diffDisputes(_ freshRefunds: [[String: Any]], key: String) async -> [Thing] {
        var tracked = PolarAccount.tracked("disputes")
        var landed: [Thing] = []
        let terminal: Set<String> = ["won", "lost"]

        var seenDisputes: [(dispute: [String: Any], refundID: String)] = []
        for row in freshRefunds {
            guard let dispute = row["dispute"] as? [String: Any],
                  let refundID = row["id"] as? String else { continue }
            seenDisputes.append((dispute, refundID))
        }
        // Every OTHER tracked dispute not yet terminal gets re-read by id,
        // so a resolution can never be missed just because newer refunds
        // pushed it off the page.
        for (refundID, item) in tracked where !terminal.contains(item.status) {
            guard !seenDisputes.contains(where: { $0.refundID == refundID }) else { continue }
            guard let row = await PolarFetch.refund(id: refundID, key: key),
                  let dispute = row["dispute"] as? [String: Any] else { continue }
            seenDisputes.append((dispute, refundID))
        }

        for (dispute, refundID) in seenDisputes {
            let status = (dispute["status"] as? String) ?? ""
            let createdAt = PolarShape.date(dispute["created_at"])

            if let known = tracked[refundID] {
                guard known.status != status else { continue }
                if terminal.contains(status),
                   let shaped = PolarShape.disputeClosed(dispute, openedAt: known.createdAt ?? known.firstSeenAt) {
                    landed.append(thing(shaped, sourceRef: "polar:dispute:\(refundID):closed"))
                }
                tracked[refundID] = PolarAccount.TrackedItem(
                    status: status, firstSeenAt: known.firstSeenAt, createdAt: known.createdAt)
            } else {
                // First sighting. Alarm only if genuinely fresh — an older
                // dispute already open when this bridge connects is a
                // backfill, not news (Dodo Payments' identical rule).
                let recent = createdAt.map { Date.now.timeIntervalSince($0) < 86_400 } ?? false
                if !terminal.contains(status), recent,
                   let shaped = PolarShape.disputeOpened(dispute) {
                    landed.append(thing(shaped, sourceRef: "polar:dispute:\(refundID):opened"))
                }
                tracked[refundID] = PolarAccount.TrackedItem(
                    status: status, firstSeenAt: .now, createdAt: createdAt)
            }
        }
        PolarAccount.setTracked("disputes", tracked)
        return landed
    }

    /// The subscription diff — first sighting seeds silently, a transition
    /// between two DIFFERENT unhealthy statuses lands as its own alarm
    /// (stamped with the status, so re-entering the same one later lands
    /// again), and a tracked id that simply stops appearing in THIS pass's
    /// unhealthy-filtered results can only mean it moved to a healthy status
    /// — the loop-closer, landed as a recovery.
    private static func diffSubscriptions(_ rows: [[String: Any]]) -> [Thing] {
        var tracked = PolarAccount.tracked("subscriptions")
        var landed: [Thing] = []
        var seen: Set<String> = []

        for row in rows {
            // A Subscription's own `id`, not an Order's `subscription_id`
            // (the field this list's rows do NOT carry).
            guard let id = row["id"] as? String, !id.isEmpty else { continue }
            seen.insert(id)
            let status = (row["status"] as? String) ?? ""
            defer {
                tracked[id] = PolarAccount.TrackedItem(
                    status: status, firstSeenAt: tracked[id]?.firstSeenAt ?? .now, createdAt: nil)
            }
            guard let known = tracked[id], known.status != status else { continue }
            guard let shaped = PolarShape.subscriptionAlarm(row) else { continue }
            landed.append(thing(shaped, sourceRef: "polar:subscription:\(id):\(status)"))
        }

        for id in tracked.keys where !seen.contains(id) {
            let product = productName(fromTrackedID: id)
            let shaped = PolarShape.subscriptionRecovered(productName: product)
            // Stamped with a moment (not the status, unlike the alarms above)
            // so a subscription that later re-enters and re-leaves an
            // unhealthy state can recover-land again.
            landed.append(thing(shaped, sourceRef: "polar:subscription:\(id):recovered:\(Int(Date.now.timeIntervalSince1970))"))
            tracked.removeValue(forKey: id)
        }
        PolarAccount.setTracked("subscriptions", tracked)
        return landed
    }

    /// No product name is available for a recovered subscription — it left
    /// the unhealthy page entirely, so this pass never saw its row. Returns
    /// nil honestly rather than guessing; `subscriptionRecovered` already
    /// handles a nil name.
    private static func productName(fromTrackedID id: String) -> String? { nil }

    private static func thing(_ shaped: PolarShape.Shaped, sourceRef: String) -> Thing {
        let t = Thing(kind: .link,
                      title: IngestSupport.titleLine(shaped.title),
                      content: shaped.url,
                      source: PolarWatch.source,
                      capturedAt: shaped.when,
                      tags: [shaped.tag] + shaped.facets,
                      sourceRef: sourceRef)
        t.dueAt = shaped.dueAt
        if let minor = shaped.amountMinor, let code = shaped.currency,
           let value = StripeMoney.value(minor, currency: code) {
            t.priceValue = value
            t.priceCurrency = code.uppercased()
        }
        return t
    }

    @MainActor
    private static func insert(_ incoming: [Thing], context: ModelContext) -> Int {
        let existing = IngestSupport.existingSourceRefs(context, source: PolarWatch.source)
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

    // MARK: Probe

    /// `-polarProbe YES` — the measure tool for an UNMEASURED API. Connect
    /// first (`-tokenBridge "Polar:<token>"`), then this reads the STORED
    /// token and NSLogs the RAW shapes: per-endpoint HTTP status, the
    /// resolved organization, the MRR reading, and one line per refund/
    /// dispute/subscription row with the title it would land wearing. One
    /// NSLog per line on purpose (the `-todayProbe` truncation lesson).
    /// Reads only; running it never advances the tracked-status maps.
    static func probe() async {
        guard let key = TokenVault.get(TokenBridge.polar.tokenKey) else {
            NSLog("[Casberi] polarProbe: no stored token (connect via -tokenBridge \"Polar:<token>\")")
            return
        }
        let (refundsBody, refundsStatus) = await IngestSupport.getJSONBody(
            "\(PolarAccount.api)/refunds/?limit=1", auth: "Bearer \(key)")
        NSLog("[Casberi] polarProbe refunds endpoint: HTTP %d (401 rejected/sandbox-token · 403 missing scope · 0 unreachable)", refundsStatus)
        if refundsStatus != 200 {
            NSLog("[Casberi] polarProbe refunds endpoint reason: %@",
                  PolarFetch.errorDetail(refundsBody) ?? "no reason field in the response body")
        }

        if let org = await PolarFetch.organization(key: key) {
            NSLog("[Casberi] polarProbe org: %@ · %@ (slug=%@)", org.id, org.name.isEmpty ? "—" : org.name, org.slug.isEmpty ? "—" : org.slug)
        } else {
            NSLog("[Casberi] polarProbe org: UNREADABLE (organizations:read is optional)")
        }

        if let reading = await PolarFetch.metrics(key: key) {
            NSLog("[Casberi] polarProbe metrics: mrr=%@ activeSubs=%@ currency=%@",
                  reading.mrrMinor.map(String.init) ?? "nil",
                  reading.activeSubscriptions.map(String.init) ?? "nil",
                  reading.currency)
        } else {
            NSLog("[Casberi] polarProbe metrics: UNREADABLE")
        }

        let refunds = await PolarFetch.refunds(key: key) { [] }
        NSLog("[Casberi] polarProbe refunds: %@", refunds.map { "\($0.count) read" } ?? "UNREADABLE")
        var disputeCount = 0
        for row in refunds ?? [] {
            if let dispute = row["dispute"] as? [String: Any] {
                disputeCount += 1
                NSLog("[Casberi] polarRow| dispute status=%@ evidenceDueBy=%@",
                      (dispute["status"] as? String) ?? "?",
                      String(describing: dispute["evidence_due_by"] ?? "nil"))
            }
            if let shaped = PolarShape.refund(row) {
                NSLog("[Casberi] polarRow| refund → %@", shaped.title)
            }
        }
        NSLog("[Casberi] polarProbe disputes seen on refunds page: %d", disputeCount)

        let subs = await PolarFetch.unhealthySubscriptions(key: key)
        NSLog("[Casberi] polarProbe unhealthy subscriptions: %@", subs.map { "\($0.count) read" } ?? "UNREADABLE")
        for row in subs ?? [] {
            NSLog("[Casberi] polarRow| subscription status=%@ product=%@",
                  (row["status"] as? String) ?? "?",
                  ((row["product"] as? [String: Any])?["name"] as? String) ?? "?")
        }
    }
}

// MARK: - The seat

enum PolarWatch {

    static let source = "Polar"

    /// The seat rule, owned in one place: connected while a token exists —
    /// Stripe's exact shape, one account, no watch list.
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard PolarAccount.configured else {
            store.remove(TokenBridge.polar.bridgeID)
            return
        }
        let name = PolarAccount.orgName
        let mrr = PolarState.mrrText()
        let proof = [name.isEmpty ? nil : name, mrr.map { String(localized: "\($0)/mo recurring") }]
            .compactMap { $0 }.joined(separator: " · ")
        store.registerConnected(
            id: TokenBridge.polar.bridgeID, name: source,
            proof: proof.isEmpty ? String(localized: "Connected") : proof,
            can: [TokenBridge.polar.canLine])
    }
}
