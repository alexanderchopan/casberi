import SwiftUI
import Observation

/// Everything a WINDOW owns, as against everything the APP owns
/// (multi-window, 2026-08-02).
///
/// The app declared `UIApplicationSupportsMultipleScenes` from the day
/// `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` was switched on, and
/// could not honour it: navigation (`HomeRoute`), the source filter
/// (`FeedFilter`) and the detail pane's selection (`PadDetailSelection`) were
/// all process singletons. Two windows would have shared one pushed stack, one
/// selected source and one open record — clicking a chip in the second window
/// would have re-routed the first. It was unreachable rather than broken
/// (File's New Window is replaced by "New Thing…"), which is the worst state
/// for a thing to be in: shipped, declared, and wrong the moment anyone finds
/// the door.
///
/// So the three moved in here and their `.shared` statics were DELETED. That
/// deletion is the enforcement: a call site that still wants a global stops
/// compiling, and there is no accessor that silently returns "whichever window
/// is frontmost" — which reads fine from a menu command and is a bug from a
/// view, since a body evaluating in the background window would resolve to the
/// foreground one's state.
///
/// `ShellChrome` is NOT in here. It has been per-window since it was written
/// (a plain `@State` on `RootShell`) and already reaches the menu bar through
/// its own `FocusedValues` entry; this type follows the pattern it set rather
/// than absorbing it.
///
/// **Reaching it.** Views take the three out of the environment individually
/// (`@Environment(HomeRoute.self)`, …), so no screen has to know this
/// container exists. The menu bar takes the WHOLE container out of
/// `FocusedValues`, because a command fires from outside every window's view
/// hierarchy and has to be told which window it meant — that is what
/// `focusedSceneValue` answers.
@MainActor @Observable
final class SceneState {
    let route = HomeRoute()
    let filter = FeedFilter()
    let detail = PadDetailSelection()

    init() {}
}

/// The menu bar's route back down into the frontmost window's state. See
/// `ShellChromeFocusedKey` for the same argument made once already.
private struct SceneStateFocusedKey: FocusedValueKey {
    typealias Value = SceneState
}
extension FocusedValues {
    var sceneState: SceneState? {
        get { self[SceneStateFocusedKey.self] }
        set { self[SceneStateFocusedKey.self] = newValue }
    }
}

/// Reads the `UIWindowScene` a view is ACTUALLY in (multi-window, 2026-08-02).
///
/// The app used to ask `UIApplication.shared.connectedScenes` for "the first
/// foreground-active scene" whenever it needed a window — to set the size
/// floor and to retitle the title bar. With one window that is a correct if
/// roundabout way to say "mine". With two it answers "whichever is frontmost",
/// so a background window changing source would retitle the front one, and the
/// size floor could be applied to the same window twice and to the other never.
///
/// A view's own `window?.windowScene` cannot be wrong, which is the whole
/// point. `didMoveToWindow` is the hook because a SwiftUI view has no window
/// at `onAppear` time on every path — the old code's single unretried attempt
/// is exactly that bug — and it fires again if the view is ever re-hosted.
struct WindowSceneReader: UIViewRepresentable {
    let onResolve: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> UIView { ProbeView(onResolve: onResolve) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class ProbeView: UIView {
        private let onResolve: (UIWindowScene) -> Void
        init(onResolve: @escaping (UIWindowScene) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
            // Invisible and untouchable: this is a probe riding a
            // `.background`, and it must never take a press from the content
            // it sits behind.
            isUserInteractionEnabled = false
            isHidden = true
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            onResolve(scene)
        }
    }
}
