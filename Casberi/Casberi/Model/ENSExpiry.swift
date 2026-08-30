import Foundation
import SwiftData

/// ENS names expire, and until now Casberi had no way to say so (2026-07-21,
/// the second customer for the forward-deadline chip — 1Claw grants were the
/// first). A lapsed name silently stops resolving, every app that showed it
/// falls back to a hash, and the only warning is an email you may not read.
///
/// Keyless, and no on-chain call. Expiry lives on the `.eth` BaseRegistrar as
/// `nameExpires(uint256 labelhash)`, which would need keccak256 the app has no
/// implementation of — but ENS's own metadata service answers BY NAME and
/// carries the same fact as an "Expiration Date" attribute (measured
/// 2026-07-21). One GET per name, no key, no hashing.
///
/// Reads only the names Casberi can already SEE: a watched address the person
/// typed as a name, and the primary name an address reverse-resolves to. There
/// is deliberately no attempt to enumerate every name a wallet owns — that
/// needs an indexer (the ENS subgraph, which now wants an API key), and a
/// partial list presented as complete would be the kind of quiet lie the
/// honesty rule exists to prevent. What lands is what we can stand behind.
@MainActor
enum ENSExpiry {

    /// The `.eth` BaseRegistrar — the NFT contract the metadata service keys
    /// on. Only `.eth` names have a registrar expiry at all; a DNS-imported
    /// name (`.com`, `.xyz`) expires with its DNS registration, somewhere this
    /// endpoint can't see, so those are skipped rather than guessed at.
    private static let baseRegistrar = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85"

    /// How far ahead a name has to be expiring before it becomes a thing.
    /// Without a horizon every watched name would land a row expiring in 2048
    /// (vitalik.eth's real date) and sit in the feed forever — a deadline is
    /// news when it is near, and noise when it isn't.
    ///
    /// The number lives in `ENSName` since 2026-08-29 (prd §533), with the rest
    /// of the ladder. Two spellings of one horizon drift, and then a name is
    /// news in one room and not in the other.
    private static var horizonDays: Int { ENSName.horizonDays }

    /// How far into the PAST an expiry still earns a row. ENS gives a lapsed
    /// name a 90-day grace period in which the owner — and only the owner — can
    /// still renew it, so a just-expired name is the most actionable state
    /// there is, not the least. Past the grace period the name is released to
    /// anyone and there is nothing left to tell its old owner.
    ///
    /// Found by verification: a watched wallet's own reverse name (`031.eth`)
    /// had expired a month earlier and landed a row reading "expires Jun 20",
    /// present tense, about something already gone.
    private static var graceDays: Int { ENSName.graceDays }

    /// Lands (or reconciles) an expiry row per readable name. Returns the
    /// number of NEW things, or nil if nothing could be read at all — the same
    /// "reached?" convention `WalletIngest`'s other arms use, so a network
    /// hiccup never reads as "nothing expiring".
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        let names = await candidateNames(addresses, context: context)
        guard !names.isEmpty else { return 0 }
        guard let horizon = Calendar.current.date(byAdding: .day, value: horizonDays, to: .now),
              let graceFloor = Calendar.current.date(byAdding: .day, value: -graceDays, to: .now)
        else { return nil }

        var added = 0
        var reached = false
        for name in names {
            guard let expiry = await expiryDate(for: name) else { continue }
            reached = true
            let ref = ENSName.walletRef(for: name)
            // Reconcile before landing: a renewal MOVES the date, and the row
            // has to follow it rather than keep claiming the old one (the
            // lesson `OneClawBridge` records for grants).
            if existing.contains(ref) {
                let fresh = ENSName.title(name: name, expiry: expiry)
                if let landed = try? context.fetch(
                    FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })).first,
                   landed.dueAt != ENSName.nextCliff(expiry: expiry) || landed.title != fresh {
                    // The TITLE is compared too, not just the date: a row
                    // crossing from "expires" to "expired" does so with its
                    // date unchanged — only `now` moved past it. Reconciling on
                    // the date alone would leave it in the present tense forever.
                    // The NEXT cliff, not the expiry (prd §533): a lapsed name
                    // used to sit ninety days overdue against a date that had
                    // stopped being the question, while the moment that
                    // actually mattered — grace ending — passed unannounced.
                    landed.dueAt = ENSName.nextCliff(expiry: expiry)
                    landed.title = fresh
                }
                continue
            }
            guard expiry <= horizon, expiry >= graceFloor else { continue }
            let thing = Thing(
                kind: .link,
                title: ENSName.title(name: name, expiry: expiry),
                content: "https://app.ens.domains/\(name)",
                source: "Wallet",
                capturedAt: .now,
                sourceRef: ref
            )
            thing.dueAt = ENSName.nextCliff(expiry: expiry)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        return reached || names.isEmpty ? added : nil
    }

    /// The row's words and its next deadline both come from `ENSName` since
    /// 2026-08-29 (prd §533) — one ladder, so a name found from a wallet and a
    /// name somebody followed can never disagree about where it stands. The
    /// wording rules this function used to hold are recorded there.
    /// The names worth asking about: what the person typed, plus what each
    /// address says it goes by. Deduped, `.eth` only, lowercased.
    ///
    /// **A name the ENS seat FOLLOWS is dropped here** (2026-08-29, prd §533).
    /// That seat owns the same name under `ens:name:<name>`, in its own room,
    /// and adopts this row when somebody follows it — so leaving the name in
    /// this list would have the two halves reconciling two rows about one
    /// deadline, one of which the wallet would keep re-landing after the seat
    /// had taken it. One name, one row.
    private static func candidateNames(_ addresses: [String],
                                       context: ModelContext) async -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ raw: String?) {
            guard let raw else { return }
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // `.eth` only, and never a subname — a subname's lifetime is its
            // parent's to manage and the registrar has no record of its own.
            guard n.hasSuffix(".eth"), n.split(separator: ".").count == 2,
                  seen.insert(n).inserted else { return }
            out.append(n)
        }
        for watched in WalletStore.shared.addresses { add(watched.address) }
        for address in addresses { add(await ENS.reverseName(for: address)) }
        let followed = Set(ENSWatch.followed(context: context))
        return out.filter { !followed.contains($0) }
    }

    /// The expiry the metadata service reports, as a date. The attribute is
    /// epoch MILLISECONDS (measured) — reading it as seconds would put every
    /// name's expiry in 1970 and make each one permanently, silently overdue.
    private static func expiryDate(for name: String) async -> Date? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let root = await IngestSupport.getJSON(
                "https://metadata.ens.domains/mainnet/\(baseRegistrar)/\(encoded)") as? [String: Any],
              let attributes = root["attributes"] as? [[String: Any]]
        else { return nil }
        for attribute in attributes where attribute["trait_type"] as? String == "Expiration Date" {
            if let ms = attribute["value"] as? Double, ms > 0 {
                return Date(timeIntervalSince1970: ms / 1000)
            }
        }
        return nil
    }
}
