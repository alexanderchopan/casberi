import Foundation
import SwiftData

/// Cloudflare — the deadlines behind a site you run (2026-08-03).
///
/// Cloudflare's API is overwhelmingly a firehose of COUNTS: requests served,
/// bandwidth, cache hit ratio, threats blocked. Not one of them lands here.
/// That is the PostHog lesson stated as a rule — a count is never a thing, and
/// a bridge that mirrored Cloudflare's analytics would be a dashboard nobody
/// asked for sitting inside a personal corpus.
///
/// What Cloudflare knows that IS thing-shaped is every date on which something
/// you own stops working. Four of them land, and all four are the reconciling
/// `dueAt` shape already shipping in `ENSExpiry` and Aerodrome's vote deadline:
///
/// 1. **A TLS certificate close to expiry.** Certificates renew themselves
///    until they don't, and a renewal that quietly failed is invisible until
///    the browser warning. Only a pack inside `expiryWindow` lands — a
///    certificate with 70 days on it is not news, it is the normal state of
///    every certificate on earth.
/// 2. **A domain registration close to renewal** (Cloudflare Registrar only).
///    Landed further out than a certificate because the decision is yours and
///    auto-renew fails on a dead card.
/// 3. **The API token's own expiry.** The bridge warning about its own
///    credential: when this token lapses the connection stops reading and
///    nothing else on the device knows why.
/// 4. **A zone that is not active.** A domain sitting at `pending` is not
///    being served — the most urgent thing here, and the only one with no
///    date, because it is already true.
///
/// **Read-only STRUCTURALLY, not by conduct.** Cloudflare API tokens carry
/// permissions chosen at mint time, so a token minted with the reads named on
/// the setup screen has no write capability to misuse. That is the PostHog and
/// Trello contract rather than Privacy.com's promise-by-behaviour — and unlike
/// Trello, Casberi does not mint it, so the setup screen names the exact
/// permissions instead.
///
/// **MEASURED 2026-08-03** (curl, no key), and the four auth outcomes are
/// distinct enough to word separately — see `CloudflareFailure`:
/// no `Authorization` header → 400 `1001`; a malformed token → 400 `6003/6111`;
/// a well-formed token that isn't valid → **401 `1000`** on `/user/tokens/verify`
/// but **403 `9109`** on `/zones`; legacy key+email headers → 403 `9103`.
/// Validation therefore rides `/user/tokens/verify`, which is the only endpoint
/// that separates "this token is invalid" from "this token lacks that
/// permission" — every resource endpoint reports both as 403.
///
/// **UNMEASURED against a live account**: no Cloudflare token is stored and the
/// build host has no authenticated access, so every payload shape below is
/// derived from Cloudflare's published API reference. Every read is a GET and
/// every failure path returns nil or skips, so it fails safe — a renamed field
/// lands nothing rather than landing something wrong. Verify with
/// `-tokenBridge "Cloudflare:<token>"` then `-cloudflareProbe YES` before
/// trusting any date on this screen.
enum CloudflareFetch {

    // MARK: - Budget

    /// How far ahead each kind of deadline is worth saying out loud.
    ///
    /// These differ on purpose. A certificate renews on its own about a month
    /// out, so 30 days is already the window in which silence means something
    /// broke. A registration is a decision — and one whose auto-renew depends
    /// on a card that may have expired — so it wants longer. The token matches
    /// the certificate: by the time it lapses the bridge has already gone
    /// quiet.
    static let certWindow  = 30
    static let domainWindow = 60
    static let tokenWindow = 30

    /// The per-zone certificate read is the only fan-out in this pass, so it
    /// is the only thing that can make a Cloudflare account with many domains
    /// expensive. Ten zones is one request each on top of a fixed three, which
    /// keeps a worst-case pass at ~14 requests against a documented limit of
    /// 1200 per five minutes.
    ///
    /// What is dropped is REPORTED, never silent (`-cloudflareProbe` prints the
    /// overflow) — a cap that hides its own effect reads as full coverage.
    static let zoneCap = 10

    /// Pages of 100 DNS records read per zone. Three covers every real zone;
    /// a zone with more refuses the diff entirely rather than running one over
    /// a prefix — see `allDNSRecords`.
    static let dnsPageCap = 3

