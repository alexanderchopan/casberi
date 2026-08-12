import Foundation
import SwiftData

/// 1Claw (2026-07-17) — the agent secrets vault, read side only. 1Claw holds
/// API keys for AI agents behind scoped, human-granted policies; connecting it
/// here answers "what can this key actually reach" with the vault's own
/// records. An agent API key (`ocv_…`, minted in the 1Claw dashboard)
/// exchanges for a short-lived JWT at the documented auth endpoint, then the
/// key's own view lands: every vault it can see, and each vault's grant table
/// — one thing per policy, wearing the secret path pattern and permissions
/// the grant actually names. Metadata only, by construction: nothing here
/// ever reads a secret VALUE, signs, or spends — the endpoints called can't.
///
/// Honesty ceiling (built against OpenAPI spec 2.27.0, unmeasured against the
/// live API — re-measure before hardening): a minimally-scoped key may lack
/// `policies:read`, so a vault's grant read can come back empty-handed. That
/// degrades to the vaults themselves with no grant rows — the feed never
/// invents a grant table it couldn't read. A grant's `expires_at` lands in
/// `dueAt` (a real structured deadline), though the Coming up lane reads only
/// reminders today — surfacing expiring access there is a separate ruling.
enum OneClawFetch {

    static let api = "https://api.1claw.xyz/v1"
    /// Where a grant row opens — the 1Claw dashboard. The API documents no
    /// per-vault web permalink; the root is the honest destination.
    static let dashboard = "https://1claw.xyz"

    /// True for a grant thing's ref — the classification the lede needs,
    /// owned here beside the ref it mints (`policyThing`).
    static func isGrantRef(_ ref: String?) -> Bool {
        ref?.hasPrefix("1claw:policy:") ?? false
    }

    /// The key's whole view: exchange → vaults → per-vault grant tables
    /// (bounded fan-out, the ingest norm). Returns nil only when the exchange
    /// or the VAULTS read fails — the honest key-rejected signal TokenIngest
    /// words as "check the token". The spec doesn't require the `vaults`
    /// envelope key, so a valid key with zero vaults (omitted or JSON-null
    /// list) is an EMPTY reach, not a rejected key. A per-vault policies read
    /// failing just means that vault lands no grant rows (its most likely
    /// cause is a key without `policies:read`).
    ///
    /// Grants are MUTABLE records — a policy can be edited or revoked under
    /// the same id — so unlike an append-only bridge this fetch also
    /// RECONCILES the corpus: an already-landed grant's title/`dueAt` follow
    /// the record, and a grant that vanished from the tables is deleted.
    /// Deletion only runs when EVERY vault's table was actually readable —
    /// with one table unreadable, "revoked" and "couldn't read" are
    /// indistinguishable, and guessing would erase real grants.
    @MainActor
    static func things(token: String, context: ModelContext) async -> [Thing]? {
        guard let jwt = await exchange(key: token) else { return nil }
        let auth = "Bearer \(jwt)"
        guard let vaultsRoot = await IngestSupport.getJSON("\(api)/vaults", auth: auth)
                as? [String: Any] else { return nil }
        let vaults = (vaultsRoot["vaults"] as? [[String: Any]]) ?? []

        let tables = await IngestSupport.boundedGather(vaults, maxConcurrent: 4) { vault in
            await policyTable(vault, auth: auth)
        }
        var things: [Thing] = []
        var allReadable = true
        for table in tables {
            guard let table else { allReadable = false; continue }
            things += table
        }
        reconcile(incoming: things, complete: allReadable, context: context)
        OneClawAccess.set(vaults: vaults.count)
        return things
    }

