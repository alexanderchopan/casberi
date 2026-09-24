import SwiftUI

/// The "act in this source" affordance — what a single-source feed offers
/// (user, 2026-07-12): COMPOSE, make a new item of the source's kind (a task,
/// an email) in the app that owns it. A source with none returns nil, so
/// nothing dead ever shows. The gate for a compose hand-off is the same as
/// the thing sheet's: it only appears when the target can actually receive it.
///
/// There was a second flavour, EXPAND ("Watch another wallet", "Follow
/// another feed", routing to the seat's setup screen). The source capsule
/// that drew it went in prd §359 (managing a source happens in the app
/// catalogue), and `FeedScreen` has drawn only `.openURL` since — so the
/// seven phrases sat here with no caller for six weeks. Deleted in prd §911
/// under §723: a feature deleted from the surface is deleted from the model.
struct SourceAction {
    let label: String
    let icon: String
    enum Run {
        case openURL(URL)                     // compose in another app
    }
    let run: Run
}

enum SourceActions {

    /// The action for a connected source, keyed by its bridge/catalog name —
    /// or nil when the source is read-only with nothing to add (Photos, a
    /// one-time import). The feed shows this only when filtered to that source.
    static func action(forSource name: String) -> SourceAction? {
        switch name.lowercased() {

        // Todoist rides its documented add URL, gated on the app
        // being installed (a connected token bridge doesn't imply the app).
        case "todoist":
            guard HandOffState.installedSchemes.contains("todoist"),
                  let url = URL(string: "todoist://addtask") else { return nil }
            return SourceAction(label: "New task", icon: "plus", run: .openURL(url))

        // Gmail composes IN the Gmail app when it's installed — matching today's
        // hand-off rule (Calendar/Reminders open their own apps, never a generic
        // proxy). Gated on the scheme resolving, like Todoist; falls back to the
        // universal mailto: only when Gmail isn't installed, so a Gmail source no
        // longer silently opens Apple Mail (user, 2026-07-12).
        case "gmail":
            let composeURL = HandOffState.installedSchemes.contains("googlegmail")
                ? URL(string: "googlegmail:///co")
                : URL(string: "mailto:")
            guard let url = composeURL else { return nil }
            return SourceAction(label: "New email", icon: "square.and.pencil", run: .openURL(url))

        // iCloud Mail rides the universal mailto: — Apple Mail is its native
        // client, so the default composer already lands in the right place.
        case "icloud mail":
            guard let url = URL(string: "mailto:") else { return nil }
            return SourceAction(label: "New email", icon: "square.and.pencil", run: .openURL(url))

        // Apple's own — no "new item" compose URL exists, so these OPEN THE APP
        // itself (calshow:// / x-apple-reminderkit://). A new event/reminder is
        // made there, never written inside Casberi (user, 2026-07-13).
        case "calendar":
            guard let url = URL(string: "calshow://") else { return nil }
            return SourceAction(label: "New event", icon: "calendar.badge.plus",
                                run: .openURL(url))
        case "reminders":
            guard let url = URL(string: "x-apple-reminderkit://") else { return nil }
            return SourceAction(label: "New reminder", icon: "plus",
                                run: .openURL(url))

        default:
            return nil
        }
    }
}
