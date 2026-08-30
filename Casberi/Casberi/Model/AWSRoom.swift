import Foundation

/// The AWS room's judgement (2026-08-30) — Foundation-only by design, so
/// `scripts/aws-selftest.sh` compiles it WHOLE and unmodified. Everything
/// that touches `UserDefaults`/`ModelContext` lives in `AWSRoomSource.swift`
/// (the ASC/Stripe/PostHog split); everything here is a pure function of a
/// `AWSStanding` value.
///
/// One account, one region — unlike `ASCRoom`, which ranks several apps,
/// there is exactly one standing to draw, so there is no `ordered([...])`
/// here, only `rank` and `headline`.
enum AWSRoom {

    /// What the card LEADS with, ranked highest first. A failed deploy
    /// outranks a firing alarm because a pipeline failure blocks shipping
    /// entirely; an alarm outranks a cost anomaly because an alarm usually
    /// means something is actively broken right now, where a cost anomaly is
    /// a trend to notice rather than an incident. Resources-only (nothing
    /// wrong) ranks above an unreadable standing, so a healthy account never
    /// reads as worse than one nobody has synced yet.
    static func rank(_ standing: AWSStanding) -> Int {
        if !standing.alarmsInAlarm.isEmpty { return 4 }
        if pipelineFailedRecently(standing) { return 3 }
        if standing.costAnomalyDay != nil { return 2 }
        if standing.lastRead != nil { return 1 }
        return 0
    }

    /// A failed pipeline only leads the card while it's still the pipeline's
    /// CURRENT standing — `lastFailedPipeline` is written every pass a
    /// pipeline's newest execution is Failed, so once a later pass sees a
    /// Succeeded run for that pipeline the field is left stale here and this
    /// is what keeps a fixed deploy from leading the card forever. Nil
    /// `lastFailedPipelineWhen` (an unobserved first sight) still counts —
    /// the fact of a failure needs no duration to be true.
    private static func pipelineFailedRecently(_ standing: AWSStanding) -> Bool {
        standing.lastFailedPipeline != nil
    }

    /// The whole finding as one sentence.
    static func headline(_ standing: AWSStanding) -> String {
        if standing.alarmsInAlarm.count == 1 {
            return String(localized: "\(standing.alarmsInAlarm[0]) is in ALARM")
        }
        if standing.alarmsInAlarm.count > 1 {
            return String(localized: "\(standing.alarmsInAlarm.count) alarms are firing")
        }
        if let pipeline = standing.lastFailedPipeline {
            return String(localized: "\(pipeline) failed to deploy")
        }
        if standing.costAnomalyDay != nil, let today = standing.costToday {
            return String(localized: "Spend jumped to \(AWSCost.dollars(today))")
        }
        if standing.lastRead != nil {
            return String(localized: "Nothing needs attention")
        }
        return String(localized: "Not read yet")
    }

    /// The one-line resource count — "12 instances · 4 buckets · 2 databases
    /// · 30 functions" — with a ZERO count OMITTED rather than stated: a
    /// region with no RDS instances at all is not information worth a clause,
    /// and "0 databases" beside three real counts reads as a missing feature
    /// rather than an empty account.
    static func resourceLine(_ standing: AWSStanding) -> String? {
        var parts: [String] = []
        if standing.ec2Count > 0 {
            parts.append(standing.ec2Count == 1
                ? String(localized: "1 instance") : String(localized: "\(standing.ec2Count) instances"))
        }
        if standing.s3Count > 0 {
            parts.append(standing.s3Count == 1
                ? String(localized: "1 bucket") : String(localized: "\(standing.s3Count) buckets"))
        }
        if standing.rdsCount > 0 {
            parts.append(standing.rdsCount == 1
                ? String(localized: "1 database") : String(localized: "\(standing.rdsCount) databases"))
        }
        if standing.lambdaCount > 0 {
            parts.append(standing.lambdaCount == 1
                ? String(localized: "1 function") : String(localized: "\(standing.lambdaCount) functions"))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// A reading from last week is a broken key, `ASCRoom.staleNote`'s exact
    /// rule and the same three states: never read, read today (silent), read
    /// N days ago (said out loud).
    static func staleNote(asOf: Date?, now: Date, calendar: Calendar = Calendar(identifier: .gregorian))
        -> String? {
        guard let asOf else { return String(localized: "not read on this device yet") }
        let a = calendar.startOfDay(for: asOf)
        let b = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        if days <= 0 { return nil }
        if days == 1 { return String(localized: "read yesterday") }
        return String(localized: "read \(days) days ago")
    }
}
