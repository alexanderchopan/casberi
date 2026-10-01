import Foundation

/// A FOLDER's card (prd §1021): the Notes room's folder, shared as one card
/// listing what is in it — the folder's name as the statement, the true
/// count and the day in the eyebrow, then up to five rows, each a thing's
/// mark and its one-line title (§902's row). A folder has no link, so the
/// share's second representation is the same list as words, which Notes,
/// Mail and a text field take.
enum FolderShareCard {
    static let rowCap = 5

    struct Input: Identifiable {
        let name: String
        let rows: [ShareCard.Row]
        let count: Int
        var id: String { name }

        /// Newest first, the room's own order; a sealed note is listed by
        /// the two words its record keeps (§982.6), never its words.
        @MainActor
        init(name: String, things: [Thing]) {
            self.name = name
            let live = things.filter(\.isLive).sorted { Pinboard.stamp($0) > Pinboard.stamp($1) }
            count = live.count
            rows = live.prefix(rowCap).map { thing in
                ShareCard.Row(source: thing.source,
                              symbol: BridgeIcon.noteSymbol(for: thing),
                              title: FolderShareCard.rowTitle(thing))
            }
        }
    }

    /// A voice note reads as the room reads it, "Voice note · 0:42"; every
    /// other row is its title's name.
    static func rowTitle(_ thing: Thing) -> String {
        if thing.kind == .voice, NoteSheetSource.isKeptNote(thing) {
            let length = VoiceLength.seconds(from: thing.capturedAt, to: thing.endAt)
                .map { VoiceLength.label($0) }
            return [String(localized: "Voice note"), length].compactMap { $0 }.joined(separator: " · ")
        }
        return TitleSeam.split(thing.title).name
    }

    static func model(_ input: Input, now: Date = .now) -> ShareCard.Model {
        let day = now.formatted(date: .abbreviated, time: .omitted)
        let count = String(localized: "\(input.count) things")
        return ShareCard.Model(source: NoteSheetSource.keptSource,
                               sourceName: input.name,
                               author: nil,
                               day: "\(count) · \(day)",
                               title: input.name,
                               words: "",
                               link: nil, artURL: nil, faceURL: nil,
                               rows: input.rows, symbol: ScopeTileGlyph.folders)
    }

    /// The card's words for a target that takes text: the name, then one
    /// line per thing listed.
    static func words(_ input: Input) -> String {
        ([input.name] + input.rows.map { "· " + $0.title }).joined(separator: "\n")
    }
}
