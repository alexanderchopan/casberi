import Foundation
import SwiftData

/// Which apps can post as you (2026-07-31).
///
/// A Farcaster account doesn't sign its own casts — apps do, on your behalf,
/// through SIGNERS you grant them. Every grant and every revocation is an
/// onchain event on the Key Registry (Optimism), and the same keyless
/// Snapchain node that serves casts serves those events too.
///
/// **This is `WalletApprovals` applied to social identity**, and it inherits
/// that whole doctrine. An approval is "this contract may move your tokens"; a
/// signer is "this app may speak as you" — the same shape of standing
/// permission, the same tendency to accumulate silently over years, and the
/// same fact that nobody ever reviews the list. It also inherits prd §112's
/// preparing-surface ruling without argument: this READS and PREVIEWS, and the
/// revoke happens where revokes happen. Each landed thing links to Farcaster's
/// own connected-apps settings, exactly as an approval links to Revoke.cash.
///
/// Gated on `mine` — the apps that can speak as someone ELSE are neither your
/// business nor useful to you.
///
/// **UNMEASURED (2026-07-31)**: built against the hub HTTP API's documented
/// shape with no network egress from the authoring host. Three things to check
/// against a live node before trusting it, all of which fail SAFE (they make
/// the read say less, never say something false):
///  1. which endpoint carries REMOVES — `onChainEventsByFid` with an
///     `event_type` filter is asked first for exactly this reason, since
///     `onChainSignersByFid` may serve only signers currently active;
///  2. the envelope key (`events`), and whether `blockTimestamp` is seconds;
///  3. the metadata decode below, which is the only guess with a wrong answer
///     available to it — hence `plausibleFid`.
enum FarcasterSigners {

    private static let node = "https://snap.farcaster.xyz:3381"

    /// Where a grant is actually revoked. The landed thing's `content`, so
    /// opening one goes straight to the surface that can act (prd §112).
    static let revokeURL = "https://farcaster.xyz/~/settings/connected-apps"

    /// Highest block already landed, per fid — so a later pass lands only what
    /// is new. First sight has none: see `sync`.
    private static func cursorKey(_ fid: Int) -> String { "farcaster.signers.\(fid)" }

