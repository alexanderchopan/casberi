import SwiftUI

/// **NO WORD ALONE ON A PARAGRAPH'S LAST LINE (user, 2026-09-24: "i don't
/// want to see orphan text on lines").**
///
/// SwiftUI exposes no line-break strategy (the iOS 27 SDK has no
/// `lineBreakStrategy` or `pushOut` on `Text`), so a wrapped sentence can end
/// on a single word — Apple Wallet's promise read "Nothing is / uploaded.".
/// The typesetter's own answer is a no-break space between the last two
/// words: they wrap together or not at all. It changes nothing on a line that
/// fits, and nothing in a language that doesn't separate words with spaces.
enum DSProse {
    /// The last two words of each paragraph are bound when they are short
    /// enough to wrap as a pair. A long pair (a URL, a German compound) is
    /// left alone, or binding would force it to break mid-word instead.
    static func unorphaned(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { bindLastPair(String($0)) }
            .joined(separator: "\n")
    }

    /// A literal drawn as prose. The parameter is a `LocalizedStringResource`
    /// so Xcode extracts it exactly as it extracts `Text("…")`.
    static func text(_ key: LocalizedStringResource) -> Text {
        markdown(unorphaned(String(localized: key)))
    }

    /// A runtime string drawn as prose: looked up first (a raw step string is
    /// its own catalog key; an already-localized one finds nothing and stays
    /// as it is), then bound, then read as inline Markdown so a `**word**` or
    /// a code span still draws as it did through `LocalizedStringKey`.
    static func text(resolving raw: String) -> Text {
        markdown(unorphaned(String(localized: String.LocalizationValue(raw))))
    }

    private static func markdown(_ bound: String) -> Text {
        if let styled = try? AttributedString(
            markdown: bound,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(styled)
        }
        return Text(verbatim: bound)
    }

    static let pairLimit = 24

    private static func bindLastPair(_ line: String) -> String {
        var words = line.split(separator: " ", omittingEmptySubsequences: false)
            .map(String.init)
        // Three words or fewer never wrap into an orphan worth binding.
        guard words.count >= 4 else { return line }
        let tail = words.removeLast()
        let before = words[words.count - 1]
        guard !tail.isEmpty, !before.isEmpty,
              before.count + 1 + tail.count <= pairLimit else { return line }
        words[words.count - 1] = before + "\u{00A0}" + tail
        return words.joined(separator: " ")
    }
}
