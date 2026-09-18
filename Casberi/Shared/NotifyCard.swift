import Foundation

/// What a digest notification's long press draws (prd §809). The app writes
/// it into the notification's `userInfo` when it schedules the digest; the
/// NotificationContent extension reads it back and draws the rows. Nothing in
/// the extension reads the store or the network: every word, time and picture
/// is decided here, at scheduling, the same moment the banner's words are.
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
        /// Where a tap lands (`casberi://thing/<id>`), or nil for a row with no
        /// door of its own; the digest's own link stands in.
        var link: String?
        /// The lead's file name inside `facesDirectory`, written by the app at
        /// scheduling. Nil draws the app's initial instead.
        var face: String?
        /// A person's face is a circle, an app's mark a rounded square — the
        /// same split the feed row draws.
        var round: Bool
    }

    var title: String
    /// The head's picture, a file in `facesDirectory`: the same faces and app
    /// tiles the banner's thumbnail draws (§770), at card size.
    var head: String?
    var rows: [Row]
    /// The files under `facesDirectory` this card's rows name, so the app can
    /// clear them when the digest is replaced.
    var folder: String

    static let userInfoKey = "card"
    /// The category the extension answers to (`UNNotificationExtensionCategory`).
    static let category = "digest"
    /// A folder in the app group container, one subfolder per scheduled digest.
    static let facesDirectory = "NotifyFaces"
    /// The link a row tap leaves for the app, read before the notification's
    /// own link. The extension cannot open a URL; it can only open the app.
    static let rowLinkKey = "notify.rowLink"

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(from userInfo: [AnyHashable: Any]) -> NotifyCard? {
        guard let data = userInfo[userInfoKey] as? Data else { return nil }
        return try? JSONDecoder().decode(NotifyCard.self, from: data)
    }
}
