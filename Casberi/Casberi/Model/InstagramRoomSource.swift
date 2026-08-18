import Foundation
import SwiftData

/// The Instagram room head's reading half (2026-08-18, prd §395) — landed rows
/// turned into the card's own value, with every judgement left to
/// `InstagramRoom`.
///
/// The split is `XRoomSource`'s and exists for its reason: this file touches
/// `Thing` and so can never be compiled by a harness, while `InstagramRoom` is
/// Foundation-only and is compiled WHOLE by `scripts/instagram-selftest.sh`.
/// Everything that could be wrong in a way that still renders perfectly — an
/// account ranked first because ties broke the other way, a span computed off
/// the wrong field, saves and likes quietly summed into one board — lives on
/// the other side of that line.
enum InstagramRoomSource {

    static let source = InstagramImport.source

    /// The head, or nil when this room has no library to show.
    ///
    /// `now` is taken for signature parity with every other `…RoomSource` in the
    /// `sourceHead` chain and is deliberately unused: this card is entirely
    /// historical, so nothing about it may change between two opens of the same
    /// corpus.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> InstagramRoom? {
        _ = now
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { $0.source == source && !Corpus.isImportReceipt($0) }
        guard !rows.isEmpty else { return nil }
        var saved: [InstagramRoom.Keep] = []
        var liked: [InstagramRoom.Keep] = []
        var made = 0
        for thing in rows {
            // What you MADE is every `.note` in this room — your captions
            // (Post/Reel/Story/Photo) and your comments. Counted, never ranked:
            // the export names no author for them beyond you, so there is
            // nothing to build a board out of, and §247 forbids folding them
            // into the one below.
            if thing.kind == .note { made += 1; continue }
            guard thing.kind == .link else { continue }
            if thing.tags.contains("Saved") {
                saved.append(keep(thing))
            } else if thing.tags.contains("Liked") {
                liked.append(keep(thing))
            }
        }
        return InstagramRoom.compose(saved: saved, liked: liked, made: made)
    }

    /// ONE calendar for every row, taken once (`XRoomSource`'s reason): asking
    /// `Calendar.current` per row is both slower and — across a run that spans a
    /// timezone change — capable of filing two saves from the same minute in
    /// different years.
    private static let calendar = Calendar.current

    /// One landed row, reduced to the four facts the head reads. The ONLY place
    /// a `Thing` is touched.
    @MainActor
    private static func keep(_ thing: Thing) -> InstagramRoom.Keep {
        InstagramRoom.Keep(ref: thing.sourceRef,
                           handle: thing.authorHandle,
                           year: calendar.component(.year, from: thing.capturedAt),
                           gone: thing.tags.contains("Gone"))
    }

    /// The probe's lines — driven by `-instagramRoomProbe`, and deliberately
    /// calling the REAL `compose` rather than reimplementing it: a probe whose
    /// job is explaining the card must not be able to disagree with the card
    /// (`PeerRoomSource.probeLines`' rule).
    ///
    /// It exists because an empty head has FIVE causes that render as one
    /// nothing, and only the last is a bug:
    ///
    ///   1. no export imported, so the room has no rows at all;
    ///   2. fewer than `InstagramRoom.minimumKept` saves AND likes, or fewer
    ///      than `minimumAccounts` accounts across them — the card declining on
    ///      purpose, with "Who you save most" leading exactly as before;
    ///   3. an export whose saves carry no `title`, so `authorHandle` is nil on
    ///      every row and there is nobody to rank (the rows still land, and the
    ///      `handles=` line below is what separates this from cause 1);
    ///   4. an import made by a build before `authorHandle` existed and never
    ///      re-imported, which is cause 3 wearing a different date;
    ///   5. `capturedAt` not resolving to plausible years, which draws a span of
    ///      centuries and is invisible in a feed sorted by the same field.
    ///
    /// It also reports the CAPTION AND COVER coverage, which is the one reading
    /// the card deliberately does not carry (see `InstagramRoom`'s type note):
    /// `enrichedText` is not a pre-fetched column, so asking it per row is fine
    /// once, in a probe, and wrong on every re-draw of a room holding thousands.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let all = things.live.filter { $0.source == source }
        let rows = all.filter { !Corpus.isImportReceipt($0) }
        let kept = rows.filter { $0.kind == .link }
        let savedRows = kept.filter { $0.tags.contains("Saved") }
        let likedRows = kept.filter { $0.tags.contains("Liked") }
        let mine = rows.filter { $0.kind == .note }
        var out: [String] = [
            "instagramRoom| source=\(source) handed=\(things.count) rows=\(rows.count)"
                + " saved=\(savedRows.count) liked=\(likedRows.count) made=\(mine.count)"
                + " minKept=\(InstagramRoom.minimumKept)"
                + " minAccounts=\(InstagramRoom.minimumAccounts)",
        ]
        let handles = kept.filter { !($0.authorHandle ?? "").isEmpty }.count
        let worded = kept.filter { $0.enrichedText != nil }.count
        let covers = kept.filter { $0.previewImageData != nil }.count
        let gone = kept.filter { $0.tags.contains("Gone") }.count
        let photos = mine.filter { $0.tags.contains("Photo") }.count
        out.append("instagramFields| handles=\(handles)/\(kept.count)"
                   + " words=\(worded)/\(kept.count) covers=\(covers)/\(kept.count)"
                   + " (cap \(InstagramCaptions.coverCap), ledger says \(InstagramCaptions.coversStored()))"
                   + " gone=\(gone) photoPosts=\(photos)/\(mine.count)")
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (nothing imported, or under the floors above)")
            return out
        }
        out.append("act=\(room.act.rawValue)")
        out.append("headline=\(InstagramRoom.headline(room))")
        out.append("note=\(InstagramRoom.note(room))")
        out.append("footnote=\(InstagramRoom.footnote(room) ?? "none")")
        out.append("totals| kept=\(room.kept) accounts=\(room.accountCount)"
                   + " made=\(room.made) gone=\(room.gone)"
                   + " span=\(room.span) (\(room.firstYear)–\(room.lastYear))")
        let top = InstagramRoom.top(room)
        // One line PER ACCOUNT (the `-todayProbe` truncation lesson).
        for account in room.accounts {
            out.append("instagramAccount| @\(account.handle)"
                       + " · \(InstagramRoom.accountLine(account, act: room.act))"
                       + " · share=\(String(format: "%.2f", InstagramRoom.share(kept: account.kept, of: top)))"
                       + " · newest=\(account.newestRef ?? "none")")
        }
        return out
    }
}