    /// One vault's grant table as things — nil when the read itself failed
    /// (vs. an empty-but-readable table), the distinction `reconcile` needs.
    private static func policyTable(_ vault: [String: Any], auth: String) async -> [Thing]? {
        guard let vaultID = vault["id"] as? String else { return [] }
        let vaultName = (vault["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let root = await IngestSupport.getJSON("\(api)/vaults/\(vaultID)/policies",
                                                     auth: auth) as? [String: Any]
        else { return nil }
        return ((root["policies"] as? [[String: Any]]) ?? [])
            .compactMap { policyThing($0, vaultName: vaultName) }
    }

    /// Landed grant rows follow the live record: an edited policy's row takes
    /// the new title/expiry in place (TokenIngest's dedupe would otherwise
    /// freeze it at first landing), and — only when the read was `complete` —
    /// a revoked policy's row is deleted, Spotlight included. Without this,
    /// the feed overstates the key's reach, the one failure a grants surface
    /// must not have.
    @MainActor
    private static func reconcile(incoming: [Thing], complete: Bool, context: ModelContext) {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "1Claw" })
        guard let landed = try? context.fetch(descriptor) else { return }
        let grants = landed.filter { isGrantRef($0.sourceRef) }
        guard !grants.isEmpty else { return }
        let byRef = Dictionary(incoming.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { first, _ in first })
        var changed = false
        var removedIDs: [UUID] = []
        for grant in grants {
            guard let ref = grant.sourceRef else { continue }
            if let fresh = byRef[ref] {
                // The stamped parts heal here too (prd §367), and this pass is
                // the ONLY thing that will ever reach a grant landed before
                // they existed: `TokenIngest`'s dedupe drops the incoming row
                // on the ref, so a re-read cannot re-land one. Without it the
                // sheet's grant anatomy would reach only grants created from
                // this build on, which is indistinguishable from it not
                // working at all.
                if grant.title != fresh.title || grant.dueAt != fresh.dueAt
                    || grant.summary != fresh.summary
                    || grant.authorHandle != fresh.authorHandle
                    || grant.tags != fresh.tags {
                    grant.title = fresh.title
                    grant.dueAt = fresh.dueAt
                    grant.summary = fresh.summary
                    grant.authorHandle = fresh.authorHandle
                    grant.tags = fresh.tags
                    changed = true
                }
            } else if complete {
                removedIDs.append(grant.id)
                context.delete(grant)
                changed = true
            }
        }
        if changed {
            context.saveHonestly()
            SpotlightIndex.remove(ids: removedIDs)
        }
    }

    /// The facet naming what a grant IS (§308). Every OTHER tag on one of
    /// these rows is a permission the API reported.
    static let grantTag = "Grant"

    /// A grant: "Prod · secrets/anthropic/* · read, rotate" — the vault, the
    /// secret path pattern, and the permissions, all straight off the policy
    /// record. Dated when the grant was created; an expiring grant carries
    /// its deadline in `dueAt`.
    ///
    /// **The three parts are ALSO stamped as fields (prd §367).** The title is
    /// one slot, so they were joined into it and clamped at 80 — and the sheet
    /// that wants to draw a permission then has to split a display string back
    /// apart, which is the very thing `WorkStage`'s central rule forbids. The
    /// join stays (the row is unchanged); the parts now ride fields the sheet
    /// can read without guessing:
    ///
    /// - `summary` — the path pattern, the grant's whole payload, and display
    ///   copy in the same sense a Trello card's back is.
    /// - `authorHandle` — the vault, the field `WorkStage` already treats as
    ///   "the thing this belongs to".
    /// - `tags` — the facet, then the permissions in the API's OWN words, so a
    ///   security decision is never restated in ours (and so `Set(tags)` can
    ///   answer "what can be written?" as an ordinary §308 filter).
    ///
    /// All three are existing properties, so **no CloudKit Production deploy**.
    private static func policyThing(_ policy: [String: Any], vaultName: String?) -> Thing? {
        guard let id = policy["id"] as? String,
              let pattern = policy["secret_path_pattern"] as? String else { return nil }
        let permissions = (policy["permissions"] as? [String]) ?? []
        var parts = [pattern]
        if let vaultName { parts.insert(vaultName, at: 0) }
        if !permissions.isEmpty { parts.append(permissions.joined(separator: ", ")) }
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(parts.joined(separator: " · ")),
            content: dashboard,
            source: "1Claw",
            capturedAt: IngestSupport.isoDate(policy["created_at"]) ?? .now,
            tags: [grantTag] + permissions.filter { !$0.isEmpty },
            sourceRef: "1claw:policy:\(id)"
        )
        thing.dueAt = IngestSupport.isoDate(policy["expires_at"])
        thing.summary = pattern
        thing.authorHandle = vaultName
        return thing
    }

    /// The documented exchange: the pasted key for a short-lived JWT. An
    /// agent key (`ocv_…`) auto-resolves its agent at the agent endpoint; any
    /// other shape is treated as a human's user API key and exchanged at the
    /// user endpoint. Both take just `{api_key}` and answer `access_token`.
    /// One fetch outlives no JWT, so no refresh handling.
    private static func exchange(key: String) async -> String? {
        let path = key.hasPrefix("ocv_") ? "auth/agent-token" : "auth/api-key-token"
        guard let root = await IngestSupport.postJSON("\(api)/\(path)",
                                                      body: ["api_key": key]) as? [String: Any]
        else { return nil }
        return root["access_token"] as? String
    }

    #if DEBUG
    /// The `-oneclawProbe` walk: every step NSLogged, so "the key can't read
    /// policies" and "there are no policies" stop looking identical — for
    /// this bridge that distinction IS the feature. Reads the stored token.
    static func probe() async {
        guard let token = TokenVault.get(TokenBridge.oneclaw.tokenKey) else {
            NSLog("1Claw probe: no stored key — connect first (-tokenBridge \"1Claw:<key>\")")
            return
        }
        guard let jwt = await exchange(key: token) else {
            NSLog("1Claw probe: key exchange FAILED (bad key, or the API is unreachable)")
            return
        }
        let auth = "Bearer \(jwt)"
        if let me = await IngestSupport.getJSON("\(api)/agents/me", auth: auth)
            as? [String: Any] {
            let scopes = (me["scopes"] as? [String]) ?? []
            NSLog("1Claw probe: agent %@, scopes [%@]",
                  (me["name"] as? String) ?? "?", scopes.joined(separator: ", "))
        } else {
            NSLog("1Claw probe: agents/me unreadable (a user key, or no agents:read)")
        }
        guard let vaultsRoot = await IngestSupport.getJSON("\(api)/vaults", auth: auth)
                as? [String: Any] else {
            NSLog("1Claw probe: vaults read FAILED")
            return
        }
        let vaults = (vaultsRoot["vaults"] as? [[String: Any]]) ?? []
        NSLog("1Claw probe: %d vaults", vaults.count)
        for vault in vaults {
            guard let id = vault["id"] as? String else { continue }
            let name = (vault["name"] as? String) ?? id
            if let root = await IngestSupport.getJSON("\(api)/vaults/\(id)/policies",
                                                      auth: auth) as? [String: Any],
               let policies = root["policies"] as? [[String: Any]] {
                NSLog("1Claw probe: vault %@ — %d grants", name, policies.count)
            } else {
                NSLog("1Claw probe: vault %@ — grants UNREADABLE (no policies:read?)", name)
            }
        }
    }
    #endif
}

/// The reachable-vault count, cached for the feed's lede. UserDefaults, not
/// the corpus — a count is a reading, not a thing. `formatted` is nil until a
/// read has actually landed, so the lede never invents a zero; `clear()`
/// drops it when the key is removed, so a reconnected DIFFERENT key never
/// wears the prior one's reach.
enum OneClawAccess {
    private static let vaultsKey = "oneclaw.access.vaults"

    static func set(vaults: Int) {
        UserDefaults.standard.set(vaults, forKey: vaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: vaultsKey)
    }

    static var formatted: String? {
        guard UserDefaults.standard.object(forKey: vaultsKey) != nil else { return nil }
        let n = UserDefaults.standard.integer(forKey: vaultsKey)
        return n == 1 ? "1 vault" : "\(n) vaults"
    }
}