    /// DNS changes landed per zone per pass. A bulk edit is genuinely N
    /// distinct events, but forty rows at once is a flood that buries the
    /// deadline rows this bridge exists for. The overflow is REPORTED by
    /// `-cloudflareProbe`, never silent — and the snapshot advances regardless,
    /// so a dropped change is dropped for good rather than re-landing forever.
    static let dnsChangeCap = 10

    private static let api = "https://api.cloudflare.com/client/v4"

    /// The refs this pass genuinely COVERED — every ref it was in a position to
    /// land, whether or not it did.
    ///
    /// `reconcileCloudflare` resolves a row by ABSENCE, which is the opposite
    /// of `reconcileTrello`'s deliberately conservative rule, and it is only
    /// safe because of this set. Absence from `things` has exactly one meaning
    /// — the condition that put the row there stopped holding — but only for a
    /// zone this pass actually read. A zone past `zoneCap`, or an account whose
    /// registrar read failed, is absent for a reason that has nothing to do
    /// with the deadline, and marking those done would quietly retire a warning
    /// about a certificate that really is about to expire.
    private(set) static var lastCovered: Set<String> = []

    // MARK: - The pass

    /// Reads the account and returns what needs attention. Nil means the token
    /// could not be used at all — `TokenIngest.refresh` words that as "check
    /// the token", which is right for every case that reaches it.
    @MainActor
    static func things(token: String) async -> [Thing]? {
        var covered: Set<String> = []
        var out: [Thing] = []

        // 1. The token itself. This is the validation request as well as a
        // reading: it is the only endpoint that answers 401 rather than 403 for
        // a token that isn't valid, so a failure here is unambiguous.
        let verify = await IngestSupport.getJSONStatus("\(api)/user/tokens/verify",
                                                       auth: "Bearer \(token)")
        guard verify.status == 200,
              let verifyBody = verify.json as? [String: Any],
              (verifyBody["success"] as? Bool) == true,
              let tokenInfo = verifyBody["result"] as? [String: Any]
        else { return nil }

        covered.insert("cloudflare:token")
        if let expiring = tokenRow(tokenInfo) { out.append(expiring) }

        // 2. The zones. A failure here IS a failure of the pass — with no zone
        // list there is nothing else to read, and reporting "nothing needs
        // attention" on an unread account is the exact lie this bridge exists
        // to avoid.
        guard let zonesBody = await IngestSupport.getJSON("\(api)/zones?per_page=50",
                                                          auth: "Bearer \(token)") as? [String: Any],
              let zones = zonesBody["result"] as? [[String: Any]]
        else { return nil }

        for zone in zones {
            guard let id = zone["id"] as? String,
                  let name = zone["name"] as? String, !name.isEmpty else { continue }
            covered.insert("cloudflare:zone:\(id)")
            if let stalled = zoneRow(zone, id: id, name: name) { out.append(stalled) }
        }

        // 3. Certificates, one request per zone, capped. A zone whose
        // certificate read fails is NOT marked covered, so its existing row
        // survives untouched rather than resolving on a blip.
        for zone in zones.prefix(zoneCap) {
            guard let id = zone["id"] as? String,
                  let name = zone["name"] as? String, !name.isEmpty else { continue }
            guard let body = await IngestSupport.getJSON(
                    "\(api)/zones/\(id)/ssl/certificate_packs?status=all",
                    auth: "Bearer \(token)") as? [String: Any],
                  let packs = body["result"] as? [[String: Any]]
            else { continue }
            covered.insert("cloudflare:cert:\(id)")
            if let soon = certRow(packs, zoneID: id, zoneName: name,
                                  dashboard: dashboardURL(zone: zone, name: name)) {
                out.append(soon)
            }
        }

        // 3b. What moved in DNS since last pass. These are EVENTS, not states —
        // they are stamped with their moment, they never reconcile, and their
        // refs are deliberately NOT added to `covered` (see the reconcile).
        for zone in zones.prefix(zoneCap) {
            guard let id = zone["id"] as? String,
                  let name = zone["name"] as? String, !name.isEmpty else { continue }
            out += await dnsPass(zoneID: id, zoneName: name,
                                 dashboard: dashboardURL(zone: zone, name: name),
                                 auth: "Bearer \(token)")
        }

        // 4. Registrar domains. Most Cloudflare accounts do not use Cloudflare
        // as their registrar, and that account answers 403 here — a SKIP, not a
        // failure, and deliberately not covered, so nothing resolves off it.
        if let accountsBody = await IngestSupport.getJSON("\(api)/accounts",
                                                          auth: "Bearer \(token)") as? [String: Any],
           let accounts = accountsBody["result"] as? [[String: Any]] {
            for account in accounts.prefix(3) {
                guard let accountID = account["id"] as? String else { continue }
                guard let body = await IngestSupport.getJSON(
                        "\(api)/accounts/\(accountID)/registrar/domains",
                        auth: "Bearer \(token)") as? [String: Any],
                      let domains = body["result"] as? [[String: Any]]
                else { continue }
                for domain in domains {
                    guard let name = domain["name"] as? String, !name.isEmpty else { continue }
                    covered.insert("cloudflare:domain:\(name)")
                    if let due = domainRow(domain, name: name, accountID: accountID) {
                        out.append(due)
                    }
                }
            }
        }

        lastCovered = covered
        return out
    }

