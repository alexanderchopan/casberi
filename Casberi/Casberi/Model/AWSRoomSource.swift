import Foundation
import SwiftData

/// The AWS room head's reading half (2026-08-30) — the stored standing turned
/// into the card's value, with every judgement left to `AWSRoom`. The
/// `ASCRoomSource` split exactly: this file touches `UserDefaults` and so can
/// never be compiled by a harness, while `AWSRoom.swift` is Foundation-only
/// and is compiled WHOLE by `scripts/aws-selftest.sh`.
enum AWSRoomSource {

    /// The head, or nil when there is nothing to draw.
    ///
    /// Takes `things` for signature parity with every other `…RoomSource`
    /// (the `sourceHead` chain hands the room's rows to all of them) and
    /// reads none of them, deliberately — `ASCRoomSource.compose`'s exact
    /// reasoning: this card is about the account's PRESENT STANDING, and the
    /// resource counts have no row to replay at all (the module doctrine
    /// forbids landing them). One source of standing, read by both the room
    /// head and the connect screen.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> AWSStanding? {
        // `|| DemoMode.isActive` (2026-08-31) — the App Store Connect precedent
        // exactly (`ASCRoomSource`): this gate wants a real secret AND a real
        // access-key id in the Keychain, which a demo must never fake, so the
        // demo is admitted here and `DemoSeedAll` plants the standing below.
        guard AWSAuth.configured || DemoMode.isActive else { return nil }
        let standing = AWSState.standing
        guard standing.lastRead != nil else { return nil }
        return standing
    }

    /// The probe's lines, driven by `-awsRoomProbe` — calling the REAL
    /// `compose` rather than reimplementing it, so a probe explaining the
    /// card can never disagree with what the card actually draws.
    @MainActor
    static func probeLines(now: Date = .now) -> [String] {
        var out: [String] = [
            "configured=\(AWSAuth.configured) region=\(AWSAuth.region)",
        ]
        guard let standing = compose(now: now) else {
            out.append("compose=nil — no card (not connected, or no pass has run here)")
            return out
        }
        out.append("awsStanding| alarmsInAlarm=\(standing.alarmsInAlarm.count)"
                   + " lastFailedPipeline=\(standing.lastFailedPipeline ?? "—")"
                   + " costToday=\(standing.costToday.map(AWSCost.dollars) ?? "—")"
                   + " costBaseline=\(standing.costBaseline.map(AWSCost.dollars) ?? "—")"
                   + " costAnomalyDay=\(standing.costAnomalyDay ?? "—")")
        out.append("awsStanding| EC2=\(standing.ec2Count) S3=\(standing.s3Count)"
                   + " RDS=\(standing.rdsCount) Lambda=\(standing.lambdaCount)")
        out.append("rank=\(AWSRoom.rank(standing))")
        out.append("headline=\(AWSRoom.headline(standing))")
        out.append("resourceLine=\(AWSRoom.resourceLine(standing) ?? "none")")
        out.append("staleNote=\(AWSRoom.staleNote(asOf: standing.lastRead, now: now) ?? "current")")
        return out
    }
}
