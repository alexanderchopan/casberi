import SwiftUI
#if !targetEnvironment(macCatalyst)
import SafariServices
#endif

/// A page opened INSIDE the app (prd §529, 2026-08-29) — Safari's engine and
/// Safari's session, presented as a sheet.
///
/// ## WHY THIS EXISTS RATHER THAN `openURL`
///
/// Every "Get your API key" button in this app has been a one-way door: it
/// hands the person to Safari, the app goes to the background, and whatever
/// they were half-way through is behind them. For Bankr that is the whole
/// setup — make an account, mint a key, come back — so the trip out was most
/// of the experience.
///
/// **Passkeys and Password AutoFill are the reason this works.**
/// `SFSafariViewController` runs the system's own passkey UI and the
/// keyboard's AutoFill bar (iCloud Keychain, or a manager like 1Password),
/// so signing in with Face ID inside this sheet is what happens in Safari.
/// What it does NOT share is Safari's cookies — this file said it did, and
/// that stopped being true in iOS 11: the sheet has its own website data,
/// kept per app and persisted between openings (iOS 16's
/// `SFSafariViewController.DataStore` exists to clear it). So the sheet
/// lands on the provider's sign-in page, not already inside; the fast door
/// through it is AutoFill, and a REOPENED sheet lands signed in. Casberi
/// cannot read a keystroke, a cookie or the page — it is a browser we are
/// standing next to, not one we are driving.
///
/// ## HALF AND FULL (prd §653)
///
/// Every setup screen's door opens here since §653 (`AccountPage.doorAction`),
/// and the sheet has TWO detents. Dragged to half, the page beneath stays
/// live — scroll it and the entry row comes clear of the sheet (the page
/// keeps the sheet's height of room under its act while the door is up) —
/// so the trip is: door, sign in, copy, drag the sheet down, scroll, tap
/// Paste; drag it back up if the site is needed again, same page, still
/// signed in. It opens full, because a form wants the room. The sheet
/// DISMISSING is not what offers the paste (the row lights on first open,
/// `accountDoorOpened`), so nothing depends on catching a dismissal. The
/// way OUT is on both sides: the sheet's own compass opens the page in
/// Safari, and a long press on the door does the same (`dsDoorWayOut`).
///
/// **Deliberately NOT `ASWebAuthenticationSession`**, which the OAuth bridges
/// use: that type is built to END on a redirect to our own scheme, and shows a
/// consent alert saying the site and app will share information about you.
/// Neither is true here — there is no callback, and nothing is shared. Using
/// it would put a false sentence in front of somebody at the exact moment they
/// are deciding whether to trust this.
///
/// **And deliberately NOT `WKWebView`**, which does not share Safari's session,
/// so a person already signed in to the site would be asked to sign in again —
/// and whose passkey support is not the system's.
///
/// ## MAC
///
/// `SFSafariViewController` is unavailable on Mac Catalyst, so there the sheet
/// is not drawn at all and the caller's `onUnavailable` opens the real browser.
/// The Mac has an actual browser window a person can leave open beside the
/// app, which is the thing an iPhone does not, so the fallback loses nothing.
struct DSWebSheet: View {
    let url: URL
    /// Opens at `.large` on every door — a fresh sheet per URL, so nothing
    /// carries the last one's height over.
    @State private var detent: PresentationDetent = .large
    /// The presenter closes this sheet by clearing its own item, rather than
    /// the content calling `@Environment(\.dismiss)`. That is the tidier
    /// ownership and it is the shape kept — but it is NOT a fix for the
    /// behaviour below, and the first version of this comment claimed it was.
    ///
    /// **MEASURED, AND STILL TRUE: DONE COLLAPSES BOTH SHEETS.** Opened from a
    /// key sheet on Venice, tapping this controller's Done lands on the account
    /// page with the key sheet gone, not back on the key sheet. Swapping
    /// `dismiss()` for a presenter-owned close changed nothing, which is what
    /// identifies the cause: `SFSafariViewController` runs its OWN dismissal
    /// for that button, and hosted as a sheet's content the thing it dismisses
    /// is the presentation it is embedded in. Only presenting it through UIKit
    /// rather than embedding it would separate the two, and that is a larger
    /// change than this bought.
    ///
    /// **It costs a tap, not the feature**, which is why it is recorded rather
    /// than chased: the designed return leg is the DRAG, and that is verified
    /// working from both doors — pulled to half from a key sheet, the key row
    /// and its paste chip sit live above the page (prd §653). Done is the exit
    /// for somebody who is finished, and it exits to a page whose "Your key"
    /// row reopens the sheet in one tap.
    let onDone: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // Never presented on Mac — `AccountPage.doorAction` keeps the system
        // action there. Drawn as an empty page rather than a crash if a
        // caller ever forgets.
        Color.clear.onAppear { UIApplication.shared.open(url) }
        #else
        SafariView(url: url, onDone: onDone)
            .ignoresSafeArea()
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            // iPad sizes sheets as fixed pages and honours no detent, so the
            // half-sheet leg is an iPhone thing; the page sizing keeps it the
            // same object every other sheet here is (`DSNavSheet`'s lesson).
            .dsPageSheet()
        #endif
    }
}

#if !targetEnvironment(macCatalyst)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        // The reader and the bar-collapse are for articles. This is a form.
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        // THE PHONE'S OWN APPEARANCE, never the app's theme. The sheet reads
        // as Safari, not as this app — a dark Casberi shows a light Safari
        // on a light phone — and that is the point (user, 2026-09-08): it is
        // the right signal at the moment someone is typing a password; an
        // app-coloured browser chrome is what a phishing sheet would draw.
        // Set explicitly rather than inherited, because a presented sheet in
        // this app wears `dsColorScheme()` and the controller would take
        // THAT trait when hosted inside the key sheet (seen: dark there,
        // light from the page, for the same site).
        controller.overrideUserInterfaceStyle = Self.systemStyle
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        controller.overrideUserInterfaceStyle = Self.systemStyle
    }

    private static var systemStyle: UIUserInterfaceStyle {
        UIScreen.main.traitCollection.userInterfaceStyle
    }

    /// Done is the controller's own button; hosted inside a SwiftUI sheet it
    /// dismisses the controller, not the sheet's item — this closes the item.
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}
#endif
