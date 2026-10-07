import Foundation

/// An app that stopped letting us in, said once in that category's digest
/// (prd §1162).
///
/// A refused key or a lapsed session is no row: nothing lands, and the
/// corpus sweep only speaks about rows, so a dead connection went untold —
/// the feed just went quiet, which reads as "nothing happened". This composes
/// one plan per break from `BridgeHealth`'s sticky refusal stamp, merged into
/// `WalletBackgroundRefresh.runNotifySweep`'s one submit as `DevnetNotify`'s
/// plans are, so it waits for the evening digest with everything else (it is
/// not one of `standsAlone`'s kinds — a reconnect keeps until then).
///
/// **Once per break, never per sweep.** The id carries the moment the refusals
/// began, so the ledger's "fires once, ever" holds while it stays broken, and
/// a break that heals and recurs is new news.
enum ReconnectNotify {
    /// `seats` is every app you have added, as (id, name). A refusal stamped
    /// for an app you never connected — a mistyped key on its connect page,
    /// refused and discarded — is not a connection that broke, so it is never
    /// said. `BridgeHealth` keys on whatever `NetworkReach` names the bridge,
    /// which is the seat id for some ("cloudflare") and the name for others
    /// ("Linear"), so both are matched and the name is what is said.
    static func plans(seats: [(id: String, name: String)]) -> [NotifyPlan] {
        var display: [String: String] = [:]
        for seat in seats { display[seat.id] = seat.name; display[seat.name] = seat.name }
        let refused = BridgeHealth.allNeedingReconnect().compactMap { key -> (name: String, since: Date)? in
            guard let name = display[key], let since = BridgeHealth.needsReconnect(key) else { return nil }
            return (name: name, since: since)
        }
        return plans(refused: refused)
    }

    /// Pure over its input, for the harness.
    static func plans(refused: [(name: String, since: Date)]) -> [NotifyPlan] {
        refused.map { seat in
            NotifyPlan(
                id: "broken:\(seat.name):\(Int(seat.since.timeIntervalSince1970))",
                kind: .connectionBroken,
                title: NotifyKind.connectionBroken.headline,
                body: String(localized: "\(seat.name) stopped letting us in. Nothing new arrives until you reconnect it."),
                // No per-app door exists as a link; opening the app lands on
                // Home, whose first rows name what needs reconnecting.
                link: nil,
                occurredAt: seat.since,
                source: seat.name,
                place: seat.name)
        }
    }
}
