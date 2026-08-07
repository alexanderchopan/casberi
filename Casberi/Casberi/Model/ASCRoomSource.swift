import Foundation
import SwiftData

/// The App Store Connect room head's reading half (2026-08-06, prd §324) — the
/// stored standings turned into the card's own value, with every judgement left
/// to `ASCRoom`.
///
/// The split is `StripeRoomSource`'s and exists for its reason: this file
/// touches `UserDefaults` and `ModelContext` and so can never be compiled by a
/// harness, while `ASCRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/appstoreconnect-selftest.sh`. Everything that could be wrong in a
/// way that still renders — an app ranked below a rejected one, a duration
/// quoted from a first sight we never watched, a build's runway off by a day —
/// lives on the other side of that line.
enum ASCRoomSource {

    /// The card draws at most this many apps; the rest are counted in the note
    /// rather than silently dropped.
    static let rowCap = 3

    /// How close a build has to be to expiry before it can pull an otherwise
    /// quiet app up the card. Matches `ASCIngest.expiryWindow`, and the harness
    /// pins the two together — they are spelled separately because `ASCRoom` is
    /// Foundation-only and cannot read the ingest's constant.
    static let expirySoonDays = 14

    /// The head, or nil when there is nothing to draw.
    ///
    /// Takes `things` for signature parity with every other `…RoomSource` (the
    /// `sourceHead` chain hands the room's rows to all of them) and reads none
    /// of them — deliberately. This card is about STATE, and the rows are
    /// events; deriving "where does 1.4 stand" by replaying the feed would give
    /// a different answer from the connect screen for the same corpus. One
    /// source of standing, read by both.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> ASCRoom? {
        guard ASCAuth.configured else { return nil }
        let apps = ASCState.standing.values.map { standing -> ASCRoom.App in
            ASCRoom.App(
                id: standing.appID,
                name: standing.app.isEmpty ? standing.appID : standing.app,
                version: standing.version,
                state: ASCVersionState(rawValue: standing.state),
                // The honest-duration pair: a number only for a transition this
                // device actually watched. See `ASCStanding.observed`.
                days: standing.observed ? ASCRoom.days(from: standing.since, to: now) : nil,
                build: standing.build,
                expiresInDays: standing.expires.map { ASCRoom.days(from: now, to: $0) })
        }
        let room = ASCRoom(apps: ASCRoom.ordered(apps, expirySoonDays: expirySoonDays),
                           asOf: ASCState.lastRead)
        return room.isEmpty ? nil : room
    }

    /// The probe's lines — driven by `-ascRoomProbe`, and deliberately calling
    /// the REAL `compose` rather than reimplementing it: a probe whose job is
    /// explaining the card must not be able to disagree with the card
    /// (`StripeRoomSource.probeLines`' own rule).
    ///
    /// It exists because an empty head has FOUR causes that render as one
    /// nothing — the bridge isn't connected, no pass has run on this device (a
    /// fresh install syncs rows but not UserDefaults, so the standings are
    /// empty while the feed is full), the key sees no apps, or every standing
    /// decoded to nothing — and only the last is a bug.
    @MainActor
    static func probeLines(now: Date = .now) -> [String] {
        let standing = ASCState.standing
        var out: [String] = [
            "configured=\(ASCAuth.configured) apps=\(ASCState.apps.count)"
                + " standings=\(standing.count)"
                + " lastRead=\(ASCState.lastRead.map { ASCRoom.staleNote(asOf: $0, now: now) ?? "today" } ?? "NEVER")",
        ]
        // The raw standings BEFORE ranking, so a card that drew the wrong app
        // first can be told from one whose data was already wrong.
        for s in standing.values.sorted(by: { $0.app < $1.app }) {
            out.append("ascStanding| \(s.app) v\(s.version) state=\(s.state.isEmpty ? "—" : s.state)"
                       + " observed=\(s.observed) build=\(s.build.isEmpty ? "—" : s.build)"
                       + " processing=\(s.buildState.isEmpty ? "—" : s.buildState)"
                       + " expires=\(s.expires.map { String(ASCRoom.days(from: now, to: $0)) + "d" } ?? "none")")
        }
        guard let room = compose(now: now) else {
            out.append("compose=nil — no card (not connected, or no pass has run here)")
            return out
        }
        out.append("headline=\(ASCRoom.headline(room))")
        out.append("note=\(ASCRoom.note(room, drawn: min(rowCap, room.apps.count), now: now) ?? "none")")
        for app in room.apps.prefix(rowCap) {
            out.append("ascRoomApp| \(app.name) v\(app.version)"
                       + " · \(ASCRoom.stateLabel(app.state))"
                       + " · wait=\(ASCRoom.waitLabel(days: app.days) ?? "unobserved")"
                       + " · \(ASCRoom.buildLabel(app) ?? "no build")"
                       + " · rank=\(ASCRoom.rank(app, expirySoonDays: expirySoonDays))")
        }
        return out
    }
}
