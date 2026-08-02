import UIKit
import UniformTypeIdentifiers

/// What Casberi puts on the clipboard, and for how long (prd §276, 2026-08-02).
///
/// A plain `UIPasteboard.general.string = …` writes an item with no expiry and
/// no device limit: it sits there until something else replaces it, and on a
/// device signed into iCloud it also travels to every other Apple device on
/// the account via Universal Clipboard. For an app whose clipboard traffic is
/// wallet addresses, device sign-in codes and the text of private notes, both
/// halves of that default are wrong.
///
/// Two verbs, and the split is deliberate:
///
/// * **`copy`** — ordinary content. It EXPIRES, because nothing this app
///   copies needs to still be in the clipboard tomorrow. It stays shareable
///   across devices, because copying a note on the phone and pasting it on
///   the Mac is a real thing people do, and this app runs on both. Taking
///   that away to look private would cost a feature and protect nobody: the
///   person chose to copy it.
/// * **`copySensitive`** — an address, a sign-in code, a calldata blob. Short
///   expiry AND `.localOnly`, so it never leaves for another device.
///
/// Deliberately NOT done: auto-upgrading `copy` to `copySensitive` when
/// `SecretScan` finds something. A false positive there would mean the Mac
/// silently refuses to paste with nothing on screen to explain why — the
/// "silently broken" failure this codebase keeps paying for. The call site
/// knows what it is copying; it says so.
enum DSPasteboard {

    /// Long enough to switch apps and paste, short enough that it isn't there
    /// after lunch.
    static let contentLifetime: TimeInterval = 10 * 60

    /// A code or an address is pasted within seconds or not at all.
    static let sensitiveLifetime: TimeInterval = 2 * 60

    static func copy(_ string: String) {
        write(string, localOnly: false, lifetime: contentLifetime)
    }

    static func copySensitive(_ string: String) {
        write(string, localOnly: true, lifetime: sensitiveLifetime)
    }

    private static func write(_ string: String, localOnly: Bool, lifetime: TimeInterval) {
        var options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(lifetime)
        ]
        if localOnly { options[.localOnly] = true }
        // `utf8PlainText` is the type `UIPasteboard.string`'s own setter
        // writes, so every paste target that accepted the old call accepts
        // this one.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: string]], options: options)
    }
}