    // MARK: - Shapes

    /// The API token's own expiry. A token with no `expires_on` never expires —
    /// that is Cloudflare's own "no expiry" option, not a missing field, so it
    /// lands nothing rather than a row claiming an unknown date.
    static func tokenRow(_ info: [String: Any]) -> Thing? {
        guard let expiry = IngestSupport.isoDate(info["expires_on"]),
              let days = daysUntil(expiry), days <= tokenWindow else { return nil }
        let thing = Thing(
            kind: .reminder,
            title: days <= 0
                ? String(localized: "Your Cloudflare API token has expired")
                : String(localized: "Your Cloudflare API token expires in \(days) days"),
            content: "https://dash.cloudflare.com/profile/api-tokens",
            source: "Cloudflare",
            capturedAt: .now,
            sourceRef: "cloudflare:token"
        )
        thing.dueAt = expiry
        thing.mark = .todo
        thing.summary = String(localized: "When it lapses, Casberi stops reading your Cloudflare account and nothing else on this iPhone will know why. Mint a replacement and paste it in.")
        return thing
    }

    /// A zone that is not being served. No date — it is already true — so this
    /// is the one shape here with no `dueAt`.
    ///
    /// Only `active` is healthy. `pending` means the nameservers have not moved
    /// yet, `initializing` that setup never finished, `moved`/`deactivated`
    /// that it stopped. Each of those is worth one row.
    static func zoneRow(_ zone: [String: Any], id: String, name: String) -> Thing? {
        guard let status = zone["status"] as? String,
              status.lowercased() != "active" else { return nil }
        let thing = Thing(
            kind: .reminder,
            title: String(localized: "\(name) isn't active on Cloudflare — \(status)"),
            content: dashboardURL(zone: zone, name: name),
            source: "Cloudflare",
            capturedAt: .now,
            sourceRef: "cloudflare:zone:\(id)"
        )
        thing.mark = .todo
        thing.summary = String(localized: "Cloudflare isn't serving this domain while it's in this state.")
        return thing
    }

    /// The earliest certificate expiry in a zone, when it falls inside
    /// `certWindow`.
    ///
    /// EARLIEST, not latest: a zone can hold several packs and the one that
    /// bites is whichever dies first. Only `active` packs are read — a pending
    /// or deleted pack carries a date that means nothing.
    ///
    /// The pack shape is handled two ways on purpose. Cloudflare documents the
    /// expiry on the certificates INSIDE a pack, but has also returned it at
    /// pack level; reading both costs one `??` and makes the difference between
    /// a working feature and a silently empty one, which is not a trade worth
    /// thinking about twice.
    static func certRow(_ packs: [[String: Any]], zoneID: String, zoneName: String,
                        dashboard: String) -> Thing? {
        var earliest: Date?
        for pack in packs {
            if let status = pack["status"] as? String,
               status.lowercased() != "active" { continue }
            var packDates: [Date] = []
            if let top = IngestSupport.isoDate(pack["expires_on"]) { packDates.append(top) }
            for cert in (pack["certificates"] as? [[String: Any]]) ?? [] {
                if let d = IngestSupport.isoDate(cert["expires_on"]) { packDates.append(d) }
            }
            if let primary = pack["primary_certificate"] as? [String: Any],
               let d = IngestSupport.isoDate(primary["expires_on"]) { packDates.append(d) }
            if let soonest = packDates.min() {
                earliest = min(earliest ?? soonest, soonest)
            }
        }
        guard let expiry = earliest,
              let days = daysUntil(expiry), days <= certWindow else { return nil }
        let thing = Thing(
            kind: .reminder,
            title: days <= 0
                ? String(localized: "\(zoneName) — TLS certificate has expired")
                : String(localized: "\(zoneName) — TLS certificate expires in \(days) days"),
            content: dashboard,
            source: "Cloudflare",
            capturedAt: .now,
            sourceRef: "cloudflare:cert:\(zoneID)"
        )
        thing.dueAt = expiry
        thing.mark = .todo
        thing.summary = String(localized: "Certificates normally renew on their own about a month out. Seeing this means the renewal hasn't happened yet.")
        return thing
    }

