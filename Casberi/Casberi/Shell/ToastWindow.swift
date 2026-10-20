import SwiftUI
import UIKit

/// **THE TOAST DRAWS ABOVE EVERY SHEET (prd §1443).** `ShellChrome.flash` sets
/// `chrome.toast`, and the toast used to be drawn in `RootShell`'s own ZStack.
/// A SwiftUI `.sheet` is presented above that whole tree, so a flash raised
/// from inside any sheet or tray — a failure, "Address copied", an Undo —
/// drew UNDER it and nobody saw it (measured 2026-10-20 in the Move tray,
/// §1442c, where every message vanished).
///
/// So the toast lives in its own clear window per scene, one level above the
/// app's window and below `PrivacyCover`'s (`.alert + 1`): above the root
/// view, every sheet and the composer, and still hidden by the app-switcher
/// cover. The window takes no touch of its own: `hitTest` answers only inside
/// the pill, and only while the pill carries an action (the drop-capture
/// Undo), the rule the in-shell toast kept with `allowsHitTesting`.
///
/// **Per scene**, for the reason `PrivacyCover`'s header gives: two iPad
/// windows each have their own `RootShell` and their own `ShellChrome`.
///
/// **The Mac keeps the toast in the shell** (`usesWindow` is false there):
/// a second UIWindow in a Catalyst scene is not measured here, and the Mac's
/// sheets are its own question. The pill is one view, `ToastPill`, drawn by
/// both, so the two cannot drift.
@MainActor
enum ToastWindow {
    /// The phone and the iPad draw the toast in its own window.
    static var usesWindow: Bool { !ProcessInfo.processInfo.isMacCatalystApp }

    private static var windows: [ObjectIdentifier: PassthroughWindow] = [:]

    /// Raise the scene's toast window once; later calls for the same scene
    /// do nothing, so `WindowSceneReader` may call it as often as it fires.
    static func install(on scene: UIWindowScene, chrome: ShellChrome) {
        guard usesWindow else { return }
        for (key, w) in windows where w.windowScene == nil { windows[key] = nil }
        let key = ObjectIdentifier(scene)
        guard windows[key] == nil else { return }
        let w = PassthroughWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastLayer(chrome: chrome) { [weak w] rect in
            w?.interactive = rect
        })
        host.view.backgroundColor = .clear
        w.backgroundColor = .clear
        // Above the app's window and its sheets, below the privacy cover.
        w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1)
        w.rootViewController = host
        // Shown, never key: the app's window keeps the keyboard and focus.
        w.isHidden = false
        windows[key] = w
    }

    /// A window that is there only where the toast's action is.
    final class PassthroughWindow: UIWindow {
        /// The pill's frame in this window while it carries an action, else nil.
        var interactive: CGRect?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let interactive, interactive.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

/// The toast as it stands over everything: bottom-centred, 140 above the edge,
/// crossfading when a flash replaces it. Drawn by `ToastWindow` on the phone
/// and the iPad, and by `RootShell` on the Mac.
struct ToastLayer: View {
    let chrome: ShellChrome
    /// Told the pill's frame while it carries an action, and nil otherwise,
    /// so the window above can take that touch and no other.
    var onInteractive: ((CGRect?) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let toast = chrome.toast {
                ToastPill(chrome: chrome, text: toast)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                        onInteractive?(chrome.toastAction == nil ? nil : rect)
                    }
                    .padding(.bottom, 140)
                    // A replacing flash swaps identity — crossfade, never a
                    // stack (§12). The `.id` rides the whole glass unit.
                    .id(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // A plain outcome pill lets taps fall through to what is
                    // under it; only a toast carrying an action stays
                    // interactive (perf/hit-test pass 2026-07-13).
                    .allowsHitTesting(chrome.toastAction != nil)
            }
        }
        .onChange(of: chrome.toast == nil || chrome.toastAction == nil) { _, plain in
            if plain { onInteractive?(nil) }
        }
        // The window inherits nothing from the shell: the person's mode and
        // language, the same two the shell applies to its whole tree.
        .environment(\.locale, LanguageStore.shared.locale)
        .preferredColorScheme(
            ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil ? .light : .dark
        )
        .ignoresSafeArea(.keyboard)
    }
}

/// Transient chrome floating over content — it wears glass.
///
/// The pill and its one action are concentric glass — a tinted prominent
/// capsule (the drop-capture Undo) riding inside the clear glass pill —
/// so they live in a `DSGlassContainer`: the container is what lets the
/// inner button lens against the SAME backdrop sample as the pill instead
/// of compositing as an unrelated glass layer stacked on top (2026-07-23,
/// the first real use of the container the design system already shipped).
struct ToastPill: View {
    let chrome: ShellChrome
    let text: String

    var body: some View {
        DSGlassContainer(spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                // The first thing ever gets the mark (§8). Once. The first-ever
                // kept ask (composer delight, 2026-07-21) shares the treatment —
                // both are "your first standing X with Casberi" moments.
                if text == "Your first thing" || text.hasPrefix("Your first standing question") {
                    CasberiMark(size: 18)
                } else if let mark = chrome.toastMark {
                    // A moment's toast wears the brand it's about (prd §384) —
                    // whose news this is, said before a word is read.
                    BridgeIcon(name: mark, size: DS.Face.badge, circular: true)
                }
                Text(DSProse.unorphaned(text))
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                if let action = chrome.toastAction {
                    // The pane's one action reads as ITS interactive part —
                    // a tinted glass capsule riding the glass pill.
                    // DRAWN 28, TARGETED 44: the glass rides the label so it keeps
                    // the capsule's size, and the floor goes on after it.
                    Button(action: action.run) {
                        Text(action.label)
                            .dsText(.label12)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.s3)
                            .frame(minHeight: 28)
                            .dsGlassProminent(tint: DS.pickInk, cornerRadius: DS.Radius.pill)
                            .dsTapTarget(Capsule(style: .continuous))
                    }
                    .buttonStyle(PressSpring())
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s2)
            .dsGlass(cornerRadius: DS.Radius.pill)
            // It MATERIALIZES (2026-08-06). A toast is the one piece of chrome
            // here that exists ONLY as an arrival — it appears because
            // something just happened and then it's gone. Applied inside the
            // container so the pill and its Undo capsule form together.
            .dsGlassMaterialize()
        }
    }
}
