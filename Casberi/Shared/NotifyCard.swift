import Foundation

/// What a digest notification's long press draws (prd §809, §809a). The app
/// writes it into the notification's `userInfo` when it schedules the digest;
/// the NotificationContent extension reads it back and draws the rows. Every
/// picture rides the notification as an attachment named here, so the
/// extension reads no store, no shared folder and no network, and needs no
/// app group: every word, time and face is decided at scheduling.
///
/// Foundation-only, so `notify-selftest.sh` compiles it beside
/// `NotifyPlan.swift` and drives the pure half that fills it.
struct NotifyCard: Codable, Sendable, Equatable {

    /// One thing in the digest, in the feed row's anatomy: a lead, the app and
    /// the time, then the line.
    struct Row: Codable, Sendable, Equatable {
        var app: String
        /// Who acted, when the row names a person; the row leads with them
        /// and the app is not repeated down the card.
        var who: String? = nil
        var line: String
        var at: Date
        var link: String?
        /// The lead's attachment identifier (`faceAttachment`), filled by the
        /// scheduler. Nil draws the initial instead.
        var face: String?
        /// A person's face is a circle, an app's mark a rounded square — the
        /// same split the feed row draws.
        var round: Bool
    }

    var title: String
    /// The head's attachment identifier: the same faces and app tiles the
    /// banner's thumbnail draws (§770), at card size.
    var head: String?
    var rows: [Row]

    static let userInfoKey = "card"
    /// The category the extension answers to (`UNNotificationExtensionCategory`).
    static let category = "digest"
    /// The tile sheet's attachment. It is attached FIRST, because iOS draws
    /// the first attachment as the banner's thumbnail.
    static let headAttachment = "head"
    static func faceAttachment(_ index: Int) -> String { "face-\(index)" }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(from userInfo: [AnyHashable: Any]) -> NotifyCard? {
        guard let data = userInfo[userInfoKey] as? Data else { return nil }
        return try? JSONDecoder().decode(NotifyCard.self, from: data)
    }
}
