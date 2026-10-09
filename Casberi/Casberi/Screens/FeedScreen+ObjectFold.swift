import SwiftData
import SwiftUI

// ONE ROW PER OBJECT IN WORK AND MEDIA'S READ (prd §1079, §1204, `Model/ObjectFold.swift`).
//
// The key is read off a row's link, which is `content` — a heavy column the
// merged room's query leaves out (`lightColumns`), so reading it in a body
// would fault the room's 600 rows back in on the main actor. The keys are
// computed instead once per corpus revision, on a context of their own off
// the main actor, and the body folds with a dictionary lookup per row.
extension FeedScreen {
    /// Work or Reading, else nil (no fold).
    var objectFoldRoom: ObjectFold.Room? { ObjectFold.Room(room: source) }

    /// What the keys are computed against: the room and any change to the
    /// corpus. Empty outside the two rooms, so the task does nothing there.
    var objectFoldKey: String {
        guard objectFoldRoom != nil else { return "" }
        return "\(source)|\(CorpusSignal.shared.revision)"
    }

    /// The room's object keys, off the main actor: the same rows the room's
    /// query reads (its members, newest first, its bound), each row's key.
    func recomputeObjectKeys() async {
        guard let room = objectFoldRoom else {
            if !objectKeys.isEmpty { objectKeys = [:] }
            return
        }
        // Media's keys are its Read half's (prd §1204): a video or a song
        // saved twice is two plays, never one object.
        let members = RoomAccounts.roomSources(source == RoomAccounts.mediaRoom ? RoomAccounts.readingRoom : source)
        let container = modelContext.container
        let limit = Self.sourceRoomFetchLimit
        let keys = await Task.detached(priority: .utility) { () -> [UUID: String] in
            let context = ModelContext(container)
            var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = limit
            let rows = (try? context.fetch(d)) ?? []
            var out: [UUID: String] = [:]
            for thing in rows {
                if let key = ObjectFold.key(room: room, source: thing.source, link: thing.content) {
                    out[thing.id] = key
                }
            }
            return out
        }.value
        guard !Task.isCancelled else { return }
        if keys != objectKeys { objectKeys = keys }
    }

    /// `visible` with every object's older rows folded under its newest. A
    /// row whose key has not been read yet stands, so the first frame is the
    /// unfolded room and never an emptier one.
    func objectFolded(_ visible: [Thing]) -> [Thing] {
        guard objectFoldRoom != nil, !objectKeys.isEmpty else { return visible }
        let live = visible.live
        let hidden = ObjectFold.folded(live.map {
            ObjectFold.Row(id: $0.id, key: objectKeys[$0.id], at: $0.capturedAt)
        })
        return hidden.isEmpty ? live : live.filter { !hidden.contains($0.id) }
    }
}
