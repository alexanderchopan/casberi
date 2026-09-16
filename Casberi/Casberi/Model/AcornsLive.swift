import Foundation
import SwiftData

/// Acorns, read with the person's OWN signed-in session — §726's Instagram
/// door and §731's TikTok door, one seat over. A REAL SEAT since §780b (user:
/// "yes promote them to real seats we can test on testflight"), reversing
/// §780's DEBUG-only staging: the staging put the only door inside the
/// Diagnostics sheet, which is where probe output is read and not anywhere a
/// person would look for a bridge.
///
/// **What that reversal costs, stated plainly because the seat has to carry
/// it.** The staging existed so the read path could be proven against a real
/// account before shipping. Promoting first means the Connect button ships
/// before anyone has seen a single authenticated response — so this seat is
/// built to be honest about exactly that: it reads, and it says what it found,
/// including when what it found is nothing it could make a row out of. See
/// `AcornsIngest.Reading`. It never says "Synced" over a read it did not
/// understand (§83).
///
/// This reads a BROKERAGE account, so the credential is device-only Keychain
/// and every path here is a GET. There is no endpoint in this file that could
/// accept a write.
///
/// **WHAT WAS MEASURED BEFORE A LINE WAS WRITTEN (2026-09-15, keyless).** The
/// API is a versioned REST namespace on `api.acorns.com`, and it hands back a
/// clean oracle: an endpoint that EXISTS answers `401 {"error":"Login
/// required."}` and one that does not answers `404 {"error":"Could not find
/// resource."}`. Four are confirmed live by that split and are what
/// `Endpoint.confirmed` holds. The sign-in is at `oak.acorns.com/sign-in`
/// (OAuth, `/oauth/sign-in`), and — unlike Cash App's, which loads reCAPTCHA
/// Enterprise, and Credit Karma's, which is walled by an edge bot check before
/// login — it carries **no captcha and no bot vendor at all**, which is the
/// single reason this seat was judged reachable and those two were not.
///
/// **THE PROBE PRINTS SHAPE, NEVER VALUES.** `-keychainProbe` reports counts
/// and never a token; `-secretScanProbe` reports kinds and never the secret.
/// Same rule, and here it is load-bearing rather than tidy: this endpoint's
/// body is somebody's balances. The probe logs the status, the top-level JSON
/// type, and the KEY NAMES — never a number, a string value or an identifier.
/// That is enough to write a parser against and not enough to leak an account
/// into a simulator log.
enum AcornsAuth {
    /// The bearer the web app sends. Device-only Keychain via `TokenVault`,
    /// like every other session credential in the app.
    private static let bearerKey = "acorns.live.bearer"
    /// The session cookies, as one `Cookie:` header — the fallback credential
    /// for the case the bearer is minted per-request and never observed.
    private static let cookieKey = "acorns.live.cookies"

