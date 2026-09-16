import Foundation
import SwiftData

/// Rocket Money, read with the person's OWN signed-in session — the second
/// seat promoted in §780b (user: "yes promote them to real seats we can test on
/// testflight"), reversing §780's DEBUG-only staging for the reason Acorns was:
/// the staging put the only door inside Diagnostics, which is not anywhere a
/// person looks for a bridge. It ships ahead of its evidence and is built to
/// say so — see `RocketMoneyIngest.Reading`.
///
/// **WHY THIS SEAT IS SHAPED DIFFERENTLY FROM ACORNS.** Acorns hands back a
/// REST namespace whose endpoints can be discovered keylessly (a 401/404
/// split), so its probe carries a fixed list of four. Rocket Money is one
/// GraphQL endpoint whose schema is deliberately closed: introspection is
/// disabled, and so are field SUGGESTIONS — `{ me }` returns a bare "Cannot
/// query field", never a "did you mean". So there is nothing to enumerate and
/// nothing to guess at.
///
/// What there IS, measured 2026-09-15: the web app ships its own precompiled
/// GraphQL documents in its JS bundle — 91 queries and 114 mutations by name
/// — and the endpoint accepts a raw query string (no persisted-hash gate).
/// Reconstructing those documents by hand would be fragile and would rot on
/// the publisher's next deploy, so this seat does the robust thing instead:
/// **it lets the page teach it its own queries.** The sign-in web view records
/// the operations the real app sends, and the probe replays them.
///
/// **READS ONLY, AND THAT IS STRUCTURAL, NOT A PROMISE.** 114 of those
/// operations are mutations, and this is somebody's bank account — a replayed
/// `CancelSubscription` or `AddBudgetItem` is a real-world act with a real
/// consequence. So a mutation is refused TWICE and by construction: once at
/// capture (it is never written to the catalogue) and again at replay (the
/// text is re-checked immediately before the request is built). Neither check
/// is load-bearing alone; two of them is what makes "read-only" a property of
/// the code rather than a sentence in a comment.
///
/// **AND THE PROBE PRINTS SHAPE, NEVER VALUES** — §780's rule. Status, the
/// top-level JSON type, and KEY NAMES. Never a balance, a merchant, a date or
/// an identifier.
enum RocketMoneyAuth {
    private static let bearerKey = "rocketmoney.live.bearer"
    private static let cookieKey = "rocketmoney.live.cookies"

