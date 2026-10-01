import SwiftUI
import UIKit

/// What KEEP does with a selected passage, when the page offers it (prd
/// §1020). nil — the default, and every note of yours — draws the prose as
/// SwiftUI `Text` exactly as before.
struct KeepPassageKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var keepPassage: ((String) -> Void)? {
        get { self[KeepPassageKey.self] }
        set { self[KeepPassageKey.self] = newValue }
    }
}

/// A paragraph you can keep a passage out of.
///
/// SwiftUI's own text selection offers no item of ours in its menu, so a
/// reading body that offers Keep is a `UITextView`: not editable, selectable,
/// sized to its words, set in the same rung (`DSTextStyle` → the shipped
/// Figtree face, Dynamic Type through `UIFontMetrics`, the rung's leading)
/// so the page reads as it did. The menu is the system's — Copy, Look Up,
/// Translate — with **Keep** after Copy; nothing else changes hands. A link
/// in the words stays a link, routed through SwiftUI's `openURL` so the
/// sheet's own handler keeps it.
struct KeepableText: UIViewRepresentable {
    let text: String
    let tier: DSTextStyle
    let ink: Color
    let onKeep: (String) -> Void

    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    func makeUIView(context: Context) -> KeepTextView {
        let view = KeepTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link]
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: KeepTextView, context: Context) {
        view.attributedText = attributed()
        view.linkTextAttributes = [.foregroundColor: UIColor(DS.tint)]
        view.onKeep = onKeep
        context.coordinator.openURL = openURL
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeepTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The rung, as UIKit draws it: `DSTextModifier`'s scale and weight, the
    /// rung's own line spacing.
    private func attributed() -> NSAttributedString {
        let scaled = UIFontMetrics(forTextStyle: tier.relative).scaledValue(for: tier.platformSize)
        let weight = legibilityWeight == .bold ? DSFont.bolder(tier.weight) : tier.weight
        let font = tier.monospaced
            ? UIFont.monospacedSystemFont(ofSize: scaled, weight: .regular)
            : (UIFont(name: DSFont.name(for: weight), size: scaled) ?? .systemFont(ofSize: scaled))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = tier.lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor(ink),
            .paragraphStyle: paragraph,
        ])
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction?
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }
    }
}

/// The text view, with Keep in its menu.
final class KeepTextView: UITextView {
    var onKeep: ((String) -> Void)?

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selected = text(in: textRange)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selected.isEmpty else { return UIMenu(children: suggestedActions) }
        let keep = UIAction(title: String(localized: "Keep"),
                            image: UIImage(systemName: "text.quote")) { [weak self] _ in
            self?.onKeep?(selected)
            self?.selectedTextRange = nil
        }
        var children = suggestedActions
        children.insert(keep, at: min(1, children.count))
        return UIMenu(children: children)
    }
}
