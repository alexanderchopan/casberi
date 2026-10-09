import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ImageIO

/// The share extension — capture in one gesture (S3). Text, URLs, and images
/// land as things in the shared store, each where you would look for it
/// later (prd §1200, `ShareHome`): an article in Reading, a video or a show
/// in Media, your words and pictures in Notes. No question at share time; the
/// pill names the place, then dismisses itself.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        captureAndConfirm()
    }

    private func captureAndConfirm() {
        Task { @MainActor in
            let home = await save()
            #if DEBUG
            NSLog("shareSave| home %@", home?.rawValue ?? "none")
            #endif
            let pill = show(confirmation: home)
            try? await Task.sleep(for: .milliseconds(750))
            await fadeOut(pill)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Reads the first usable attachment, writes a Thing and says where it
    /// went. Nil when nothing was kept: a picture that would not decode is
    /// "Couldn't save", never an empty row (prd §83).
    private func save() async -> ShareHome? {
        guard
            let item = (extensionContext?.inputItems.first as? NSExtensionItem),
            let providers = item.attachments
        else { return nil }

        // Safari's JS preprocessing result (`SharePreprocessor.js`), when the
        // share came from a web page — a separate attachment alongside the
        // URL one, so it's read up front rather than inside the URL branch.
        let pageInfo = await loadPageInfo(from: providers)
        #if DEBUG
        NSLog("shareSave| types %@", providers.map { $0.registeredTypeIdentifiers.joined(separator: ",") }
            .joined(separator: " ; "))
        #endif

        for provider in providers {
            // URL first — the richer capture.
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let home = ShareHome.forLink(url)
                return insert(linkThing(for: url, home: home, item: item, pageInfo: pageInfo)) ? home : nil
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                // An address alone is a link; words are a note, even ones
                // holding an address (`ShareHome.link(inText:)`).
                if let url = ShareHome.link(inText: text) {
                    let home = ShareHome.forLink(url)
                    return insert(linkThing(for: url, home: home, item: item, pageInfo: pageInfo)) ? home : nil
                }
                guard let thing = Capture.thing(from: text) else { return nil }
                thing.kind = .note
                return insert(thing) ? .notes : nil
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // A picture is a note of yours holding it (prd §974's shape:
                // `previewImageData` at the app's one 480px size, "Photo").
                guard let bytes = await pictureBytes(from: provider) else { return nil }
                let thing = Thing(kind: .note, title: String(localized: "Photo"),
                                  source: ShareHome.notes.source)
                thing.previewImageData = bytes
                return insert(thing) ? .notes : nil
            }
        }
        // Safari sends ONLY the preprocessing result when the extension
        // declares `NSExtensionJavaScriptPreprocessingFile` — one
        // `com.apple.property-list` attachment, no URL (measured 2026-10-08,
        // prd §1200) — so a share from Safari reached here with nothing kept
        // and said "Couldn't save" every time. The page's address is in the
        // result (`SharePreprocessor.js`'s "url").
        if let raw = pageInfo?["url"] as? String, let url = ShareHome.link(inText: raw) {
            let home = ShareHome.forLink(url)
            return insert(linkThing(for: url, home: home, item: item, pageInfo: pageInfo)) ? home : nil
        }
        return nil
    }

    /// The shared picture at the app's one stored size (`ImportMedia.thumbnail`'s
    /// numbers: 480px on the long side, orientation applied, JPEG 0.7). A host
    /// hands an image as a file URL, as bytes or as a `UIImage`; each is read
    /// through ImageIO so a full-size photo is never decoded whole inside the
    /// extension's memory budget.
    private func pictureBytes(from provider: NSItemProvider) async -> Data? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        let source: CGImageSource?
        switch item {
        case let url as URL:     source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case let data as Data:   source = CGImageSourceCreateWithData(data as CFData, nil)
        case let image as UIImage:
            source = image.jpegData(compressionQuality: 0.9)
                .flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        default:                 source = nil
        }
        guard let source else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }

    /// The saved URL, named the way the original path always was
    /// (`attributedContentText` → the page's own title → the bare host), now
    /// also carrying the page's readable text when Safari ran our
    /// preprocessing script — nil `enrichedText` when it didn't (another
    /// app's share, or a non-web source), same as any other link.
    private func linkThing(for url: URL, home: ShareHome, item: NSExtensionItem, pageInfo: [String: Any]?) -> Thing {
        let selectedText = (item.attributedContentText?.string).flatMap { $0.isEmpty ? nil : $0 }
        let pageTitle = (pageInfo?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = selectedText
            ?? (pageTitle?.isEmpty == false ? pageTitle : nil)
            ?? url.host()?.replacingOccurrences(of: "www.", with: "")
            ?? url.absoluteString
        let thing = Thing(kind: .link, title: title, content: url.absoluteString, source: home.source)
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
        let container: ModelContainer
        do { container = try SharedStore.extensionContainer() } catch {
            #if DEBUG
            NSLog("shareSave| no store: %@", String(describing: error))
            #endif
            return false
        }
        let context = ModelContext(container)
        context.insert(thing)
        // `saveHonestly` is a Bool; the `!= nil` this replaced compared an
        // Optional-promoted Bool and passed every failed save as "Saved".
        guard context.saveHonestly() else { return false }
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
    @discardableResult
    private func show(confirmation home: ShareHome?) -> UIView {
        UINotificationFeedbackGenerator().notificationOccurred(home != nil ? .success : .error)
        let label = UILabel()
        label.text = home?.confirmation ?? String(localized: "Couldn't save")
        label.font = .systemFont(ofSize: 17)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0.17, alpha: 1)
        label.layer.cornerRadius = 22
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 44),
        ])
        guard !UIAccessibility.isReduceMotionEnabled else { return label }
        label.alpha = 0
        label.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            label.alpha = 1
            label.transform = .identity
        }
        return label
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
