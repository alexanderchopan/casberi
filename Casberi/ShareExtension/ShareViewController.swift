import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit

/// The share extension — capture in one gesture (S3). Text, URLs, and images
/// land as things in the shared store; no destination decision, no title, no
/// folder. The sheet confirms and dismisses itself; the write happened.
///
/// **Add to note, AFTER the save (the add-to-note ruling, 2026-09-29).** The
/// capture stays one gesture: the thing lands before anything is asked. When
/// you have a note to add to and the share was words or a link, the pill
/// carries one more verb, "Add to note", and stays long enough to reach it.
/// Tapped, the notes list rises; a pick writes the words into the note (and
/// the separate note the words made goes, so nothing lands twice), or a
/// link's `[[title]]` (the note's own link syntax, §982, so the note points
/// at the thing you just kept). Not tapped, the sheet leaves as it always has.
final class ShareViewController: UIViewController {

    /// What landed, as far as a note can take it.
    private enum Landed {
        /// A link, by the title a note's `[[…]]` can name.
        case link(id: UUID, title: String, url: String)
        /// Words, which became a note of their own (`Capture.thing`).
        case words(id: UUID, text: String)
        /// Anything a note cannot name (an image).
        case other
    }

    /// The pill's wait, cancelled when "Add to note" is tapped.
    private var dismissal: Task<Void, Never>?
    /// The pill standing now — it leaves when the notes rise, so the answer
    /// pill never lands on top of it.
    private weak var pillView: UIView?
    /// What landed, for the note the person picks.
    private var landed: Landed = .other

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        captureAndConfirm()
    }

    private func captureAndConfirm() {
        Task { @MainActor in
            let saved = await save()
            // The note verb only where a note can take what landed and there
            // is a note to take it: a door onto an empty list is §83's dead
            // control.
            let offersNote: Bool = {
                guard saved else { return false }
                if case .other = landed { return false }
                guard let container = try? SharedStore.extensionContainer() else { return false }
                return !NoteAppend.notes(in: ModelContext(container), limit: 1).isEmpty
            }()
            let pill = show(confirmation: saved, offersNote: offersNote)
            pillView = pill
            // Long enough to reach the verb when there is one; the old beat
            // when there is not.
            dismissal = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(offersNote ? 2400 : 750))
                guard !Task.isCancelled else { return }
                await fadeOut(pill)
                extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    /// "Add to note", tapped: the wait stops and the notes rise.
    @objc private func addToNoteTapped() {
        dismissal?.cancel()
        pillView?.removeFromSuperview()
        UISelectionFeedbackGenerator().selectionChanged()
        guard let container = try? SharedStore.extensionContainer() else { finish(); return }
        let choices = NoteAppend.notes(in: ModelContext(container))
        let picker = UIHostingController(rootView: ShareNotePicker(
            notes: choices,
            onPick: { [weak self] id in self?.add(to: id) }))
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        // Pulled down is "not now": the thing is already kept, so the sheet
        // simply goes (no Cancel at the top edge, §752).
        picker.presentationController?.delegate = self
        present(picker, animated: true)
    }

    /// Write what landed into the picked note, say so, and go.
    private func add(to id: UUID) {
        guard let container = try? SharedStore.extensionContainer() else { finish(); return }
        let context = ModelContext(container)
        var written: Thing?
        switch landed {
        case .link(_, let title, let url):
            // The note's own link to the thing, by title; a title a link
            // cannot hold (brackets) goes in as the address.
            let named = title.contains("[") || title.contains("]") ? url : "[[\(title)]]"
            written = try? NoteAppend.append(named, to: id, in: context)
        case .words(let made, let text):
            written = try? NoteAppend.append(text, to: id, in: context)
            // The words are in the note now; the note they made alone goes,
            // so the share lands once.
            if written != nil {
                var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.id == made })
                d.fetchLimit = 1
                if let alone = (try? context.fetch(d))?.first {
                    context.delete(alone)
                    try? context.save()
                }
            }
        case .other:
            break
        }
        if written != nil {
            UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "capture.landed")
            WidgetCenter.shared.reloadTimelines(ofKind: NoteAppend.widgetKind)
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let title = written?.title
                let pill = self.show(confirmation: written != nil,
                                     saying: title.map { String(localized: "Added to \($0)") }
                                        ?? String(localized: "Couldn't add it"))
                try? await Task.sleep(for: .milliseconds(900))
                await self.fadeOut(pill)
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func finish() {
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Reads the first usable attachment and writes a Thing. Source is the
    /// place words say: shared into Casberi by the person.
    private func save() async -> Bool {
        guard
            let item = (extensionContext?.inputItems.first as? NSExtensionItem),
            let providers = item.attachments
        else { return false }

        // Safari's JS preprocessing result (`SharePreprocessor.js`), when the
        // share came from a web page — a separate attachment alongside the
        // URL one, so it's read up front rather than inside the URL branch.
        let pageInfo = await loadPageInfo(from: providers)

        for provider in providers {
            // URL first — the richer capture.
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let thing = linkThing(for: url, item: item, pageInfo: pageInfo)
                landed = .link(id: thing.id, title: thing.title, url: url.absoluteString)
                return insert(thing)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let thing = Capture.thing(from: text) {
                // A URL typed as text lands as a link (`Capture.thing`), and
                // a note takes it as one.
                landed = thing.kind == .link
                    ? .link(id: thing.id, title: thing.title, url: thing.content)
                    : .words(id: thing.id, text: text)
                return insert(thing)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                return insert(Thing(kind: .screenshot, title: "Shared image",
                                    source: "You"))
            }
        }
        return false
    }

    /// The saved URL, named the way the original path always was
    /// (`attributedContentText` → the page's own title → the bare host), now
    /// also carrying the page's readable text when Safari ran our
    /// preprocessing script — nil `enrichedText` when it didn't (another
    /// app's share, or a non-web source), same as any other link.
    private func linkThing(for url: URL, item: NSExtensionItem, pageInfo: [String: Any]?) -> Thing {
        let selectedText = (item.attributedContentText?.string).flatMap { $0.isEmpty ? nil : $0 }
        let pageTitle = (pageInfo?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = selectedText
            ?? (pageTitle?.isEmpty == false ? pageTitle : nil)
            ?? url.host()?.replacingOccurrences(of: "www.", with: "")
            ?? url.absoluteString
        let thing = Thing(kind: .link, title: title, content: url.absoluteString, source: "You")
        let article = (pageInfo?["articleText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = (pageInfo?["excerpt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Description THEN article, not description OR article (prd §645
        // amendment 4): both are drawn now, and the script hands over the
        // page's paragraphs with their breaks.
        let body = ReadableBody.compose(description: excerpt, article: article)
        if body.count >= 40 {
            // `ReadableBody.limit`, not a literal: the app clamps the same
            // column in another process, both are DRAWN since prd §645 pass 1,
            // and `LinkTitle.enrich` will not re-fetch this row — it bails on
            // anything already wearing a real title, which is what a Safari
            // share arrives with. So this clamp is final for a shared link.
            thing.enrichedText = String(body.prefix(ReadableBody.limit))
        }
        return thing
    }

    /// Reads `SharePreprocessor.js`'s completion payload — a `public
    /// property list` attachment Safari adds alongside the URL/text one when
    /// the share came from a web page. nil when it didn't run (a share from
    /// another app, or from a source with no page context).
    private func loadPageInfo(from providers: [NSItemProvider]) async -> [String: Any]? {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                  let wrapper = try? await provider.loadItem(
                      forTypeIdentifier: UTType.propertyList.identifier) as? NSDictionary,
                  // Hardcoded rather than the SDK constant: it lives in a
                  // framework this target doesn't otherwise need to import,
                  // and the string is stable, documented Apple API.
                  let results = wrapper["NSExtensionJavaScriptPreprocessingResultsKey"] as? [String: Any]
            else { continue }
            return results
        }
        return nil
    }

    private func insert(_ thing: Thing) -> Bool {
        guard let container = try? SharedStore.extensionContainer() else { return false }
        let context = ModelContext(container)
        context.insert(thing)
        guard (context.saveHonestly()) != nil else { return false }
        // Leave the app a note: its @Query views never hear another
        // process's save (SwiftData; Apple forums thread 764290), so a
        // capture landed here stayed invisible until relaunch. The shell
        // reconciles on its next foreground when this flag is up.
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "capture.landed")
        return true
    }

    /// A small confirmation pill — Bob's words, no "successfully".
    ///
    /// The pill ARRIVES (2026-09-05): a success/failure haptic and the app's
    /// own settle-in (0.92 → 1 with a fade, `SettleIn`'s numbers) — this is
    /// the capture loop's front door, and until now it was the one surface in
    /// the product with no feedback at all: a flat label that appeared, sat,
    /// and was gone. UIKit here because the extension has no DS; the spring
    /// is tuned to read the same as `DS.Motion.standard` at rest. Reduce
    /// Motion skips the move and keeps the haptic, which is the rule
    /// everywhere else.
    ///
    /// With `offersNote`, the pill carries "Add to note" after its words — a
    /// second verb in the same capsule, the slab's grammar (one control, two
    /// acts), never a second pill.
    @discardableResult
    private func show(confirmation saved: Bool, offersNote: Bool = false,
                      saying: String? = nil) -> UIView {
        UINotificationFeedbackGenerator().notificationOccurred(saved ? .success : .error)
        let label = UILabel()
        label.text = saying ?? (saved ? String(localized: "Saved to Casberi") : String(localized: "Couldn't save"))
        label.font = .systemFont(ofSize: 17)
        label.textColor = .white
        label.textAlignment = .center
        let pill = UIStackView(arrangedSubviews: [label])
        pill.axis = .horizontal
        pill.spacing = 14
        pill.alignment = .center
        pill.isLayoutMarginsRelativeArrangement = true
        pill.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        pill.backgroundColor = UIColor(white: 0.17, alpha: 1)
        pill.layer.cornerRadius = 22
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        if offersNote {
            let add = UIButton(type: .system)
            add.setTitle(String(localized: "Add to note"), for: .normal)
            add.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            add.tintColor = UIColor(white: 1, alpha: 0.9)
            add.addTarget(self, action: #selector(addToNoteTapped), for: .touchUpInside)
            add.accessibilityHint = String(localized: "Adds this to one of your notes")
            pill.addArrangedSubview(add)
        }
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            pill.heightAnchor.constraint(equalToConstant: 44),
        ])
        guard !UIAccessibility.isReduceMotionEnabled else { return pill }
        pill.alpha = 0
        pill.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            pill.alpha = 1
            pill.transform = .identity
        }
        return pill
    }

    /// The pill leaves the way it came, a beat before the sheet is torn down —
    /// so the dismissal reads as the confirmation finishing rather than the
    /// host app snatching it back mid-word.
    private func fadeOut(_ pill: UIView) async {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
                pill.alpha = 0
                pill.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            } completion: { _ in done.resume() }
        }
    }
}

/// The notes a share can go into (the add-to-note ruling): newest first, a
/// title a row, one tap to pick; pulled down, nothing more happens. The
/// extension has no design system, so this is the system's own list — the
/// same one the share sheet itself is — named in its first line.
private struct ShareNotePicker: View {
    let notes: [NoteAppend.Choice]
    let onPick: (UUID) -> Void

    var body: some View {
        List {
            Section {
                ForEach(notes) { note in
                    Button {
                        onPick(note.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(note.capturedAt, format: .dateTime.day().month(.abbreviated).year())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                // Sentence case, never the list's default capitals (§8).
                Text("Add to note")
                    .textCase(nil)
            }
        }
    }
}

extension ShareViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
