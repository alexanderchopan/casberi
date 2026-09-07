import SwiftUI

/// What a bridge says happened (prd §608).
///
/// **THE FILE IS THIS TYPE ALONE SINCE §639 (2026-09-06).** It was
/// `BridgeSetupPage.swift`, and it held the chassis of that name plus this
/// enum. Every screen is an `AccountPage` now, so the chassis is deleted
/// rather than left as a second way to build a page nobody builds — along with
/// `BridgeSetupHeader`, `BridgeConnectedState`, `BridgeConnectionSheet`,
/// `RoomDoor` and `RecentThingsSection`, whose jobs the chassis does. What
/// they were FOR is recorded in §608/§639 and guarded by
/// `setup-anatomy-audit.py`'s check A, which fails the build if any of those
/// names comes back onto a page.
///
/// The proof line outlives all of it, unchanged: it is what a bridge SAYS, not
/// where the page draws it.
///
/// `BridgeSyncStatusRows` took a free `String?` and a separate `Bool` saying
/// whether that string was a failure, and the two drifted apart in both
/// directions.
///
/// **The Bool was the dangerous half, and it had already shipped wrong.**
/// §252 found five screens passing a hardcoded `resultIsError: false` while
/// assigning real failures ("Couldn't reach the chain…") into the same
/// variable — so a network failure arrived in confirm green, wearing the
/// count-up animation, with no shake and no failure haptic. Each was fixed by
/// hand, and nothing stopped the sixth. **A failure that cannot be spelled
/// green is better than a failure somebody remembered to spell red**, so the
/// message and its tone are one value here and the pair is unrepresentable.
///
/// **The String was the drifting half.** Measured across the sixty-two setup
/// screens: fifteen distinct wordings for a successful outcome — "Up to date",
/// "\(n) new", "\(n) in", "\(n) landed…", "Connected", "Connected.",
/// "Connected — 1 app", "Connected to \(name)" — and thirty-six distinct lines
/// for "reading". The reading lines STAY free text and that is not an
/// oversight: "Reading the pool's doors…" is the one moment a bridge says what
/// it is actually doing, and it differs because the work differs. The
/// OUTCOMES are the same four events everywhere, so they are cases.
///
/// `landed`'s optional noun keeps the two shapes that were really carrying
/// meaning — "3 new" and "3 games in" — and collapses the other six spellings
/// of them.
enum BridgeProof: Equatable {
    /// Nothing arrived, and nothing was wrong. The commonest outcome.
    case upToDate
    /// Rows landed. `noun` nil reads "3 new"; a noun reads "3 games in".
    case landed(Int, noun: String? = nil)
    /// The handshake worked, before anything has synced. `detail` names what
    /// it connected TO when the bridge really holds that fact — never a guess
    /// (the identity rule `BridgeConnectedState` carried before §639: never
    /// a name we would guess).
    case connected(String? = nil)
    /// A line this bridge composes ITSELF, because the outcome really is
    /// several facts at once — an import receipt ("8,412 imported · 61 already
    /// here · 240 older not imported") is three numbers and cannot be one
    /// case without inventing a shape for every importer.
    ///
    /// **It is not an escape hatch for a count**, and the audit enforces that:
    /// a `says` whose text matches a canonical shape — a bare "N new", "Up to
    /// date", a lone "Connected" — fails the build, because `landed`,
    /// `upToDate` and `connected` exist precisely so those read the same on
    /// sixty-two screens. Reach for it when no other case is TRUE, never when
    /// another case is merely inconvenient.
    case says(String)
    /// It didn't work, in the bridge's own words. Free text on purpose: the
    /// whole value of this case is saying WHICH failure, and a closed set
    /// would collapse "check your connection" onto "that key was refused".
    case failed(String)

    var isFailure: Bool { if case .failed = self { return true }; return false }

    /// The line as drawn. `landed(0)` is `upToDate`, so a caller need not
    /// spell the ternary that forty-nine screens spelled by hand.
    var line: String {
        switch self {
        case .upToDate:
            return String(localized: "Up to date")
        case let .landed(count, noun):
            if count <= 0 { return String(localized: "Up to date") }
            guard let noun, !noun.isEmpty else {
                return String(localized: "\(count) new")
            }
            return String(localized: "\(count) \(noun) in")
        case let .connected(detail):
            guard let detail, !detail.isEmpty else {
                return String(localized: "Connected")
            }
            return String(localized: "Connected — \(detail)")
        case let .says(line):
            return line
        case let .failed(message):
            return message
        }
    }
}
