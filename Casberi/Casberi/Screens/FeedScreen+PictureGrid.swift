import SwiftUI
import SwiftData

// The picture grid: which rows are tiles, their captions, and the tile rows, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// A Snapchat memory that has its picture back — the grid's own membership
    /// test, used to split that room (2026-07-31). Guarded internally because
    /// it is a shared helper taking a raw `Thing` and every caller hands it its
    /// own derived array (COROLLARY 4, see `ThingRowKeying`).
    /// The mixed rooms' grid split, in ONE pass (PERF 2026-09-01).
    ///
    /// All five wrote it as two `visible.live.filter` calls — once for the
    /// membership and once for its negation — which is two walks of the room,
    /// two `.live` copies, and, because the tests below read
    /// `previewImageData`, **two disk reads per picture row**, on every body
    /// pass. The predicate is pure, so asking it once per row and keeping both
    /// answers is the same result for half the work.
    ///
    /// Order is preserved in both halves, which is load-bearing rather than
    /// incidental: `rest` goes straight to `chronoGroups`, and the grid draws
    /// newest-first like every other tile shelf here.
    static func splitTiles(_ rows: [Thing],
                                   by isTile: (Thing) -> Bool) -> (tiles: [Thing], rest: [Thing]) {
        var tiles: [Thing] = []
        var rest: [Thing] = []
        for row in rows {
            if isTile(row) { tiles.append(row) } else { rest.append(row) }
        }
        return (tiles, rest)
    }

    /// **`previewImageData` IS TESTED LAST IN ALL FIVE OF THESE, AND THAT IS NOT
    /// COSMETIC (PERF 2026-09-01).** It is `@Attribute(.externalStorage)`, so
    /// `!= nil` is a read of the blob off disk rather than a field compare —
    /// and these run over `visible`, twice per mixed room (tiles, then the
    /// rest), on every body pass. Every other term is a string or enum compare,
    /// so ordering the cheap ones first is what lets them actually decide, and
    /// leaves the file read to the handful of rows that got past them. Same
    /// lesson `displayedMarketVenues` paid for on 2026-08-11: a short-circuit
    /// whose expensive half runs first is not a short-circuit.
    static func isMemoryTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Snapchat" && thing.kind == .file
            && thing.previewImageData != nil
    }

    /// A connected-folder file whose heal has landed pixels — the mixed
    /// Files room's grid membership (2026-08-02), `isMemoryTile`'s shape with
    /// one addition: the extension check makes the picture claim explicit
    /// rather than inferring it from `previewImageData`, which is the heal's
    /// implementation detail and not this test's contract. Guarded internally
    /// for the same corollary-4 reason as above.
    ///
    /// `drawsAsPicture`, not `isImageRef`, since 2026-08-17 — a VIDEO's poster
    /// frame is pixels and tiles here too. The comment above used to say only
    /// images ever carry `previewImageData` under Files; that stopped being
    /// true the day the poster heal landed, which is exactly why the claim was
    /// written as an explicit test instead of a `previewImageData != nil`.
    static func isFileImageTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Files" && thing.kind == .file
            // `drawsAsPicture` BEFORE the pixels (PERF 2026-09-01) — a
            // `sourceRef` extension test is a string compare; the term after it
            // is a file read. See `isMemoryTile` above.
            && FilesIngest.drawsAsPicture(thing.sourceRef)
            && thing.previewImageData != nil
    }

    /// A wordless picture in an Instagram export (2026-08-18, prd §389) — the
    /// mixed room's grid membership, `isXPhotoTile`'s shape one product over
    /// and for its exact reasons.
    ///
    /// Your own posts, reels and stories ONLY. A saved post's cover is a
    /// picture too, and it is deliberately not a tile: a save is somebody
    /// else's post that you kept for what it SAID as much as what it showed,
    /// and the caption `InstagramCaptions` fetches is the words the room exists
    /// to make searchable — extracting the picture into a grid would file the
    /// two halves of one thing in two places. It rides its own post card
    /// instead, cover and all.
    ///
    /// The test is the pixels plus the tag the importer stamps, never the
    /// title: that title is the localized word "Photo", and matching on it
    /// would empty this grid on every device that isn't in English. Guarded
    /// internally for the same corollary-4 reason as its three siblings.
    static func isInstagramPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == InstagramImport.source && thing.kind == .note
            && thing.tags.contains("Photo")
            && thing.previewImageData != nil
    }

    /// A wordless picture OR video post in an X archive (2026-08-13, prd §375;
    /// widened 2026-08-18, prd §396) — the mixed X room's grid membership,
    /// `isMemoryTile`'s shape one source over.
    ///
    /// THE TEST IS `postText == nil`, not the tag, and that changed with the
    /// videos. A wordless post is exactly one the importer gave no `postText`
    /// (`landTweets` writes it only from a non-empty body), which is a fact
    /// about the row rather than a word about the medium — so one test covers
    /// both tags and neither tag has to mean two things. It is never the
    /// title: that title is the localized word "Photo" or "Video", and
    /// matching on it would empty this grid on every device not in English.
    ///
    /// `Video` rides captioned posts too (see `landTweets`), which is exactly
    /// why the tag can no longer be the membership test: a video with a
    /// caption is a post card, and its caption is the post.
    ///
    /// Guarded internally for the same corollary-4 reason as its three
    /// siblings.
    static func isXPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == XArchiveImport.source && thing.kind == .note
            && thing.postText == nil
            && (thing.tags.contains("Photo") || thing.tags.contains("Video"))
            && thing.previewImageData != nil
    }

    /// A wordless picture from a followed CHANNEL (2026-08-23, prd §456).
    ///
    /// Live rows only: an imported conversation or a saved message never
    /// becomes a tile, whatever it carries. The same honesty rule the three
    /// mixed rooms before it settled — a tile promises a picture, so a post
    /// with a caption stays a post card, because the caption is the post.
    /// A Pinterest pin with a picture — every pin the feed gave an image. A
    /// pin is judged by looking, and its title is usually the first line of a
    /// description or the literal word "Pin" (prd §912), so the room is a
    /// wall of pins at 2:3 rather than a column of names.
    static func isPinTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Pinterest"
            && !(thing.previewImageURL ?? "").isEmpty
    }

    /// THE MEDIA ROOM'S GRID (prd §1049, built §1055): every row with a
    /// picture is a square tile — a photo, a screenshot, a pin, a video's or
    /// an album's art — and a row with none stays a row, because a tile
    /// promises a picture. The stored pixels are read last (the note above).
    static func isMediaTile(_ thing: Thing) -> Bool {
        guard thing.isLive else { return false }
        if !(thing.previewImageURL ?? "").isEmpty { return true }
        return thing.previewImageData != nil
    }

    static func isTelegramPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == TelegramChannel.source
            && Corpus.arrivedLive(thing)
            && (thing.postText ?? "").isEmpty
            && thing.previewImageData != nil
    }

    /// A tile whose picture is one FRAME of a video, so the grid can mark it.
    ///
    /// The mark is not decoration and its absence was a small lie: a poster
    /// frame is a still, and a still drawn with nothing to say otherwise reads
    /// as a photograph. `VideoMark`'s own doc settled the shape (cornered, no
    /// centred play button, no hits taken) — this is the test that decides
    /// which tiles wear it, in the two rooms that can hold one.
    private static func isVideoTile(_ thing: Thing) -> Bool {
        guard thing.isLive else { return false }
        if thing.source == XArchiveImport.source { return thing.tags.contains("Video") }
        return FilesIngest.isVideoRef(thing.sourceRef)
    }

    /// What a grid tile says across its foot. A screenshot's title is the text
    /// it shows, which is the tile's whole point; a Snapchat memory's title is
    /// its date, which the day pill already carries — so that room says the
    /// PLACE the export named, or nothing at all.
    private static func tileCaption(_ thing: Thing) -> String? {
        guard thing.isLive else { return nil }
        if thing.source == "Snapchat" {
            return SnapchatImport.place(inMemoryNote: thing.content)
        }
        // An X picture post has no caption BY DEFINITION — that is the whole
        // test that made it a tile — and its title is the placeholder word the
        // importer gave it. Printing that under every cell would be a grid of
        // identical labels saying nothing.
        if thing.source == XArchiveImport.source { return nil }
        // An Instagram picture post is a tile precisely BECAUSE it has no
        // caption; its title is the placeholder word the importer gave it, and
        // printing that under every cell is a grid of identical labels.
        if thing.source == InstagramImport.source { return nil }
        // An untitled pin's title is the placeholder word the ingest gave it.
        // A titled one says its name; the line after the seam (prd §915)
        // cannot fit a third of the screen.
        if thing.source == "Pinterest" {
            return thing.title == "Pin" ? nil : TitleSeam.split(thing.title).name
        }
        // A file the camera named says nothing a person wrote (prd §910):
        // IMG_4021 under a photograph is a label saying nothing, the X and
        // Instagram case one room over. A name a person gave keeps it, the
        // way the Files app draws it.
        if thing.source == "Files", Self.isCameraName(thing.title) { return nil }
        return thing.title
    }

    /// Whether a file's name is the one its camera or its screenshot key gave
    /// it — IMG_4021, DSC_0913, DSCF2210, PXL_2026…, PHOTO-2026-…, Screenshot
    /// 2026-… — rather than one a person typed (prd §910). The stem is tested
    /// so the extension never decides.
    static func isCameraName(_ name: String) -> Bool {
        let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
        let upper = stem.uppercased()
        let cameraPrefixes = ["IMG_", "IMG-", "IMG ", "DSC_", "DSC-", "DSCF", "DSCN", "PXL_",
                              "DCIM", "PHOTO-", "PHOTO_", "SCREENSHOT", "SCREEN SHOT"]
        return cameraPrefixes.contains { upper.hasPrefix($0) }
    }

    /// A day's pictures, three to a row, under the day's header (prd §910).
    ///
    /// EACH ROW OF THREE IS ITS OWN `List` ROW. The grid used to be one row —
    /// a `VStack` of every tile in the room — so a 300-screenshot room laid out
    /// 300 cells in one cell and recycled none of them. Hand-rolled rather
    /// than `LazyVGrid` for that reason now (the iOS 26 spacing bug the old
    /// grid worked around is beside the point: a `LazyVGrid` cannot be split
    /// across `List` rows at all). Three columns, FIXED: the grid used to be
    /// two-up under thirteen tiles and three-up above, so a room reflowed on
    /// the day it grew past twelve.
    ///
    /// The cell's shape is the room's (`PhotoCell.Shape`): a phone screen is
    /// tall and cropped from the top, a photograph is a square. The caption
    /// sits UNDER the tile, and a row in which any tile has one reserves the
    /// line on all three, so the three pictures keep one height.
    @ViewBuilder
    func tileRows(_ tiles: [Thing], shape: PhotoCell.Shape) -> some View {
        let items = tiles.live
        let perRow = 3
        let rows = stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0..<min($0 + perRow, items.count)])
        }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            // Captions computed HERE, while every model is still valid, so the
            // cell closure below reads plain strings (corollary 3, build 176 —
            // see `ThingRowKeying`).
            let captions = row.map { Self.tileCaption($0) }
            let reserves = captions.contains { !($0 ?? "").isEmpty }
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(Array(keyed(row).enumerated()), id: \.element.id) { col, item in
                    if let thing = item.live {
                        Button {
                            openThing(thing)
                        } label: {
                            PhotoCell(thing: thing, shape: shape, caption: captions[col],
                                      reservesCaption: reserves, video: Self.isVideoTile(thing))
                        }
                        // A photograph LIFTS under the finger (prd §384) where
                        // every control tile dips — a picture is picked up, not
                        // pushed. The cursor bloom is the cell's own.
                        .buttonStyle(PressLift())
                        .dsHover()
                    }
                }
                // An incomplete last row keeps its tiles at the same width as
                // full rows rather than stretching to fill.
                if row.count < perRow {
                    ForEach(0..<(perRow - row.count), id: \.self) { _ in
                        Color.clear
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The grid stands in the rows' column (prd §763), and its rows are
            // one gutter apart: this inset's bottom plus the next one's top.
            .listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.leadInset,
                                 bottom: DS.Space.s1, trailing: DSRoomChassis.leadInset))
        }
    }
}