    static var bearer: String? {
        TokenVault.get(bearerKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var cookieHeader: String? {
        TokenVault.get(cookieKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var connected: Bool { bearer != nil || cookieHeader != nil }

    static func store(bearer: String?, cookieHeader: String?) {
        if let bearer, !bearer.isEmpty { TokenVault.set(bearer, for: bearerKey) }
        if let cookieHeader, !cookieHeader.isEmpty {
            TokenVault.set(cookieHeader, for: cookieKey)
        }
    }

    static func clear() {
        TokenVault.delete(bearerKey)
        TokenVault.delete(cookieKey)
        RocketMoneyOperations.forget()
    }
}

/// The operations the live page was seen to send. NOT a credential — this is
/// the publisher's own client schema, the same text their bundle ships in
/// public — so it lives in `UserDefaults`, not the Keychain. What makes it
/// worth keeping is that it cannot go stale against their next deploy: it is
/// whatever the app actually sent, this session.
enum RocketMoneyOperations {
    private static let key = "rocketmoney.live.operations"

    /// The reads this seat would actually want, by the names the bundle uses.
    /// Only a hint for the probe's ordering and its "still missing" line —
    /// never a filter on what may be captured, because the publisher renames
    /// these freely and a hard filter would silently record nothing.
    static let wanted = ["AuthenticationCheck", "Viewer", "Subscriptions",
                         "RecurringPage", "RecurringUpcomingPage",
                         "TransactionsPage", "NetWorthQuery", "Dashboard"]

    /// Operation name → query text. Queries only; see `isRead`.
    static var catalogue: [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    /// The ONE test of whether a document may be stored or sent. The text must
    /// positively begin with `query` — an anonymous `{ … }` shorthand is a read
    /// too, but accepting it would mean accepting anything that merely fails to
    /// say `mutation` — and must declare no further operation beyond that one.
    ///
    /// **It reads the keywords at BRACE DEPTH 0, and a substring test is not
    /// good enough — measured.** `mutation` and `subscription` are operation
    /// keywords only outside a selection set; inside one they are ordinary
    /// field names. The first version of this function asked
    /// `lowered.contains("subscription")` and therefore refused
    /// `query Subscriptions { … }` — Rocket Money's flagship read, and the
    /// single operation this seat most wants. `rocketmoney-selftest.sh` caught
    /// it, which is the whole reason that harness exists.
    ///
    /// String literals are skipped so a brace inside an argument
    /// (`$s: String = "a{b"`) cannot skew the depth and hide a keyword.
    static func isRead(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("query") else { return false }

        var depth = 0
        var word = ""
        var inString = false
        var escaped = false

        /// True when the word just ended is a forbidden operation keyword.
        func wordIsOperation() -> Bool {
            defer { word = "" }
            guard depth == 0, !word.isEmpty else { return false }
            let w = word.lowercased()
            return w == "mutation" || w == "subscription"
        }

        for ch in text {
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            if ch.isLetter || ch == "_" { word.append(ch); continue }
            if wordIsOperation() { return false }
            switch ch {
            case "\"": inString = true
            case "{":  depth += 1
            case "}":  depth = max(0, depth - 1)
            default:   break
            }
        }
        return !wordIsOperation()
    }

    /// Records one operation the page sent. A mutation is dropped here and
    /// never reaches the store — the first of the two refusals.
    static func record(name: String, query: String) {
        guard !name.isEmpty, isRead(query) else { return }
        var all = catalogue
        guard all[name] != query else { return }
        all[name] = query
        UserDefaults.standard.set(all, forKey: key)
    }

    static func forget() { UserDefaults.standard.removeObject(forKey: key) }
}

enum RocketMoneyLive {

    static let source = "Rocket Money"
    static let seatID = "rocketmoney"
    static let refPrefix = "rocketmoney:"

    /// One literal so `network-reach-audit.sh` can see it; declared in
    /// `NetworkReach` since §780b.
    static let apiHost = "api.rocketmoney.com"
    static var endpoint: String { "https://\(apiHost)/graphql" }

    /// A read that needs no captured operation, so the probe can say whether a
    /// session is good before the page has taught it anything. `viewer` is a
    /// real root field — verified keylessly: unauthenticated it answers
    /// `RequiresAuthentication`, not "Cannot query field".
    static let seedQuery = "query AuthenticationCheck { viewer { __typename } }"

    enum Outcome: Equatable {
        case ok(keys: [String], type: String)
        /// The session is dead or was never good.
        case refused(Int)
        /// Rate-limited or challenged — keep the credential, back off.
        case throttled(Int)
        /// The server answered, and said the document itself is wrong.
        case rejected(String)
        case unreachable
        /// Refused locally: the text is not a read. Never sent.
        case notARead
    }

    /// Sends one operation. The SECOND mutation refusal lives here, immediately
    /// before the body is built — a catalogue entry cannot be trusted just
    /// because storing it was once checked.
    static func run(name: String, query: String) async -> Outcome {
        guard RocketMoneyOperations.isRead(query) else { return .notARead }

        // `Accept` and `Content-Type` are set by `postJSONStatus` itself — only
        // the cookie fallback is ours to add.
        var headers: [String: String] = [:]
        if let cookies = RocketMoneyAuth.cookieHeader { headers["Cookie"] = cookies }
        let (json, status) = await IngestSupport.postJSONStatus(
            endpoint,
            auth: RocketMoneyAuth.bearer.map { "Bearer \($0)" },
            body: ["operationName": name, "query": query],
            headers: headers,
            service: "Rocket Money")

        // GraphQL answers a refusal as a 200 with an `errors` array as often as
        // it does with a status, so the body is read before the code.
        if let object = json as? [String: Any],
           let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            let codes = errors.compactMap { $0["code"] as? String }
            if codes.contains(where: { $0.contains("AUTHENTICATION") }) { return .refused(401) }
            if codes.contains(where: { $0.contains("RATE") || $0.contains("THROTTL") }) {
                return .throttled(429)
            }
            // The message is the SERVER's own words about the DOCUMENT, never
            // about the account — safe to print, and the only way to see that
            // a captured operation needs variables.
            return .rejected(codes.first ?? "GRAPHQL_ERROR")
        }

        switch status {
        case 200:
            guard let object = json as? [String: Any] else { return .ok(keys: [], type: "empty") }
            if let data = object["data"] as? [String: Any] {
                return .ok(keys: data.keys.sorted(), type: "data")
            }
            return .ok(keys: object.keys.sorted(), type: "object")
        case 401, 403: return .refused(status)
        case 429, 503: return .throttled(status)
        case 0:        return .unreachable
        default:       return .refused(status)
        }
    }

    /// `-rocketProbe YES`. Reports the credential, the captured catalogue, and
    /// what each read comes back as — one `rocket|` line each.
    static func probe() async {
        guard RocketMoneyAuth.connected else {
            NSLog("rocket| NOT CONNECTED — sign in from Diagnostics, or -rocketSession \"<bearer>\"")
            return
        }
        NSLog("rocket| credential: bearer=%@ cookies=%@",
              RocketMoneyAuth.bearer == nil ? "no" : "yes",
              RocketMoneyAuth.cookieHeader == nil ? "no" : "yes")

        // The seed first: it needs nothing captured, so it separates "the
        // session is dead" from "the page taught us nothing yet".
        report("AuthenticationCheck (seed)", await run(name: "AuthenticationCheck", query: seedQuery))

        let catalogue = RocketMoneyOperations.catalogue
        NSLog("rocket| catalogue: %d read operations captured", catalogue.count)
        let missing = RocketMoneyOperations.wanted.filter { catalogue[$0] == nil }
        if !missing.isEmpty {
            NSLog("rocket| not yet seen: %@ — open those pages in the sign-in view",
                  missing.joined(separator: ","))
        }

        // Wanted ones first, then whatever else the page taught us.
        let ordered = RocketMoneyOperations.wanted.filter { catalogue[$0] != nil }
            + catalogue.keys.filter { !RocketMoneyOperations.wanted.contains($0) }.sorted()
        for name in ordered {
            guard let query = catalogue[name] else { continue }
            report(name, await run(name: name, query: query))
        }
    }

    private static func report(_ name: String, _ outcome: Outcome) {
        switch outcome {
        case .ok(let keys, let type):
            NSLog("rocket| %@ | OK | %@ | keys: %@", name, type,
                  keys.isEmpty ? "(none)" : keys.joined(separator: ","))
        case .refused(let code):
            NSLog("rocket| %@ | REFUSED %d — the session is dead or never took", name, code)
        case .throttled(let code):
            NSLog("rocket| %@ | THROTTLED %d — credential kept", name, code)
        case .rejected(let code):
            NSLog("rocket| %@ | REJECTED %@ — the document needs variables, or has changed", name, code)
        case .unreachable:
            NSLog("rocket| %@ | UNREACHABLE — no response", name)
        case .notARead:
            NSLog("rocket| %@ | NOT A READ — refused locally, never sent", name)
        }
    }
}

/// What the seat lands, and what it says when it can't — `AcornsIngest`'s
/// shape, for the same reason (prd §780b: both seats ship ahead of their
/// evidence), plus one more failure this seat can have and Acorns cannot.
///
/// **"Not connected" and "nothing taught yet" are different, and a person can
/// fix only one of them.** This seat's reads come from watching the real page,
/// so a perfectly good session with an empty catalogue lands nothing — and the
/// remedy is "open Subscriptions inside the sign-in sheet", which no generic
/// failure line would ever say. `Reading.taught` carries that.
enum RocketMoneyIngest {
    @MainActor private static var running = false

    struct Reading: Equatable {
        var landed = 0
        /// How many read operations the page has taught us.
        var taught = 0
        /// Operations that answered but whose body yielded nothing readable,
        /// with the key names seen.
        var unreadable: [String: [String]] = [:]
        var empty: [String] = []
        var refused = false
        var unreachable = false

        var understoodSomething: Bool { landed > 0 || !empty.isEmpty }
    }

    @MainActor private(set) static var lastReading = Reading()

    /// The operations worth LANDING, as opposed to merely replaying. A
    /// subscription and a recurring bill are things a person keeps; a viewer
    /// record and an auth check are not, and landing them would be rows about
    /// the plumbing.
    private static let landable = ["Subscriptions", "RecurringPage",
                                   "RecurringUpcomingPage", "SubscriptionDetailPage"]

    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard RocketMoneyAuth.connected else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        var reading = Reading()
        let catalogue = RocketMoneyOperations.catalogue
        reading.taught = catalogue.count

        // The seed proves the SESSION even when the catalogue is empty, so the
        // screen can tell "sign in again" from "go teach it a page".
        switch await RocketMoneyLive.run(name: "AuthenticationCheck",
                                         query: RocketMoneyLive.seedQuery) {
        case .refused:
            reading.refused = true
            RocketMoneyAuth.clear()
            lastReading = reading
            return nil
        case .unreachable:
            reading.unreachable = true
            lastReading = reading
            return nil
        default: break
        }

        var existing = IngestSupport.existingSourceRefs(context, source: RocketMoneyLive.source)
        var byRef: [String: Thing]?
        func stored(_ ref: String) -> Thing? {
            if byRef == nil {
                byRef = IngestSupport.thingsByRef(context, source: RocketMoneyLive.source)
            }
            return byRef?[ref]
        }
        var touched = false
        var indexed: [Thing] = []

        for name in landable {
            guard let query = catalogue[name] else { continue }
            // Re-runs the read rather than trusting the capture — `run` is
            // where the second mutation refusal lives.
            var headers: [String: String] = [:]
            if let cookies = RocketMoneyAuth.cookieHeader { headers["Cookie"] = cookies }
            let (json, _) = await IngestSupport.postJSONStatus(
                RocketMoneyLive.endpoint,
                auth: RocketMoneyAuth.bearer.map { "Bearer \($0)" },
                body: ["operationName": name, "query": query],
                headers: headers,
                service: "Rocket Money")
            guard RocketMoneyOperations.isRead(query) else { continue }

            let records = LooseJSON.records(in: json)
            guard !records.isEmpty else {
                let keys = LooseJSON.keyNames(in: json)
                if keys.isEmpty { reading.empty.append(name) }
                else { reading.unreadable[name] = keys }
                continue
            }

            var landedHere = 0
            for record in records {
                guard let label = LooseJSON.name(in: record) else { continue }
                let value = LooseJSON.amount(in: record)
                let key = LooseJSON.id(in: record) ?? label.lowercased()
                let ref = RocketMoneyLive.refPrefix + key
                let money = value.map { LooseJSON.money($0, currency: LooseJSON.currency(in: record)) }
                let title = money.map { "\(label) — \($0)" } ?? label

                if existing.contains(ref) {
                    // A subscription is a STATE: its price changes, it does not
                    // re-land monthly.
                    if let thing = stored(ref), thing.title != title {
                        thing.title = title
                        thing.embedding = nil
                        touched = true
                    }
                    landedHere += 1
                    continue
                }
                let thing = Thing(
                    kind: .note,
                    title: title,
                    content: "",
                    source: RocketMoneyLive.source,
                    capturedAt: LooseJSON.date(in: record) ?? .now,
                    sourceRef: ref)
                thing.authorHandle = RocketMoneyLive.source
                context.insert(thing)
                existing.insert(ref)
                indexed.append(thing)
                reading.landed += 1
                landedHere += 1
            }
            if landedHere == 0 {
                reading.unreadable[name] = LooseJSON.keyNames(in: json)
            }
        }

        SpotlightIndex.index(indexed.filter(\.isLive))
        if reading.landed > 0 || touched { context.saveHonestly() }
        lastReading = reading
        return reading.landed
    }
}
