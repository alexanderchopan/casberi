import SwiftUI

/// The share tray (docs/social-spec.md section 3) — what the dial's Share disc
/// raises: the card, drawn at width so the person sees exactly what goes
/// out, then the doors as rows (§746: a verb is a row). Messages and Mail
/// open the system composer with the card attached and the link in the
/// body; `Share…` is the system sheet with the card first and the link
/// second.
///
/// Rows the device cannot honour are not drawn (§83): the simulator and a
/// Mac with no Messages account have no Messages row; there is always
/// `Share…`. Recipients come from the thing's own detector results until
/// `ContactIndex.contact(for:)` lands (section 5).
struct ShareTray: View {
    /// What the card is of: one thing, or a room's own figure (section 6,
    /// item 3 — `RoomShareCard`).
    enum Source {
        case thing(Thing)
        case room(RoomShareCard.Input)
    }
    let source: Source

    init(thing: Thing) { source = .thing(thing) }
    init(room: RoomShareCard.Input) { source = .room(room) }

    /// The thing, when the card is of one — every read of it is guarded.
    private var thing: Thing? {
        if case .thing(let t) = source { return t }
        return nil
    }
    @State private var model: ShareCard.Model?
    @State private var image: UIImage?
    @State private var composer: Composer?
    /// The room could not draw a card (nothing this week, nothing read) —
    /// said in the slot, never a spinner that spins for ever (§83).
    @State private var nothingToDraw = false

    private enum Composer: String, Identifiable {
        case messages, mail
        var id: String { rawValue }
    }

    /// Pad, title, gap, the card at `previewHeight`, the rows, pad — the
    /// arithmetic every `DSTray` caller spells out, because the tray clips at
    /// its detent.
    private static let previewHeight: CGFloat = 420
    private var trayHeight: CGFloat {
        let rows = CGFloat(1 + (MessageCompose.canText ? 1 : 0) + (MessageCompose.canMail ? 1 : 0))
        return DS.Space.s6 + 40 + DS.Space.s4 + Self.previewHeight + DS.Space.s3
             + rows * DS.Hit.min + DS.Space.s6
    }

    var body: some View {
        if let thing, !thing.isLive { EmptyView() } else { liveBody }
    }

    private var liveBody: some View {
        DSTray(title: "Share", height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.previewHeight)
                VStack(spacing: 0) {
                    if MessageCompose.canText {
                        DSDoorRow(icon: "message", label: "Send in Messages") { composer = .messages }
                    }
                    if MessageCompose.canMail {
                        DSDoorRow(icon: "envelope", label: "Send in Mail") { composer = .mail }
                    }
                    if let image {
                        ShareLink(item: ShareCardItem(image: image, link: model?.link, title: shareTitle),
                                  preview: SharePreview(shareTitle, image: Image(uiImage: image))) {
                            DSDoorRowLabel(icon: "square.and.arrow.up", title: Text("Share…"))
                        }
                        .buttonStyle(.plain)
                        .dsHover()
                    }
                }
            }
        }
        .task { await build() }
        .sheet(item: $composer) { which in
            switch which {
            case .messages:
                TextComposer(body: composeBody, attachment: image?.pngData(), attachmentName: "casberi.png",
                             recipients: MessageCompose.phone(fromTel: thing?.detectedTel).map { [$0] } ?? [])
                    .ignoresSafeArea()
            case .mail:
                MailComposer(subject: shareTitle, body: composeBody, attachment: image?.pngData(),
                             attachmentName: "casberi.png",
                             recipients: MessageCompose.address(fromMailto: thing?.detectedMailto).map { [$0] } ?? [])
                    .ignoresSafeArea()
            }
        }
    }

    /// The card as it will be sent — the rendered bitmap, never a live
    /// view, so what is previewed is what goes out. A spinner holds the
    /// slot while the pictures arrive.
    @ViewBuilder private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        } else if nothingToDraw {
            Text("Nothing to draw yet.")
                .dsText(.body17)
                .foregroundStyle(DS.textTertiary)
        } else {
            DSSpinner()
        }
    }

    /// The subject and the preview's name: the thing's title, or the room's
    /// figure said in words ("12 contributions this week").
    private var shareTitle: String {
        if let thing, thing.isLive { return thing.title }
        if let model, let figure = model.figure {
            return [figure, model.caption].compactMap { $0 }.joined(separator: " ")
        }
        return model?.sourceName ?? ""
    }

    /// The composer's body: the thing's link when it has one, else the
    /// subject.
    private var composeBody: String {
        if let link = model?.link { return link.absoluteString }
        return shareTitle
    }

    /// Build the model on main, fetch the pictures off it, render on main.
    @MainActor private func build() async {
        switch source {
        case .thing(let thing):
            guard let base = ShareCard.model(for: thing) else { return }
            model = base
            let pixels = thing.isLive ? thing.previewImageData : nil
            let filled = await ShareCard.fetchingPictures(base, storedPixels: pixels)
            guard !Task.isCancelled else { return }
            model = filled
            image = ShareCard.render(filled)
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
