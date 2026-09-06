import SwiftUI
import UniformTypeIdentifiers

/// What a feed row IS to another app (prd §631, 2026-09-06) — the one answer
/// three Mac verbs ask, in one place rather than three.
///
/// The Mac had a keyboard walk since §256 (↑/↓/Return/Escape) and nothing to
/// DO with the row it landed on. Every other list app on the platform answers
/// the same three keys at that point: ⌘C takes it, Space looks at it, and a
/// drag hands it to whatever is next to the window. This is those three.
///
/// **One resolver, deliberately.** Copy, drag and peek are three questions
/// with one answer — what this row is, as something another app can take —
/// and the recorded failure in this repo is a fix that lives twice and drifts
/// (`fix-recorded-once-lives-twice`). The URL comes from `ShareTargetMemo`,
/// which the row's Share entry already uses, so a row cannot copy one link
/// and share another; it is also the memo prd §628 introduced to stop the
/// All room faulting `content` per row, and reusing it means these verbs
/// inherit that fix rather than re-opening it.
///
/// **Reads only.** The row's context menu already rules itself reads-only —
/// writes confirm in the sheet, and a consent action fired from a right-click
/// is the one-slip yes S10 exists to prevent. Copying, previewing and dragging
/// are all reads of a thing the person already has, so the three sit inside
/// that rule rather than beside it.
@MainActor
enum MacRowHandoff {

    // MARK: - Copy (⌘C)

    /// The row's own words for the clipboard: its link when it has one, its
    /// text when it doesn't.
    ///
    /// A link first because that is what a person copying a saved article
    /// means, and because the text of a link row is frequently the URL again
    /// wrapped in a sentence. `DSPasteboard.copy` rather than the raw
    /// pasteboard, so this expires like everything else the app copies (§277)
    /// — and `copy` rather than `copySensitive`, because a corpus row is
    /// ordinary content and the phone→Mac paste is the whole point.
    static func copyText(for thing: Thing) -> String? {
        guard thing.isLive else { return nil }
        if let url = ShareTargetMemo.url(for: thing) { return url.absoluteString }
        let words = thing.content.isEmpty ? thing.title : thing.content
        return words.isEmpty ? nil : words
    }

    // MARK: - Drag out

    /// A row on its way out of the window.
    ///
    /// TWO representations, ordered: a receiver that wants a URL (a browser
    /// tab strip, a bookmark bar, a notes app making a link) negotiates the
    /// first; anything else takes the words. The URL representation THROWS
    /// when the row has none, which is the documented way to offer a
    /// representation conditionally — the receiver falls through to the text
    /// rather than getting an empty URL, which is the failure that reads as
    /// "the drag did nothing".
    ///
    /// **No image representation, and that is a decision.** Representation
    /// order is static, so preferring an image would mean preferring it on
    /// link rows too; and a picture already has a door that hands over the
    /// real photo — the row's Share entry, which loads the PHAsset rather
    /// than the stored thumbnail. Dragging a screenshot yields its title and
    /// link today. Adding pictures means a second `Transferable` chosen by
    /// kind at the call site, which is a real feature and not this one.
    struct Dragged: Transferable {
        let url: URL?
        let text: String