    /// A Cloudflare Registrar domain approaching renewal.
    ///
    /// Auto-renew is stated rather than used as a filter: it is exactly the
    /// domains set to renew automatically that lapse, because the card behind
    /// them expired and nobody was told.
    static func domainRow(_ domain: [String: Any], name: String, accountID: String) -> Thing? {
        let raw = domain["expires_at"] ?? domain["expires_on"]
        guard let expiry = IngestSupport.isoDate(raw),
              let days = daysUntil(expiry), days <= domainWindow else { return nil }
        let auto = (domain["auto_renew"] as? Bool) ?? false
        let thing = Thing(
            kind: .reminder,
            title: days <= 0
                ? String(localized: "\(name) has expired")
                : (auto ? String(localized: "\(name) renews in \(days) days")
                        : String(localized: "\(name) expires in \(days) days")),
            content: "https://dash.cloudflare.com/\(accountID)/domains/\(name)",
            source: "Cloudflare",
            capturedAt: .now,
            sourceRef: "cloudflare:domain:\(name)"
        )
        thing.dueAt = expiry
        thing.mark = .todo
        thing.summary = auto
            ? String(localized: "Set to renew automatically — which still fails if the card behind it has expired.")
            : String(localized: "Auto-renew is off. Nothing will renew this for you.")
        return thing
    }

    // MARK: - Helpers

    /// Whole days from now until `date`, negative once it's past. Nil only if
    /// the calendar can't answer, which it always can.
    static func daysUntil(_ date: Date, from now: Date = .now) -> Int? {
        Calendar.current.dateComponents([.day], from: now, to: date).day
    }

    // MARK: - DNS

    /// One DNS record, in the only five fields a change is worth reporting on.
    ///
    /// `fields` is what gets remembered between passes, as an ARRAY rather than
    /// a joined string: a TXT record's content routinely contains every
    /// delimiter you might pick (`|`, `;`, `=`, spaces), so any fingerprint that
    /// needs splitting back apart is a bug waiting for the first SPF record.
    struct DNSRecord {
        let id: String
        let type: String
        let name: String
        let content: String
        let proxied: String
        let ttl: String
        let modifiedOn: String

        var fields: [String] { [type, name, content, proxied, ttl] }

        init?(_ raw: [String: Any]) {
            guard let id = raw["id"] as? String,
                  let type = raw["type"] as? String,
                  let name = raw["name"] as? String else { return nil }
            self.id = id
            self.type = type
            self.name = name
            self.content = (raw["content"] as? String) ?? ""
            self.proxied = String(describing: (raw["proxied"] as? Bool) ?? false)
            self.ttl = String(describing: (raw["ttl"] as? Int) ?? 0)
            self.modifiedOn = (raw["modified_on"] as? String) ?? ""
        }
    }

    /// What happened to one record between two passes.
    struct DNSChange {
        enum Kind { case added, changed, removed }
        let kind: Kind
        let record: DNSRecord
        /// Only set for `.changed` — what the record used to point at, which is
        /// the single most useful thing this feature can tell anyone.
        let previousContent: String?
    }

