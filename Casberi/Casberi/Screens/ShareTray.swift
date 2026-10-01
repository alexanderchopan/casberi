import SwiftUI
import SwiftData

/// The share tray (docs/social-spec.md section 3) — what the dial's Share disc
/// raises: the card, drawn at width so the person sees exactly what goes
/// out, then the doors as rows (§746: a verb is a row). Messages and Mail
/// open the system composer with the card attached and the link in the
/// body; `Share…` is the system sheet with the card and the link as two
/// items (`ShareCardPart`), so a target keeps both.
///
/// Rows the device cannot honour are not drawn (§83): the simulator and a
/// Mac with no Messages account have no Messages row; there is always
/// `Share…`, even when the card cannot be drawn (then it carries the link).
///
/// The generic rows open with NO recipient: sending a thing on is usually to
/// someone other than the person it is from, and a prefilled wrong name is
/// worse than an empty field. The thing's own person, when the address book
/// holds one with a way to reach them (section 5), is a row of its own that
/// says who — `Send to Sam` — so the choice is visible, never hidden in a
/// composer's To line.
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
    @State private var composer: Composer?
    /// The room could not draw a card (nothing this week, nothing read) —
    /// said in the slot, never a spinner that spins for ever (§83).
    @State private var nothingToDraw = false
    /// The thing's own person, resolved on open through the address book.
    @State private var recipient: Recipient?
    /// A voice note's recording, written once for the system sheet (prd §1024).
    @State private var voiceFile: URL?
    @State private var activityUp = false
    @Environment(\.modelContext) private var context

    private enum Composer: String, Identifiable {
        case messages, mail, messagesTo, mailTo
        var id: String { rawValue }
    }

    /// Who the named row sends to, and the one channel it opens: a phone
    /// in Messages first, else an email in Mail.
    struct Recipient: Equatable {
        let name: String
        let phone: String?
        let email: String?
    }

    /// The named row's channel, or nil when this device cannot open it.
    private var recipientChannel: Composer? {
        guard let recipient else { return nil }
        if recipient.phone != nil, MessageCompose.canText { return .messagesTo }
        if recipient.email != nil, MessageCompose.canMail { return .mailTo }
        return nil
    }

    /// Pad, title, gap, the card at `previewHeight`, the rows, pad — the
    /// arithmetic every `DSTray` caller spells out, because the tray clips at
    /// its detent.
    private static let previewHeight: CGFloat = 420
    private var trayHeight: CGFloat {
        let rows = CGFloat(1 + (MessageCompose.canText ? 1 : 0) + (MessageCompose.canMail ? 1 : 0)
                           + (recipientChannel != nil ? 1 : 0))
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
                    if let recipient, let channel = recipientChannel {
                        DSDoorRow(icon: channel == .messagesTo ? "message" : "envelope",
                                  title: Text("Send to \(recipient.name)")) { composer = channel }
                    }
                    if MessageCompose.canText {
                        DSDoorRow(icon: "message", label: "Send in Messages") { composer = .messages }
                    }
                    if MessageCompose.canMail {
                        DSDoorRow(icon: "envelope", label: "Send in Mail") { composer = .mail }
                    }
                    if let image, let voiceFile {
                        // A voice note goes out as the card and the recording
                        // (prd §1024), two items on the system sheet.
                        DSDoorRow(icon: "square.and.arrow.up", label: "Share…") { activityUp = true }
                            .sheet(isPresented: $activityUp) {
                                ActivitySheet(items: [image, voiceFile])
                                    .ignoresSafeArea()
                            }
                    } else if let image {
                        ShareLink(items: ShareCardPart.items(image: image, link: model?.link, title: shareWords),
                                  subject: Text(shareTitle),
                                  preview: { _ in SharePreview(shareTitle, image: Image(uiImage: image)) }) {
                            DSDoorRowLabel(icon: "square.and.arrow.up", title: Text("Share…"))
                        }
                        .buttonStyle(RowPress())
                        .dsHover()
                    } else if nothingToDraw {
                        // No card to send, but the thing still goes out: its
                        // link, or its words (§83 — the door never vanishes).
                        fallbackShare
                    }
                }
            }
        }
        .task { await build() }
        .sheet(item: $composer) { which in
            switch which {
            case .messages, .messagesTo:
                TextComposer(body: composeBody, attachment: image?.pngData(), attachmentName: "casberi.png",
                             recipients: which == .messagesTo ? (recipient?.phone).map { [$0] } ?? [] : [])
                    .ignoresSafeArea()
            case .mail, .mailTo:
                MailComposer(subject: shareTitle, body: composeBody, attachment: image?.pngData(),
                             attachmentName: "casberi.png",
                             recipients: which == .mailTo ? (recipient?.email).map { [$0] } ?? [] : [])
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

    /// `Share…` with no card: the link when the thing has one, else the
    /// subject in words.
    @ViewBuilder private var fallbackShare: some View {
        let label = DSDoorRowLabel(icon: "square.and.arrow.up", title: Text("Share…"))
        if let link = model?.link {
            ShareLink(item: link) { label }
                .buttonStyle(RowPress())
                .dsHover()
        } else {
            ShareLink(item: shareTitle) { label }
                .buttonStyle(RowPress())
                .dsHover()
        }
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
            guard let base = ShareCard.model(for: thing) else { nothingToDraw = true; return }
            model = base
            recipient = Self.recipient(for: thing, context: context)
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

    /// The person the thing is from or about, when the address book holds
    /// one (section 5) and it is a person, not you, with a way to reach
    /// them: a phone or an email off their Contacts card, else a mail
    /// identity, else the thing's own detected `tel:` / `mailto:`. Read on
    /// open, never from a body (§628); one fetch, of one card.
    @MainActor
    static func recipient(for thing: Thing, context: ModelContext) -> Recipient? {
        guard thing.isLive, let contact = ContactIndexSources.contact(for: thing),
              contact.kind == .person, !contact.isUnnamed,
              !ContactIndexSources.isYours(contact) else { return nil }
        var phone: String?
        var email: String?
        if let key = contact.identities.first(where: { $0.kind == .contact })?.key,
           let ref = ContactIndexSources.cardRef(forKey: key) {
            var fetch = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
            fetch.fetchLimit = 4
            let card = (try? context.fetch(fetch))?.first { $0.isLive && $0.kind == .contact }
            let facts = card?.factList ?? []
            phone = facts.first { $0.action == .call }?.value
            email = facts.first { $0.action == .mail }?.value
        }
        if email == nil { email = contact.identities.first { $0.kind == .email }?.body }
        if phone == nil { phone = MessageCompose.phone(fromTel: thing.detectedTel) }
        if email == nil { email = MessageCompose.address(fromMailto: thing.detectedMailto) }
        guard phone != nil || email != nil else { return nil }
        return Recipient(name: contact.name, phone: phone, email: email)
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
