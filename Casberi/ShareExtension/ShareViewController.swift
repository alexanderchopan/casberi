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

        for provider in providers {
            // URL first — the richer capture.
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let title = (item.attributedContentText?.string).flatMap {
                    $0.isEmpty ? nil : $0
                } ?? url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
                return insert(Thing(kind: .link, title: title,
                                    content: url.absoluteString, source: "You"))
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

    private func insert(_ thing: Thing) -> Bool {
        guard let container = try? SharedStore.container() else { return false }
        let context = ModelContext(container)
        context.insert(thing)
        return (try? context.save()) != nil
    }

    /// A small confirmation pill — Bob's words, no "successfully".
    private func show(confirmation saved: Bool) {
        let label = UILabel()
        label.text = saved ? "Saved to Casberi" : "Couldn't save"
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