    /// Pure diff of one zone's records against what was remembered.
    ///
    /// Pure on purpose — no network, no storage, no clock — so the whole of
    /// this feature's judgement is one function that can be reasoned about and
    /// harnessed. Everything around it is plumbing.
    ///
    /// A record is `.changed` when ANY of the five fields moved, not just its
    /// content: flipping a record from proxied to unproxied exposes an origin
    /// server's real address, and dropping a TTL to 60 is what someone does
    /// right before repointing a domain. Both are silent under a
    /// content-only comparison.
    static func diffDNS(current: [DNSRecord],
                        previous: [String: [String]]) -> [DNSChange] {
        var out: [DNSChange] = []
        var seen: Set<String> = []
        for record in current {
            seen.insert(record.id)
            guard let was = previous[record.id] else {
                out.append(DNSChange(kind: .added, record: record, previousContent: nil))
                continue
            }
            guard was != record.fields else { continue }
            // `was[2]` is content — the array's own order, written once in
            // `fields`. Guarded by count because a snapshot written by an older
            // build could be shorter, and a crash on somebody's stored data is
            // a far worse outcome than a change that reports no previous value.
            out.append(DNSChange(kind: .changed, record: record,
                                 previousContent: was.count > 2 ? was[2] : nil))
        }
        for (id, was) in previous where !seen.contains(id) {
            guard was.count >= 5 else { continue }
            let ghost = DNSRecord(["id": id, "type": was[0], "name": was[1],
                                   "content": was[2]])
            if let ghost { out.append(DNSChange(kind: .removed, record: ghost,
                                                previousContent: nil)) }
        }
        return out
    }

    /// Reads every DNS record in a zone, or reports that it couldn't.
    ///
    /// Returns nil rather than a partial list, and that distinction is the
    /// whole reason this function exists separately. Cloudflare paginates at
    /// 100 records; a diff run against page one of a three-page zone would
    /// report **every record on pages two and three as deleted** — a screen
    /// full of alarming, entirely fictional "DNS record removed" rows, on the
    /// one bridge whose whole job is telling you when something changed. A
    /// partial read must therefore be indistinguishable from a failed one.
    private static func allDNSRecords(zoneID: String, auth: String) async -> [DNSRecord]? {
        var out: [DNSRecord] = []
        for page in 1...dnsPageCap {
            guard let body = await IngestSupport.getJSON(
                    "\(api)/zones/\(zoneID)/dns_records?per_page=100&page=\(page)",
                    auth: auth) as? [String: Any],
                  let result = body["result"] as? [[String: Any]] else { return nil }
            out.append(contentsOf: result.compactMap(DNSRecord.init))
            let info = body["result_info"] as? [String: Any]
            let total = (info?["total_count"] as? Int) ?? out.count
            if out.count >= total { return out }
            // More pages exist than this cap allows. Refuse rather than diff a
            // prefix — see the note above.
            if page == dnsPageCap { return nil }
        }
        return out
    }