        enum Failure: Error { case noURL }

        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation { (item: Dragged) -> URL in
                guard let url = item.url else { throw Failure.noURL }
                return url
            }
            ProxyRepresentation { (item: Dragged) in item.text }
        }
    }

    /// Built at DRAG TIME, never per body build — `.draggable` takes an
    /// autoclosure, so nothing here runs while the feed is merely scrolling.
    static func dragged(_ thing: Thing) -> Dragged {
        guard thing.isLive else { return Dragged(url: nil, text: "") }
        return Dragged(url: ShareTargetMemo.url(for: thing),
                       text: thing.content.isEmpty ? thing.title : thing.content)
    }

    // MARK: - Quick Look (Space)

    /// Could this row have a document behind it?
    ///
    /// Read from `kind` and `sourceRef` ALONE, which are light columns — this
    /// answers on every arrow press, and faulting `previewImageData` or
    /// walking a folder per keypress would make the walk itself expensive to
    /// pay for a menu item's enabled state. So it is the honest question a
    /// cheap read can answer: is this the KIND of thing Quick Look is for.
    /// Whether the bytes are actually reachable is settled at press time, and
    /// reported (`peek`), because that answer costs a folder walk.
    ///
    /// Links, notes and posts are false on purpose. Quick Look previews
    /// documents; a link's preview is the page, which is what Open in app is
    /// for, and a note's is the thing sheet the walk's own Return already
    /// opens. A Space that opened a sheet would be a second Return.
    static func isPeekable(_ thing: Thing) -> Bool {
        guard thing.isLive else { return false }
        switch thing.kind {
        // A screenshot's pixels live in the store, so what makes it peekable
        // is having a ref at all.
        case .screenshot: return thing.sourceRef != nil
        // A file is peekable only when it is a CONNECTED FOLDER's file, which
        // is the `files:` ref. `.file` is not one source's kind — Dropbox,
        // the Snapchat import and the demo corpus all mint them — and for
        // those there is no document on this disk to open. Enabling Space
        // over them would trade the scroll key for a message.
        case .file: return thing.sourceRef?.hasPrefix("files:") == true
        default: return false
        }
    }

    /// What a peek found. Four outcomes rather than an optional, mirroring
    /// `FilesIngest.MediaResolution`, for its reason: three of these are not
    /// errors and each says something different. Collapsing them to nil draws
    /// one silence over a file still coming down from iCloud, a file that has
    /// moved, and a folder we can no longer reach.
    enum Peek {
        /// The row is the right KIND but has no pixels stored yet — a
        /// screenshot the photo heal has not reached. Distinct from
        /// `notDownloaded`, which is iCloud's answer about a real file: saying
        /// "still downloading" about a thing that is not downloading is the
        /// dishonest-message class this app's own rules forbid.
        case noPreview
        /// The URL to preview, and the scoped-access window it needs kept
        /// open. A connected folder's file is previewed WHERE IT LIVES —
        /// copying it into a temp directory first would mean reading a
        /// gigabyte of video into memory to look at its first frame — so the
        /// handle rides along and the caller holds it until the preview
        /// closes. A screenshot carries no handle: its pixels come out of the
        /// store into a temp file that depends on nothing.
        case ready(URL, FilesMediaHandle?)
        case notDownloaded
        case missing
        case unreachable
    }

    /// Resolve a row to a file URL Quick Look can open.
    ///
    /// Two doors, because the two peekable kinds live in different places. A
    /// connected folder's file resolves through `FilesIngest.media`, which
    /// walks the folder inside its own security-scoped window and is the ONLY
    /// supported way to reach one — a URL rebuilt from the ref's path string
    /// can standardize differently and silently point at the wrong file
    /// (`WalkedFile`'s own record). A screenshot has no file at all: its
    /// pixels live in the store, so they are written to a temp file and
    /// previewed from there.
    ///
    /// The temp directory is cleared before each write, so at most one peek
    /// file exists at a time and quitting leaves nothing behind that the
    /// system would not reap anyway.
    static func peek(_ thing: Thing) async -> Peek {
        guard thing.isLive else { return .missing }
        if thing.kind == .file, let ref = thing.sourceRef, ref.hasPrefix("files:") {
            switch await FilesIngest.media(for: ref) {
            case .ready(let handle):
                return .ready(handle.url, handle)
            case .notDownloaded: return .notDownloaded
            case .missing:       return .missing
            case .unreachable:   return .unreachable
            }
        }
        guard let image = StoredPixels.image(for: thing),
              let data = image.pngData() else { return .noPreview }
        let name = safeName(thing.title.isEmpty ? "Screenshot" : thing.title) + ".png"
        guard let url = stage(data: data, named: name) else { return .unreachable }
        return .ready(url, nil)
    }

    /// The one peek file. Named after the thing, because Quick Look puts the
    /// FILENAME in its own title bar — a preview headed `peek.png` says less
    /// than the row it came from already did.
    private static func stage(data: Data, named name: String) -> URL? {
        guard let dir = freshDirectory() else { return nil }
        let url = dir.appendingPathComponent(name)
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    private static func freshDirectory() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("casberi-peek", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return nil }
        return dir
    }

    /// A title becomes a filename: path separators and colons out, length
    /// bounded. Not security — the string is the person's own — just the
    /// difference between a file that writes and one that silently doesn't.
    private static func safeName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:\u{0}"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80))
    }
}

extension View {
    /// A feed row a person can drag out of the window (prd §631).
    ///
    /// **Mac only, and iPad is a deliberate omission rather than an oversight.**
    /// The feed pages horizontally between sources inside a `TabView(.page)`,
    /// and this repo's measured record there is unambiguous: that pager claims
    /// 100% of horizontal drags at every drag length, which is why the row's
    /// both-edge swipe was retired in 2026-07-16 and its verbs moved to a
    /// long-press. `.draggable` on a touch surface is that same long-press,
    /// now sharing it with the context menu that replaced the swipe. Under a
    /// POINTER none of that is true — a drag is press-and-move and the menu is
    /// a right-click, two gestures that cannot be confused — so the Mac gets
    /// it and the decision for touch is left where the measurement is, rather
    /// than guessed at from a build that compiles.
    ///
    /// Compiles to `self` off Catalyst: the phone pays nothing, not even the
    /// autoclosure.
    func macRowDrag(_ thing: Thing) -> some View {
        #if targetEnvironment(macCatalyst)
        return draggable(MacRowHandoff.dragged(thing))
        #else
        return self
        #endif
    }
}
