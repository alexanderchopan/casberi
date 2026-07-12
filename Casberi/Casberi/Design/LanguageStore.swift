import SwiftUI
import Observation

/// App language — an in-app override for the shipped localizations, layered on
/// top of "follow the device". iOS normally binds an app's language to the
/// system; this lets someone read Casberi in Japanese while their phone stays
/// in English, and it switches LIVE (the root hands the whole tree this
/// `locale`, so every `Text` re-resolves from the chosen `.lproj` with no
/// relaunch). The choice also writes `AppleLanguages` so `String(localized:)`
/// and the next cold launch agree with what's already on screen.
@Observable
final class LanguageStore {
    static let shared = LanguageStore()

    /// One shipped language: the code iOS builds an `.lproj` for, the endonym
    /// (the language's own name for itself — never translated), and an English
    /// gloss so the picker reads for someone who can't yet read the endonym.
    struct Language: Identifiable, Equatable {
        let code: String
        let endonym: String
        let gloss: String
        var id: String { code }
    }

    /// The five shipped localizations. English first (the source), then the
    /// four added — each printed in its own script, so the list reads as a
    /// sample of itself.
    static let supported: [Language] = [
        Language(code: "en",      endonym: "English",  gloss: "English"),
        Language(code: "es",      endonym: "Español",  gloss: "Spanish"),
        Language(code: "zh-Hans", endonym: "简体中文",  gloss: "Chinese, Simplified"),
        Language(code: "ja",      endonym: "日本語",    gloss: "Japanese"),
        Language(code: "ko",      endonym: "한국어",     gloss: "Korean"),
    ]

    /// nil = follow the device. Otherwise one of `supported`'s codes.
    var code: String? {
        didSet { persist() }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "app.language")
        code = (raw?.isEmpty == false) ? raw : nil
    }

    /// What the root shell hands the whole view tree — this is what makes
    /// SwiftUI resolve `Text("…")` from the chosen `.lproj` live.
    var locale: Locale {
        if let code { return Locale(identifier: code) }
        return .autoupdatingCurrent
    }

    /// The active language record. When following the device, reflect what iOS
    /// actually resolved to, falling back to English (the source) when the
    /// device runs a language we don't ship.
    var active: Language {
        if let code, let match = Self.supported.first(where: { $0.code == code }) {
            return match
        }
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return Self.supported.first { preferred == $0.code || preferred.hasPrefix($0.code) }
            ?? Self.supported[0]
    }

    /// The Language tile's subline — states the setting in force.
    var summary: String {
        code == nil ? String(localized: "System") : active.endonym
    }

    /// A directive appended to the on-device model's instructions so a grounded
    /// answer comes back in the reader's language. Empty for English (the
    /// model's default) — English prompts stay byte-for-byte unchanged.
    var llmLanguageDirective: String {
        let names = ["zh-Hans": "Simplified Chinese", "ja": "Japanese",
                     "ko": "Korean", "es": "Spanish"]
        guard let name = names[active.code] else { return "" }
        return " Write your entire answer in \(name)."
    }

    private func persist() {
        let d = UserDefaults.standard
        if let code {
            d.set(code, forKey: "app.language")
            // Keep AppleLanguages in step so `String(localized:)` and the next
            // cold launch match the on-screen language.
            d.set([code], forKey: "AppleLanguages")
        } else {
            d.removeObject(forKey: "app.language")
            d.removeObject(forKey: "AppleLanguages")
        }
    }
}
