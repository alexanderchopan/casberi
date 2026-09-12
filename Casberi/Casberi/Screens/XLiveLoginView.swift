import SwiftUI
import WebKit

/// The in-app sign-in that harvests X's own session cookies (prd §701) —
/// deliberately `WKWebView`, not `DSWebSheet`'s `SFSafariViewController`.
/// `DSWebSheet`'s own header note explains why every OTHER setup door in this
/// app avoids `WKWebView`: it does not share Safari's session, so a person
/// already signed in to a site is asked to sign in again. That is exactly
/// backwards here — this door exists BECAUSE it can read `auth_token`/`ct0`
/// back out of its OWN cookie store the moment the person signs in, which is
/// precisely the isolation Safari is built to keep. Harvesting the pair
/// honestly, in a screen that says what it is doing, IS the feature — not a
/// workaround standing in for one.
///
/// The default, PERSISTENT `WKWebsiteDataStore` (never `.nonPersistent()`):
/// an ephemeral store's cookies live only in memory for this presentation and
/// vanish the moment the view is torn down, before a slow sign-in (2FA, a
/// security checkpoint) could ever be trusted to have finished writing them.
/// `isInspectable` is DEBUG-only (iOS 16.4+) — Safari's Web Inspector has no
/// business attaching to a signed-in session in a shipped build.
struct XLiveLoginSheet: View {
    /// Fires once, the moment both cookies land — the presenter dismisses
    /// and re-reads `XLiveAuth.connected` from there, `AccountPageSheet`'s
    /// own ownership rule (`DSWebSheet`'s reason, restated: the ONE thing
    /// that closes this sheet is the caller, never the content itself).
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to X"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct XLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT on purpose — see the sheet's own header note.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.load(URLRequest(url: URL(string: "https://x.com/i/flow/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    /// Watches BOTH signals the mechanic names (prd §701): `cookiesDidChange`
    /// (a cookie can land mid-flow, well before any navigation finishes —
    /// the common case, since X writes `ct0` before the password step) and
    /// `didFinish` (belt and braces for the pair already sitting in this
    /// device's store from an earlier session, where the flow can redirect
    /// straight past login with no NEW cookie write to observe at all — only
    /// a finished navigation ever asks in that case). Whichever sees both
    /// cookies first wins; `captured` makes the other a no-op.
    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onCaptured: () -> Void
        private var captured = false

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard !captured else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                guard let auth = cookies.first(where: {
                        $0.name == "auth_token" && $0.domain.hasSuffix("x.com")
                    }),
                    let ct0 = cookies.first(where: {
                        $0.name == "ct0" && $0.domain.hasSuffix("x.com")
                    })
                else { return }
                self.captured = true
                XLiveAuth.store(authToken: auth.value, ct0: ct0.value)
                // `getAllCookies`'s completion is documented to land on the
                // main queue already; dispatching anyway costs nothing and
                // means this call site never depends on that being true.
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }
}