    /// One zone's DNS pass: read, diff against the remembered snapshot, land
    /// what moved, remember the new state.
    ///
    /// **First sight seeds SILENTLY** — the Peer/Morpho/Hyperliquid rule.
    /// Connecting an account with forty DNS records must not land forty "new
    /// record" rows; that is a backfill wearing news, and it would bury the
    /// deadline rows this bridge exists for under a wall of things you set up
    /// years ago.
    @MainActor
    private static func dnsPass(zoneID: String, zoneName: String, dashboard: String,
                                auth: String) async -> [Thing] {
        guard let records = await allDNSRecords(zoneID: zoneID, auth: auth) else { return [] }
        let snapshot = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.fields) })
        defer { CloudflareDNSLedger.save(snapshot, zone: zoneID) }

        guard let previous = CloudflareDNSLedger.load(zone: zoneID) else { return [] }
        let changes = diffDNS(current: records, previous: previous)
        guard !changes.isEmpty else { return [] }

        return changes.prefix(dnsChangeCap).map { change in
            let thing = Thing(
                kind: .link,
                title: dnsTitle(change, zoneName: zoneName),
                content: dashboard.isEmpty ? "https://dash.cloudflare.com/" : "\(dashboard)/dns",
                source: "Cloudflare",
                capturedAt: .now,
                sourceRef: dnsRef(change)
            )
            if change.kind == .changed, let was = change.previousContent, !was.isEmpty {
                thing.summary = String(localized: "Was: \(was)")
            }
            return thing
        }
    }

    /// A change's identity. Keyed on `modified_on`, so the SECOND change to a
    /// record is a different thing than the first — key on the record id alone
    /// and every change after the first would dedupe silently out of existence.
    ///
    /// A removal has no new timestamp, and is detected exactly once (the id
    /// leaves the snapshot in the same pass), so a fixed suffix is stable.
    static func dnsRef(_ change: DNSChange) -> String {
        switch change.kind {
        case .removed: "cloudflare:dns:\(change.record.id):removed"
        case .added, .changed: "cloudflare:dns:\(change.record.id):\(change.record.modifiedOn)"
        }
    }

    static func dnsTitle(_ change: DNSChange, zoneName: String) -> String {
        let label = "\(change.record.type) \(change.record.name)"
        switch change.kind {
        case .added:
            return String(localized: "\(zoneName) — DNS record added: \(label)")
        case .removed:
            return String(localized: "\(zoneName) — DNS record removed: \(label)")
        case .changed:
            return String(localized: "\(zoneName) — DNS changed: \(label) → \(change.record.content)")
        }
    }

    // MARK: - Probe

    /// `-cloudflareProbe YES` — the read, phase by phase, against the STORED
    /// token. Bypasses nothing (there is no cache here) so a run is always a
    /// live measurement.
    ///
    /// One NSLog per line, never a joined multi-line message: the log reader
    /// truncates those mid-document, which is the `-todayProbe` lesson and cost
    /// a full debugging round when it was learned.
    ///
    /// The decisive lines are the STATUS of each endpoint and, per zone, the
    /// number of certificate packs beside the number that carried a readable
    /// expiry. A pack count of 3 with 0 dates is a field rename; a pack count
    /// of 0 is an account genuinely without certificates; a 403 is a token
    /// missing that permission. Those three are the same silence on screen.
    @MainActor
    static func diagnose() async {
        guard let token = TokenVault.get(TokenBridge.cloudflare.tokenKey) else {
            NSLog("[Casberi] cloudflare| no stored token — connect first with -tokenBridge \"Cloudflare:<token>\"")
            return
        }
        let auth = "Bearer \(token)"

        let verify = await IngestSupport.getJSONStatus("\(api)/user/tokens/verify", auth: auth)
        NSLog("[Casberi] cloudflare| verify HTTP %d %@", verify.status,
              verify.status == 401 ? "(token is not valid)"
                  : verify.status == 400 ? "(that isn't a token — check for stray whitespace)"
                  : verify.status == 200 ? "" : "(unexpected)")
        if let body = verify.json as? [String: Any],
           let info = body["result"] as? [String: Any] {
            NSLog("[Casberi] cloudflare| token status=%@ expires_on=%@",
                  (info["status"] as? String) ?? "MISSING",
                  (info["expires_on"] as? String) ?? "never")
        }
        guard verify.status == 200 else { return }

        let zonesResp = await IngestSupport.getJSONStatus("\(api)/zones?per_page=50", auth: auth)
        let zones = ((zonesResp.json as? [String: Any])?["result"] as? [[String: Any]]) ?? []
        NSLog("[Casberi] cloudflare| zones HTTP %d, %d zones%@", zonesResp.status, zones.count,
              zonesResp.status == 403 ? " (token lacks Zone:Read)" : "")
        if zones.count > zoneCap {
            NSLog("[Casberi] cloudflare| CAP: certificates read for %d of %d zones — %d not covered this pass",
                  zoneCap, zones.count, zones.count - zoneCap)
        }
        for zone in zones {
            NSLog("[Casberi] cloudflareZone| name=%@ status=%@ id=%@",
                  (zone["name"] as? String) ?? "MISSING",
                  (zone["status"] as? String) ?? "MISSING",
                  (zone["id"] as? String) ?? "MISSING")
        }

        for zone in zones.prefix(zoneCap) {
            guard let id = zone["id"] as? String,
                  let name = zone["name"] as? String else { continue }
            let resp = await IngestSupport.getJSONStatus(
                "\(api)/zones/\(id)/ssl/certificate_packs?status=all", auth: auth)
            let packs = ((resp.json as? [String: Any])?["result"] as? [[String: Any]]) ?? []
            // Packs that carried a date, vs packs that existed. The gap between
            // these two numbers is the only visible symptom of a field rename.
            let dated = packs.filter { pack in
                if IngestSupport.isoDate(pack["expires_on"]) != nil { return true }
                if ((pack["certificates"] as? [[String: Any]]) ?? []).contains(where: {
                    IngestSupport.isoDate($0["expires_on"]) != nil }) { return true }
                if let p = pack["primary_certificate"] as? [String: Any],
                   IngestSupport.isoDate(p["expires_on"]) != nil { return true }
                return false
            }.count
            NSLog("[Casberi] cloudflareCert| %@ HTTP %d packs=%d withDate=%d%@",
                  name, resp.status, packs.count, dated,
                  resp.status == 403 ? " (token lacks SSL and Certificates:Read)" : "")
        }

        // DNS. Four outcomes that look identical on screen and must not here:
        // the read failed, the zone is too big to diff safely, this is first
        // sight (seeded silently and CORRECTLY landing nothing), or it was read
        // and genuinely nothing moved.
        NSLog("[Casberi] cloudflare| dns ledger holds %d zones from previous passes",
              CloudflareDNSLedger.zoneCount)
        for zone in zones.prefix(zoneCap) {
            guard let id = zone["id"] as? String,
                  let name = zone["name"] as? String else { continue }
            guard let records = await allDNSRecords(zoneID: id, auth: auth) else {
                NSLog("[Casberi] cloudflareDNS| %@ UNREADABLE — the read failed, or the zone holds more than %d records and a partial diff would invent removals",
                      name, dnsPageCap * 100)
                continue
            }
            guard let previous = CloudflareDNSLedger.load(zone: id) else {
                NSLog("[Casberi] cloudflareDNS| %@ records=%d FIRST SIGHT — seeding silently, no rows (correct)",
                      name, records.count)
                continue
            }
            let changes = diffDNS(current: records, previous: previous)
            NSLog("[Casberi] cloudflareDNS| %@ records=%d remembered=%d changes=%d%@",
                  name, records.count, previous.count, changes.count,
                  changes.count > dnsChangeCap
                      ? " CAP: only \(dnsChangeCap) will land, \(changes.count - dnsChangeCap) dropped for good"
                      : "")
            for change in changes.prefix(dnsChangeCap) {
                NSLog("[Casberi] cloudflareDNSChange| %@ was=%@ ref=%@",
                      dnsTitle(change, zoneName: name),
                      change.previousContent ?? "—", dnsRef(change))
            }
        }

        let accountsResp = await IngestSupport.getJSONStatus("\(api)/accounts", auth: auth)
        let accounts = ((accountsResp.json as? [String: Any])?["result"] as? [[String: Any]]) ?? []
        NSLog("[Casberi] cloudflare| accounts HTTP %d, %d accounts", accountsResp.status, accounts.count)
        for account in accounts.prefix(3) {
            guard let id = account["id"] as? String else { continue }
            let resp = await IngestSupport.getJSONStatus(
                "\(api)/accounts/\(id)/registrar/domains", auth: auth)
            let domains = ((resp.json as? [String: Any])?["result"] as? [[String: Any]]) ?? []
            // 403 here is the EXPECTED answer for the many accounts that don't
            // use Cloudflare as a registrar — a skip, never a failure.
            NSLog("[Casberi] cloudflareRegistrar| account=%@ HTTP %d domains=%d%@",
                  id, resp.status, domains.count,
                  resp.status == 403 ? " (not a Registrar account, or token lacks the permission — expected for most)" : "")
            for domain in domains {
                NSLog("[Casberi] cloudflareDomain| name=%@ expires=%@ auto_renew=%@",
                      (domain["name"] as? String) ?? "MISSING",
                      String(describing: domain["expires_at"] ?? domain["expires_on"] ?? "MISSING"),
                      String(describing: domain["auto_renew"] ?? "MISSING"))
            }
        }

        // Finally the pass itself, so the probe's own reading and what the feed
        // would show can never disagree.
        let landed = await things(token: token) ?? []
        NSLog("[Casberi] cloudflare| would land %d alerts (covered %d refs)",
              landed.count, lastCovered.count)
        for thing in landed {
            NSLog("[Casberi] cloudflareRow| ref=%@ due=%@ title=%@",
                  thing.sourceRef ?? "nil",
                  thing.dueAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
                  thing.title)
        }
        if landed.isEmpty {
            NSLog("[Casberi] cloudflare| nothing to land — which is the HEALTHY answer if the counts above are non-zero")
        }
    }

    /// The zone's page on the dashboard. Cloudflare keys it by account id, which
    /// rides the zone payload — falling back to the bare dashboard rather than
    /// guessing an id, since a link to the wrong account is worse than a link
    /// to the front door.
    static func dashboardURL(zone: [String: Any], name: String) -> String {
        guard let account = zone["account"] as? [String: Any],
              let id = account["id"] as? String, !id.isEmpty else {
            return "https://dash.cloudflare.com/"
        }
        return "https://dash.cloudflare.com/\(id)/\(name)"
    }
}

