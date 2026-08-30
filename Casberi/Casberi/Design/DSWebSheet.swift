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
/// **Passkeys are the reason this works.** `SFSafariViewController` shares
/// Safari's cookies and website data and runs the system's own passkey UI, so
/// signing up or signing in with Face ID inside this sheet is byte-for-byte
/// what happens in Safari, against the same iCloud Keychain. Casberi cannot
/// read a keystroke, a cookie or the page — it is a browser we are standing
/// next to, not one we are driving.
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

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // Never presented on Mac — `dsWebSheet` opens the browser instead.
        // Drawn as an empty page rather than a crash if a caller ever forgets.
        Color.clear.onAppear { UIApplication.shared.open(url) }
        #else
        SafariView(url: url).ignoresSafeArea()
        #endif
    }
}

#if !targetEnvironment(macCatalyst)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        // The reader and the bar-collapse are for articles. This is a form.
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

extension View {
    /// Present `url` in-app on iOS, and in the real browser on Mac.
    ///
    /// The binding is a `URL?` rather than a `Bool` so a screen with several
    /// doors needs one presentation, not one per door — the "one screen, one
    /// sheet" rule this project has paid for three times.
    func dsWebSheet(_ url: Binding<URL?>) -> some View {
        #if targetEnvironment(macCatalyst)
        return onChange(of: url.wrappedValue) { _, new in
            guard let new else { return }
            UIApplication.shared.open(new)
            url.wrappedValue = nil
        }
        #else
        return sheet(item: Binding(get: { url.wrappedValue.map(DSWebSheetTarget.init) },
                                   set: { url.wrappedValue = $0?.url })) { target in
            DSWebSheet(url: target.url)
        }
        #endif
    }
}

/// `sheet(item:)` needs identity, and `URL` is not `Identifiable`.
private struct DSWebSheetTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
