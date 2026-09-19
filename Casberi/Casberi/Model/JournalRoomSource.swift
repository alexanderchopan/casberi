import Foundation

/// The two journal rooms (prd §398), the ONE place that membership is written
/// down. Their years head is DELETED (prd §832) — they lead with their newest
/// entry — and what reads this now is the anniversary: `FeedScreen` lets a
/// journal lead with "on this day" when an earlier year wrote on this date.
///
/// Obsidian is deliberately absent: a vault note is dated by its file's mtime,
/// so an edit moves a 2019 note to today and an anniversary over it would be
/// the anniversary of an edit.
enum JournalRoomSource {
    static let sources: Set<String> = ["Day One", "Apple Journal"]
}