/// What each zone's DNS looked like last pass — record id → its five fields.
///
/// UserDefaults rather than the Keychain: these are public records, readable by
/// anyone who can run `dig`, so they are not a secret. Cleared per zone when a
/// zone stops being read and wholesale on disconnect, so a reconnected
/// different account never diffs against a stranger's DNS.
enum CloudflareDNSLedger {
    private static let prefix = "cloudflare.dns."
    private static let indexKey = "cloudflare.dns.zones"

    static func load(zone: String) -> [String: [String]]? {
        UserDefaults.standard.dictionary(forKey: prefix + zone) as? [String: [String]]
    }

    static func save(_ snapshot: [String: [String]], zone: String) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot, forKey: prefix + zone)
        var zones = Set(defaults.stringArray(forKey: indexKey) ?? [])
        // The index exists so `clear()` can find every key it wrote. Without
        // it, disconnecting would leave one orphaned snapshot per zone in
        // UserDefaults forever, and reconnecting a different Cloudflare account
        // that happened to share a zone id would diff against it.
        if zones.insert(zone).inserted { defaults.set(Array(zones), forKey: indexKey) }
    }

    static func clear() {
        let defaults = UserDefaults.standard
        for zone in defaults.stringArray(forKey: indexKey) ?? [] {
            defaults.removeObject(forKey: prefix + zone)
        }
        defaults.removeObject(forKey: indexKey)
    }

    /// How many zones are remembered — the probe's way of separating "first
    /// sight, seeded silently" from "read and nothing moved".
    static var zoneCount: Int {
        (UserDefaults.standard.stringArray(forKey: indexKey) ?? []).count
    }
}

