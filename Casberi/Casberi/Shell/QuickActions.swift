import UIKit

/// The Home Screen quick action (long-press the app icon on iOS/iPadOS; the
/// same list is the Dock menu under Catalyst) and the door UIKit actually
/// delivers it through.
///
/// **A scene-based app never receives a quick action on its APP delegate, and
/// every SwiftUI `App` is scene-based.** `UIApplicationDelegate`'s
/// `application(_:performActionFor:completionHandler:)` is the pre-scene door;
/// Apple's own documentation says that with scenes present UIKit calls
/// `windowScene(_:performActionFor:completionHandler:)` on the WINDOW SCENE
/// delegate instead, and that a COLD launch arrives as
/// `UIScene.ConnectionOptions.shortcutItem` rather than in `launchOptions`.
///
/// So from the day "Daily Brief" shipped (2026-08-03) to 2026-08-14 its handler
/// could not run at all: the flag was never written, the app opened normally,
/// and the person landed on the All feed — reported as exactly that. **It
/// looked completely healthy from outside**, and the reason is worth keeping:
/// REGISTERING a quick action is an app-delegate job
/// (`didFinishLaunchingWithOptions`, which does still fire), and only HANDLING
/// it is a scene-delegate job. The menu item appeared, wore its title and its
/// icon, and opened the app. Every visible half worked.
///
/// Nothing else could have caught it either: `xcodebuild` is happy, the static
/// audits are static, and no simulator gesture can long-press a Home Screen
/// icon — so the screen sweep never touched this path and never could. See
/// prd §377a.
enum QuickAction {
    /// The one action registered in `AppDelegate`. Spelled once, here, because
    /// a type string that disagrees between the registration and the handler is
    /// the same invisible failure this file exists to end.
    static let dailyBrief = "com.casberi.app.dailyBrief"

    /// Posted the instant an action is received, so a WARM delivery lands now
    /// rather than on the next foreground.
    ///
    /// **The flag and this notification are not redundant, they cover different
    /// launches.** The flag in the app group is the durable half: a COLD launch
    /// receives its action before `RootShell` exists to hear anything, so the
    /// request has to survive until the first activation drains it. The
    /// notification is the immediate half: on a warm delivery `handleActivation`
    /// may already have run (and is debounced to one pass per two seconds), so a
    /// flag with no nudge could sit unread until some later foreground — and a
    /// brief that opens itself minutes after you asked for it, on an activation
    /// you meant for something else, is worse than one that never opens.
    static let received = Notification.Name("casberi.quickAction.received")

    /// Record an action, whichever door it came through. Idempotent: the flag is
    /// a Bool and `RootShell` drains it under a guard, so the belt-and-braces
    /// double delivery on a cold launch (see `AppDelegate`) costs nothing.
    @MainActor
    static func receive(_ item: UIApplicationShortcutItem?) {
        guard let item else { return }
        NSLog("[Casberi] quickAction: %@", item.type)
        switch item.type {
        case dailyBrief:
            UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "brief.request")
            NotificationCenter.default.post(name: received, object: nil)
        default:
            break
        }
    }
}

/// The window-scene delegate, which exists for exactly one reason: to be the
/// object UIKit hands a quick action to.
///
/// It creates NO window, holds NO state, and implements exactly ONE method.
/// SwiftUI owns the window this scene shows — the delegate is installed by
/// returning it from `AppDelegate.application(_:configurationForConnecting:
/// options:)`, the documented door for a SwiftUI-lifecycle app that needs scene
/// callbacks, and SwiftUI still does its own scene setup around it.
///
/// **`scene(_:willConnectTo:options:)` is deliberately absent**, and that is the
/// design rather than an omission. It is the method that would carry a cold
/// launch's `connectionOptions.shortcutItem` — but it is also the method
/// SwiftUI's own scene setup lives in, and shadowing it to read one optional is
/// a way to end up with a working quick action on a blank window. The cold half
/// is read on the app delegate instead, from the same `ConnectionOptions` value,
/// where nothing is being taken over. What is left here is the warm delivery,
/// which has no other door and which SwiftUI has no reason to implement.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// WARM: the app was already running, backgrounded or foreground, and the
    /// person long-pressed the icon.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickAction.receive(shortcutItem)
        completionHandler(true)
    }
}
