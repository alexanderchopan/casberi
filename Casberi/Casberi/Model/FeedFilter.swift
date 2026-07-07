import Foundation
import Observation

/// Feed's filter state, shared — Home's kind bar sets it (a segment tap
/// lands you in the filtered feed), Feed's chips read and write it, and the
/// casberi://feed/type/<Tag> route drives it from anywhere.
@Observable
final class FeedFilter {
    static let shared = FeedFilter()
    var source = "All"
    var tag = "All"

    func clear() { source = "All"; tag = "All" }
}