// MARK: - Reconcile

extension TokenIngest {

    /// Heals what's already landed, and closes what's been dealt with.
    ///
    /// Every Cloudflare row is a STATE wearing a date, not an event, so both
    /// halves of this matter and the generic ingest path does neither: it skips
    /// a known `sourceRef` entirely, which would freeze a certificate's due date
    /// at whatever it read the first time and leave a renewed certificate
    /// warning forever.
    ///
    /// - A row still present is HEALED — its date, title and summary are
    ///   rewritten from this pass, and a row that had been resolved comes back
    ///   to `.todo` if the condition returned.
    /// - A row that is absent but COVERED has been dealt with: the certificate
    ///   renewed, the domain was paid, the zone went active, the token was
    ///   replaced. It closes, and says so.
    /// - A row that is absent and NOT covered is left exactly as it was. This
    ///   is the case `CloudflareFetch.lastCovered` exists for — see its note.
    @MainActor
    static func reconcileCloudflare(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.compactMap { thing in
            thing.sourceRef.map { ($0, thing) }
        }, uniquingKeysWith: { a, _ in a })
        let covered = CloudflareFetch.lastCovered
        guard !covered.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Cloudflare" }))) ?? []
        var changed = false

        for thing in existing {
            guard let ref = thing.sourceRef else { continue }
            // DNS rows are EVENTS and are exempt from both halves of this.
            // They are absent from `fresh` on the very next pass by design —
            // a change reports once — so the resolve branch below would mark
            // every one of them done a minute after it landed, and the heal
            // branch has nothing to heal: what a record changed to on Tuesday
            // does not get rewritten by what it changed to on Friday, which is
            // a second, separate event with its own ref.
            if ref.hasPrefix("cloudflare:dns:") { continue }
            if let now = byRef[ref] {
                // Still true. Rewrite the reading — the date moves as a
                // certificate approaches, and the title counts down with it.
                if thing.dueAt != now.dueAt { thing.dueAt = now.dueAt; changed = true }
                if thing.title != now.title { thing.title = now.title; changed = true }
                if thing.summary != now.summary { thing.summary = now.summary; changed = true }
                if thing.mark != .todo { thing.mark = .todo; changed = true }
            } else if covered.contains(ref), thing.mark != .done {
                thing.mark = .done
                changed = true
                SourceMoments.shared.fire(
                    String(localized: "Sorted: \(thing.title)"), source: "Cloudflare")
            }
        }
        if changed { context.saveHonestly() }
    }
}
