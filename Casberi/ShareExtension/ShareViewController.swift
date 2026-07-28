import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The share extension — capture in one gesture (S3). Text, URLs, and images
/// land as things in the shared store; no destination decision, no title, no
/// folder. The sheet confirms and dismisses itself; the write happened.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        captureAndConfirm()
    }

    private func captureAndConfirm() {
        Task { @MainActor in
            let saved = await save()
            show(confirmation: saved)
            try? await Task.sleep(for: .milliseconds(900))
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
                return insert(linkThing(for: url, item: item, pageInfo: pageInfo))
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let thing = Capture.thing(from: text) {
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
        let body = [excerpt, article].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        if body.count >= 40 {
            thing.enrichedText = String(body.prefix(1200))
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
    private func show(confirmation saved: Bool) {
        let label = UILabel()
        label.text = saved ? String(localized: "Saved to Casberi") : String(localized: "Couldn't save")
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
    }
}