    static var bearer: String? {
        TokenVault.get(bearerKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var cookieHeader: String? {
        TokenVault.get(cookieKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Either credential is enough to try a read. Which one actually works is
    /// exactly what the probe exists to find out.
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
    }
}

enum AcornsLive {

    static let source = "Acorns"
    static let seatID = "acorns"
    static let refPrefix = "acorns:"

    /// The host the reads go to, as one literal so `network-reach-audit.sh`
    /// can see it. Declared in `NetworkReach` since §780b.
    static let apiHost = "api.acorns.com"

    /// The endpoints confirmed to EXIST by the 401/404 split, keylessly.
    /// Deliberately short: this is what was proved, not what was guessed.
    /// Path enumeration past this point is the signed-in session's job —
    /// observing what the app itself calls is both safer and more accurate
    /// than brute-forcing a third party's namespace.
    enum Endpoint: String, CaseIterable {
        case user        = "/v1/user"
        case accounts    = "/v1/accounts"
        case investments = "/v1/investments"
        case settings    = "/v1/settings"

        var url: String { "https://\(AcornsLive.apiHost)\(rawValue)" }
    }

    /// What a read came back as. `refused` is the only outcome that should
    /// ever clear a stored credential — §711's rule, learned on Spotify: a
    /// throttle or a checkpoint is not a dead session, and treating it as one
    /// signs the person out for no reason.
    enum Outcome: Equatable {
        case ok(keys: [String], type: String)
        /// The session is dead or was never good.
        case refused(Int)
        /// Rate-limited or challenged — keep the credential, back off.
        case throttled(Int)
        /// Reached, and the endpoint is not there (the 404 half of the oracle).
        case missing
        /// No response at all.
        case unreachable
    }

    /// One read, reported as SHAPE. See the type doc: no value ever leaves
    /// this function.
    static func read(_ endpoint: Endpoint) async -> Outcome {
        // `Accept: application/json` is set by `getJSONStatus` itself — only
        // the cookie fallback is ours to add.
        var headers: [String: String] = [:]
        if let cookies = AcornsAuth.cookieHeader { headers["Cookie"] = cookies }
        let (json, status) = await IngestSupport.getJSONStatus(
            endpoint.url,
            auth: AcornsAuth.bearer.map { "Bearer \($0)" },
            headers: headers,
            service: "Acorns")

        switch status {
        case 200:
            guard let json else { return .ok(keys: [], type: "empty") }
            if let object = json as? [String: Any] {
                return .ok(keys: object.keys.sorted(), type: "object")
            }
            if let array = json as? [Any] {
                // An array of records: the SHAPE that matters is the first
                // element's keys, and its length. Neither is a value.
                let first = (array.first as? [String: Any])?.keys.sorted() ?? []
                return .ok(keys: first, type: "array[\(array.count)]")
            }
            return .ok(keys: [], type: "scalar")
        case 401, 403:
            return .refused(status)
        case 404:
            return .missing
        case 429, 503:
            return .throttled(status)
        case 0:
            return .unreachable
        default:
            return .refused(status)
        }
    }

    /// The whole census, one NSLog per endpoint — `-acornsProbe YES`. The
    /// shape `-spotifyProbe` established: a failure that splits three ways
    /// (no credential / a credential they refuse / a read that returns
    /// nothing) looks identical on a screen, so the probe names which.
    static func probe() async {
        guard AcornsAuth.connected else {
            NSLog("acorns| NOT CONNECTED — run -acornsSession \"<bearer>\", or sign in from Diagnostics")
            return
        }
        NSLog("acorns| credential: bearer=%@ cookies=%@",
              AcornsAuth.bearer == nil ? "no" : "yes",
              AcornsAuth.cookieHeader == nil ? "no" : "yes")
        for endpoint in Endpoint.allCases {
            switch await read(endpoint) {
            case .ok(let keys, let type):
                NSLog("acorns| %@ | OK | %@ | keys: %@",
                      endpoint.rawValue, type,
                      keys.isEmpty ? "(none)" : keys.joined(separator: ","))
            case .refused(let code):
                NSLog("acorns| %@ | REFUSED %d — the session is dead or never took",
                      endpoint.rawValue, code)
            case .throttled(let code):
                NSLog("acorns| %@ | THROTTLED %d — credential kept", endpoint.rawValue, code)
            case .missing:
                NSLog("acorns| %@ | 404 — not this path", endpoint.rawValue)
            case .unreachable:
                NSLog("acorns| %@ | UNREACHABLE — no response", endpoint.rawValue)
            }
        }
    }
}

/// What the seat lands, and what it says when it can't.
///
/// **This ingest ships ahead of its evidence (prd §780b), and its whole design
/// follows from that.** No authenticated Acorns response has been seen from
/// here — the endpoints are confirmed to exist, their bodies are not known — so
/// it reads through `LooseJSON` rather than a schema, and it distinguishes
/// three outcomes a confident parser would collapse into one:
///
///   · rows landed — the shape was readable;
///   · the account is genuinely EMPTY — read fine, nothing in it;
///   · the shape was NOT readable — and then it says so, naming the keys it
///     actually saw, so the miss is fixable from the person's own screen.
///
/// The third is the one that matters. A parser written against a guess fails
/// identically whether the guess was wrong or the account is empty, and a seat
/// that says "Synced just now" over either is §83's fake status.
enum AcornsIngest {
    @MainActor private static var running = false

    /// What one pass made of the account. The screen renders this verbatim —
    /// it is the seat's honesty, not a debug aid.
    struct Reading: Equatable {
        var landed = 0
        /// Endpoints that answered 200 but whose body yielded no record this
        /// could read, with the key names seen. Empty when everything parsed.
        var unreadable: [String: [String]] = [:]
        /// Endpoints that answered 200 with a readable body holding no records.
        var empty: [String] = []
        /// True when the session itself was refused — the one outcome that
        /// clears the credential (§711: a throttle is not a dead session).
        var refused = false
        var unreachable = false

        /// Did anything at all come back that this understood?
        var understoodSomething: Bool { landed > 0 || !empty.isEmpty }
    }

    @MainActor private(set) static var lastReading = Reading()

    /// nil = the pass could not run or the session is gone; otherwise how many
    /// rows are new. `lastReading` carries the detail either way.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard AcornsAuth.connected else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        var reading = Reading()
        var existing = IngestSupport.existingSourceRefs(context, source: AcornsLive.source)
        var byRef: [String: Thing]?
        func stored(_ ref: String) -> Thing? {
            if byRef == nil {
                byRef = IngestSupport.thingsByRef(context, source: AcornsLive.source)
            }
            return byRef?[ref]
        }

        var touched = false
        var indexed: [Thing] = []

        // Only the two endpoints that could hold money worth a row. `/v1/user`
        // and `/v1/settings` are identity and preferences — read by the probe,
        // never landed, because a row about your notification preferences is
        // not a thing anybody keeps.
        for endpoint in [AcornsLive.Endpoint.accounts, .investments] {
            var headers: [String: String] = [:]
            if let cookies = AcornsAuth.cookieHeader { headers["Cookie"] = cookies }
            let (json, status) = await IngestSupport.getJSONStatus(
                endpoint.url,
                auth: AcornsAuth.bearer.map { "Bearer \($0)" },
                headers: headers,
                service: "Acorns")

            switch status {
            case 200: break
            case 401, 403:
                reading.refused = true
                AcornsAuth.clear()
                lastReading = reading
                return nil
            case 0:
                reading.unreachable = true
                continue
            default:
                continue
            }

            let records = LooseJSON.records(in: json)
            guard !records.isEmpty else {
                // 200 with nothing this could read. Which of the two it is
                // matters, and only the key names can say.
                let keys = LooseJSON.keyNames(in: json)
                if keys.isEmpty { reading.empty.append(endpoint.rawValue) }
                else { reading.unreadable[endpoint.rawValue] = keys }
                continue
            }

            var landedHere = 0
            for record in records {
                // A record with no name AND no amount is not an account — it is
                // some wrapper object this reader walked into. Skipped rather
                // than landed as a row with nothing in it.
                guard let name = LooseJSON.name(in: record) else { continue }
                let value = LooseJSON.amount(in: record)
                let key = LooseJSON.id(in: record) ?? name.lowercased()
                let ref = AcornsLive.refPrefix + endpoint.rawValue + ":" + key
                let money = value.map { LooseJSON.money($0, currency: LooseJSON.currency(in: record)) }
                let title = money.map { "\(name) — \($0)" } ?? name

                if existing.contains(ref) {
                    // A balance is a STATE, not an event (§216's split): the
                    // row updates in place rather than landing again daily.
                    if let thing = stored(ref), thing.title != title {
                        thing.title = title
                        thing.embedding = nil
                        thing.capturedAt = .now
                        touched = true
                    }
                    landedHere += 1
                    continue
                }

                let thing = Thing(
                    kind: .note,
                    title: title,
                    content: "",
                    source: AcornsLive.source,
                    capturedAt: LooseJSON.date(in: record) ?? .now,
                    sourceRef: ref)
                thing.authorHandle = AcornsLive.source
                context.insert(thing)
                existing.insert(ref)
                indexed.append(thing)
                reading.landed += 1
                landedHere += 1
            }
            // Records came back but none were readable as an account.
            if landedHere == 0 {
                reading.unreadable[endpoint.rawValue] = LooseJSON.keyNames(in: json)
            }
        }

        SpotlightIndex.index(indexed.filter(\.isLive))
        if reading.landed > 0 || touched { context.saveHonestly() }
        lastReading = reading

        // Nothing understood and nothing reachable is a failed pass, not an
        // up-to-date one.
        if !reading.understoodSomething && reading.unreachable { return nil }
        return reading.landed
    }
}
