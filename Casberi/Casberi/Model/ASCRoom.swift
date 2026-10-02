import Foundation

/// How App Store Connect's setup screen words an app's STANDING (2026-08-06,
/// prd §324) — "In review · 2 days".
///
/// This was the room head's model until the head left the screen (§749) and
/// its ranking, headline and note were deleted with it (2026-10-01, the rule
/// that a feature deleted from the surface is deleted from the model). What
/// stays is what `AppStoreConnectScreen.stateLine` still draws.
///
/// ## The duration is the thing most easily faked
///
/// Apple publishes NO timestamp for when a version entered its current state,
/// so the only clock available is our own — and on first connect that clock
/// reads zero for a version that has been in review since Tuesday. So a
/// duration is shown ONLY for a transition this device actually watched
/// (`ASCStanding.observed`, gated by the screen), and `waitLabel` refuses day
/// zero. "0 days" would be a confident wrong answer (§83).
///
/// Foundation-only by design so `scripts/appstoreconnect-selftest.sh` can
/// compile it WHOLE and unmodified.
enum ASCRoom {

    // MARK: - Days

    /// Whole CALENDAR days, not `timeIntervalSince / 86400` — "expires Aug 20"
    /// means the day, so an 11pm read on the 19th is one day out, not 0.04.
    /// Negative is in the past.
    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    /// The state, in the words the screen shows. Distinct from
    /// `ASCVersionState.verdict`, which is written for a FEED ROW announcing a
    /// change ("Approved — yours to release") and reads wrong as a standing
    /// ("Casberi · Approved — yours to release · 2 days"). Present tense here,
    /// past tense there.
    static func stateLabel(_ state: ASCVersionState?) -> String {
        guard let state else { return String(localized: "Unknown") }
        switch state {
        case .prepareForSubmission:       return String(localized: "Not submitted")
        case .readyForReview:             return String(localized: "Ready to submit")
        case .waitingForReview:           return String(localized: "Waiting for review")
        case .inReview:                   return String(localized: "In review")
        case .pendingContract:            return String(localized: "Contract needed")
        case .waitingForExportCompliance: return String(localized: "Export compliance")
        case .pendingDeveloperRelease:    return String(localized: "Ready to release")
        case .pendingAppleRelease:        return String(localized: "Apple is releasing")
        case .processingForDistribution,
             .processingForAppStore:      return String(localized: "Processing")
        case .readyForDistribution,
             .readyForSale:               return String(localized: "Live")
        case .preorderReadyForSale:       return String(localized: "Pre-order")
        case .accepted:                   return String(localized: "Approved")
        case .rejected:                   return String(localized: "Rejected")
        case .metadataRejected:           return String(localized: "Metadata rejected")
        case .invalidBinary:              return String(localized: "Invalid binary")
        case .developerRejected:          return String(localized: "You withdrew it")
        case .developerRemovedFromSale:   return String(localized: "You removed it")
        case .removedFromSale:            return String(localized: "Removed from sale")
        case .replacedWithNewVersion:     return String(localized: "Superseded")
        case .notApplicable:              return String(localized: "Not applicable")
        }
    }

    /// "· 2 days" — nil when we never watched it arrive, and nil on day zero,
    /// where "0 days" reads as a measurement and "today" is the truth.
    static func waitLabel(days: Int?) -> String? {
        guard let days, days > 0 else { return nil }
        return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }
}