    /// Reads the signer events for one fid and lands what's new.
    ///
    /// **First sight lands the CURRENT INVENTORY, and this is a deliberate
    /// divergence** from the seed-silently rule the wallet sweeps follow
    /// (Peer, Morpho, Hyperliquid). Those seed silently because their first
    /// read is a STATE that would arrive wearing today's date and read as news
    /// that just happened. A signer event carries its own block timestamp, so
    /// the inventory sorts to where it actually belongs in the feed — years
    /// back, where it can't fake urgency — and the list of apps that can speak
    /// as you is precisely the thing you have never once been shown. The
    /// news-only MOMENT rule still holds: nothing older than a day says a word.
    ///
    /// Returns how many landed.
    @MainActor
    static func sync(fid: Int, existing: inout Set<String>,
                     context: ModelContext) async -> Int {
        guard let events = await events(fid: fid), !events.isEmpty else { return 0 }
        let key = cursorKey(fid)
        let cursor = UserDefaults.standard.object(forKey: key) as? Int
        var highest = cursor ?? 0
        var added = 0

        for event in events {
            guard let body = event["signerEventBody"] as? [String: Any] else { continue }
            let block = event["blockNumber"] as? Int ?? 0
            highest = max(highest, block)
            // Strictly newer than the cursor, so a re-read of the same page
            // lands nothing. The ref dedupe below is the belt to this braces —
            // a chain reorg or a missing block number can't double-land.
            if let cursor, block <= cursor { continue }

            let granted = (body["eventType"] as? String)?.hasSuffix("_ADD") ?? false
            let ref = signerRef(event: event, body: body, granted: granted)
            guard !existing.contains(ref) else { continue }

            let app = await appName(metadata: body["metadata"] as? String)
            let when = (event["blockTimestamp"] as? Double).map(Date.init(timeIntervalSince1970:))
            let thing = Thing(
                kind: .link,
                title: title(app: app, granted: granted),
                content: revokeURL,
                source: "Farcaster",
                capturedAt: when ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            existing.insert(ref)
            added += 1
        }
        if highest > 0 { UserDefaults.standard.set(highest, forKey: key) }
        return added
    }

    /// Forgets a fid's cursor — teardown, so reconnecting re-lands the
    /// inventory rather than starting blind halfway through history.
    static func forget(fid: Int) {
        UserDefaults.standard.removeObject(forKey: cursorKey(fid))
    }

    /// Every signer event for a fid, newest last.
    ///
    /// `onChainEventsByFid` is asked FIRST because it is the one that can
    /// carry REMOVES: `onChainSignersByFid` may answer with only the signers
    /// currently active, which would make a revocation — the event most worth
    /// seeing — invisible. The second call is a fallback, not a preference, so
    /// a node that doesn't serve the filtered form still gives the grants.
    private static func events(fid: Int) async -> [[String: Any]]? {
        for path in ["onChainEventsByFid?fid=\(fid)&event_type=EVENT_TYPE_SIGNER",
                     "onChainSignersByFid?fid=\(fid)"] {
            guard let root = await IngestSupport.getJSON("\(node)/v1/\(path)") as? [String: Any],
                  let events = root["events"] as? [[String: Any]], !events.isEmpty
            else { continue }
            return events
        }
        return nil
    }

    /// A signer event's stable identity. The transaction hash plus its log
    /// index is exact and is what the wallet approvals sweep keys on; the
    /// key-plus-verb fallback covers a node that omits either, and still can't
    /// collide across grant/revoke of the same key.
    private static func signerRef(event: [String: Any], body: [String: Any],
                                  granted: Bool) -> String {
        let verb = granted ? "add" : "remove"
        if let tx = event["transactionHash"] as? String, !tx.isEmpty {
            return "farcaster:signer:\(verb):\(tx):\(event["logIndex"] as? Int ?? 0)"
        }
        return "farcaster:signer:\(verb):\(body["key"] as? String ?? "unknown")"
    }

    /// "Gave Warpcast permission to post as you" / "Revoked Warpcast's
    /// permission to post as you", and the honest unnamed forms.
    ///
    /// An app is NAMED only when the metadata decoded to a plausible fid AND
    /// that fid resolved to a real profile. Anything less says "an app" — the
    /// honesty rule's plainest application, and it matters more here than
    /// most: a wrong name on a permission notice tells you to go revoke the
    /// wrong thing.
    private static func title(app: String?, granted: Bool) -> String {
        switch (app, granted) {
        case let (.some(app), true):
            return String(localized: "Gave \(app) permission to post as you")
        case let (.some(app), false):
            return String(localized: "Revoked \(app)'s permission to post as you")
        case (nil, true):
            return String(localized: "An app was given permission to post as you")
        case (nil, false):
            return String(localized: "An app's permission to post as you was revoked")
        }
    }

    /// The requesting app's display name, out of the signer's metadata.
    ///
    /// The metadata is a base64 `SignedKeyRequestMetadata`, ABI-encoded:
    /// `(uint256 requestFid, address requestSigner, bytes signature, uint256
    /// deadline)`. Because the struct holds a dynamic member it is encoded
    /// behind a leading offset word, so `requestFid` is the SECOND 32-byte
    /// word. Both readings are tried — with and without that leading offset —
    /// and each is accepted only if it looks like an fid at all, because this
    /// is the one place in the read where a confident wrong answer is
    /// available: any 32 bytes decode to SOME integer.
    @MainActor
    private static func appName(metadata: String?) async -> String? {
        guard let metadata, let data = Data(base64Encoded: metadata) else { return nil }
        for wordIndex in [1, 0] {
            guard let fid = plausibleFid(data, wordIndex: wordIndex) else { continue }
            guard let profile = await FarcasterIngest.profile(fid: fid) else { continue }
            if let name = profile.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            if let username = profile.username, !username.isEmpty { return "@\(username)" }
        }
        return nil
    }

    /// The 32-byte word at `wordIndex` read as an fid, or nil when it can't be
    /// one. Farcaster fids are small, dense and monotonic — a few million
    /// after years — so a word that is zero, or that carries any of the upper
    /// 24 bytes, is an address, a deadline, or a signature, not an fid.
    private static func plausibleFid(_ data: Data, wordIndex: Int) -> Int? {
        let start = wordIndex * 32
        guard data.count >= start + 32 else { return nil }
        let word = data[data.index(data.startIndex, offsetBy: start)..<data.index(
            data.startIndex, offsetBy: start + 32)]
        // Anything above the low SIX bytes means this word isn't a small
        // integer. Six, not eight, so the shift below cannot overflow Int on
        // the very input this guard exists to reject.
        guard word.prefix(26).allSatisfy({ $0 == 0 }) else { return nil }
        let value = word.suffix(6).reduce(0) { $0 << 8 | Int($1) }
        return (1...100_000_000).contains(value) ? value : nil
    }
}
