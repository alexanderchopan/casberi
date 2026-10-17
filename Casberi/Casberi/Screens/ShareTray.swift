import SwiftUI

/// Share (docs/social-spec.md section 3, prd §1370) — what the dial's Share
/// disc raises: the system share sheet, with the card and the link as two
/// UIKit items (`ShareCardPart`, prd §1193), so a target keeps both. The
/// sheet's header draws the card (`LinkItem`'s metadata); Messages, Mail and
/// every other target are the sheet's own. A spinner holds the slot while
/// the card's pictures arrive.
///
/// When the card cannot be drawn the sheet still opens, with the link, or
/// the title in words (§83 — the door never vanishes); with neither, the
/// slot says so.
struct ShareTray: View {
    /// What the card is of: one thing, or a room's own figure (section 6,
    /// item 3 — `RoomShareCard`).
    enum Source {
        case thing(Thing)
        case room(RoomShareCard.Input)
        /// A Notes folder (prd §1021).
        case folder(FolderShareCard.Input)
    }
    let source: Source

    init(thing: Thing) { source = .thing(thing) }
    init(room: RoomShareCard.Input) { source = .room(room) }
    init(folder: FolderShareCard.Input) { source = .folder(folder) }

    /// The thing, when the card is of one — every read of it is guarded.
    private var thing: Thing? {
        if case .thing(let t) = source { return t }
        return nil
    }
    @State private var model: ShareCard.Model?
    @State private var image: UIImage?
    /// The card could not be drawn (nothing this week, nothing read).
    @State private var nothingToDraw = false
    /// A voice note's recording, written once for the system sheet (prd §1024).
    @State private var voiceFile: URL?

    var body: some View {
        if let thing, !thing.isLive { EmptyView() } else { liveBody }
    }

    private var liveBody: some View {
        Group {
            if let items {
                ActivitySheet(items: items)
                    .ignoresSafeArea()
            } else if nothingToDraw {
                Text("Nothing to draw yet.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
            } else {
                DSSpinner()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsReadSheet()
        .task { await build() }
    }

    /// What the system sheet carries: the card and the link, or a voice
    /// note's recording (prd §1024); with no card, the link or the words.
    /// nil while the card is drawn, and when there is nothing to send.
    private var items: [Any]? {
        if let image {
            return voiceFile.map { [image, $0] as [Any] }
                ?? ShareCardPart.items(image: image, link: model?.link, title: shareWords, subject: shareTitle)
        }
        guard nothingToDraw else { return nil }
        if let link = model?.link { return [link] }
        return shareTitle.isEmpty ? nil : [shareTitle]
    }

    /// The subject and the preview's name: the thing's title, or the room's
    /// figure said in words ("12 contributions this week").
    private var shareTitle: String {
        if let thing, thing.isLive { return thing.title }
        if case .folder(let input) = source { return input.name }
        if let model, let figure = model.figure {
            return [figure, model.caption].compactMap { $0 }.joined(separator: " ")
        }
        return model?.sourceName ?? ""
    }

    /// What a target that takes words gets beside the card: a folder's list
    /// (prd §1021), else the subject.
    private var shareWords: String {
        if case .folder(let input) = source { return FolderShareCard.words(input) }
        return shareTitle
    }

    /// Build the model on main, fetch the pictures off it, render on main.
    @MainActor private func build() async {
        switch source {
        case .thing(let thing):
            guard let base = ShareCard.model(for: thing) else { nothingToDraw = true; return }
            model = base
            let pixels = thing.isLive ? thing.previewImageData : nil
            var filled = await ShareCard.fetchingPictures(base, storedPixels: pixels)
            // A voice note's strip (prd §1024), read off the bytes once.
            if ShareCard.isVoice(thing), let audio = thing.audio {
                filled.wave = await ShareCard.wave(for: audio)
                voiceFile = ShareCard.audioFile(audio, name: TitleSeam.split(thing.title).name)
            }
            guard !Task.isCancelled else { return }
            model = filled
            image = ShareCard.render(filled)
            if image == nil { nothingToDraw = true }
        case .folder(let input):
            let built = FolderShareCard.model(input)
            model = built
            image = ShareCard.render(built)
            if image == nil { nothingToDraw = true }
        case .room(let input):
            let built = await RoomShareCard.model(input)
            guard !Task.isCancelled else { return }
            #if DEBUG
            NSLog("roomShare| source=%@ rows=%d model=%@", input.source, input.rows.count,
                  built == nil ? "nil" : "ok")
            #endif
            guard let built else { nothingToDraw = true; return }
            model = built
            image = ShareCard.render(built)
            if image == nil { nothingToDraw = true }
        }
    }
}

/// The system share sheet with items of more than one kind (prd §1024): a
/// `ShareLink` types every item of one `Transferable` alike, so a card and
/// a recording go through UIKit's own sheet as two items.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
