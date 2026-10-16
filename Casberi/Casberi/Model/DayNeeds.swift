import Foundation

/// **NEEDS YOU STAYS IN EACH PLACE, AND DAY GATHERS THEM ALL (prd §1327 item
/// 9).** The Wallet keeps its stuck transfer and price rise (`WalletNeedsYou`),
/// Work its asks (`WorkAsk`); Day leads its list with every one, each row
/// naming the place it came from. Nothing new decides what needs you: each
/// place's own rule answers, and this only gathers.
///
/// Foundation-only: `scripts/day-needs-selftest.sh` compiles it whole with
/// `ObjectFold.swift`, `WorkAsk.swift` and `WorkStage.swift`.
enum DayNeeds {

    /// One row of Day's Needs you: the thing, the place whose list it is on,
    /// and when it landed.
    struct Item: Equatable, Sendable {
        let id: UUID
        let place: String
        let at: Date
    }

    /// Every place's list as Day's one list: newest first, a thing two places
    /// hold standing once, under the first place to name it (places are handed
    /// in Day's order), and a tie on time kept in that order.
    static func gather(_ places: [[Item]]) -> [Item] {
        var seen = Set<UUID>()
        var kept: [(order: Int, item: Item)] = []
        for item in places.joined() where seen.insert(item.id).inserted {
            kept.append((kept.count, item))
        }
        return kept.sorted { a, b in
            a.item.at != b.item.at ? a.item.at > b.item.at : a.order < b.order
        }
        .map(\.item)
    }

    /// One row of the Work room as its Needs you reads it: the object it is
    /// about (`ObjectFold.key`, nil when it names none) and its primitives.
    struct WorkRow {
        let id: UUID
        let at: Date
        let key: String?
        let row: WorkStage.Row
    }

    /// Work's Needs you, exactly as Work's Coming up draws it (prd §1079,
    /// §1080): the room folded to one row per object, its newest state, then
    /// `WorkAsk.needsYou` over what stands — so an incident later resolved has
    /// already left. Newest first.
    static func workAsks(_ rows: [WorkRow], place: String, now: Date) -> [Item] {
        let hidden = ObjectFold.folded(rows.map { ObjectFold.Row(id: $0.id, key: $0.key, at: $0.at) })
        return rows
            .filter { !hidden.contains($0.id) && WorkAsk.needsYou($0.row, at: $0.at, now: now) }
            .sorted { $0.at > $1.at }
            .map { Item(id: $0.id, place: place, at: $0.at) }
    }
}
