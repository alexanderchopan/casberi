import Foundation

/// WHAT NEEDS YOU IN WORK, BESIDE WHAT IS DUE (prd §1080).
///
/// Coming up held only rows with a date ahead, so the asks with no date — a
/// review requested, an issue assigned, a mention, a build that broke, an
/// incident still firing — never reached it. They lead it now, newest first,
/// above the deadlines (the Wallet's "need you now" over its bills, §1078).
///
/// **Stable signals only**, `WorkStage`'s rule: a tag a bridge stamps in
/// English, a state Apple or AWS spells in a ref, never a localized title.
/// Never the to-do mark: bridges set it to mean "open", and an open ticket is
/// not an ask (CLAUDE.md, prd §1025).
///
/// **It reads the folded room** (`ObjectFold`, §1079): a row is its object's
/// newest state, so an incident later resolved, a dispute later won or a
/// subscription later recovered has already left on its own.
///
/// **A week, then it goes.** Nothing tells the app a review was done or a
/// failed build was superseded by a green one, so an ask stands for seven days
/// from when it landed. Past that, a row still sitting in the list is history,
/// and calling it "now" would be the §83 fake status.
///
/// Foundation-only: `scripts/work-ask-selftest.sh` compiles this file and
/// `WorkStage.swift` whole.
enum WorkAsk {

    /// How long an ask stands.
    static let window: TimeInterval = 7 * 86_400

    /// GitHub's asks, as `GitHubFeeds.notificationAsk` tags them.
    static let githubAsks: Set<String> = ["Review", "Assigned", "Mentioned"]

    /// Whether a row is waiting on the person now.
    static func needsYou(_ row: WorkStage.Row, at: Date, now: Date = .now) -> Bool {
        guard at > now.addingTimeInterval(-window) else { return false }
        let tags = Set(row.tags)
        switch row.source {
        case "GitHub":
            if !tags.isDisjoint(with: githubAsks) { return true }
        case "AWS":
            // An alarm's state rides its ref (`aws:alarm:<name>:<STATE>:<t>`);
            // a pipeline run's status is its own unlocalized tag.
            if let ref = row.sourceRef, ref.hasPrefix("aws:alarm:") {
                let parts = ref.split(separator: ":")
                return parts.count >= 2 && parts[parts.count - 2] == "ALARM"
            }
            if row.sourceRef?.hasPrefix("aws:pipeline:") == true { return tags.contains("Failed") }
            return false
        case "Polar", "Dodo Payments":
            if tags.contains("Dispute") { return tags.contains("Opened") }
            if tags.contains("Subscription") {
                return !tags.isDisjoint(with: ["Failed", "PastDue", "Unpaid"])
            }
            return false
        default:
            break
        }
        // Everything `WorkStage` already calls broken: a failed build, a
        // regression, a triggered incident, a rejection, an open dispute, a
        // failed payout or payment.
        if let (_, tone) = WorkStage.outcome(row), tone == .failed { return true }
        return false
    }
}
