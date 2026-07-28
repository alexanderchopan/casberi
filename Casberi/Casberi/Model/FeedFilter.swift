import Foundation
import Observation

/// Feed's filter state, shared — Home's kind bar sets it (a segment tap
/// lands you in the filtered feed), Feed's chips read and write it, and the
/// casberi://feed/type/<Tag> route drives it from anywhere.
@Observable
final class FeedFilter {
    static let shared = FeedFilter()

    /// Content-first landing (reverted 2026-07-28: §131's amendment that made
    /// this persist "wherever you left it" is undone per user feedback — the
    /// app always opens on "All" now).
    var source = "All"
    var tag = "All"

    private init() {}

    func clear() { source = "All"; tag = "All" }
}
