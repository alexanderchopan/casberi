import SwiftUI
import WebKit

/// Privy Home's sign-in, inside our own `WKWebView` (prd §803c) — Duolingo's
/// shape (`DuolingoLiveLoginSheet`) and its reason: this door exists to read
/// the session back, which Safari's sheet is built to prevent. A stated
/// exception to §653, as §703, §726, §731 and §776 are.
///
/// The gate is a signed-in session in the jar: an access token (`privy-token`
/// or `privy-access-token`) and `privy-refresh-token`. A signed-out visit
/// writes `privy-session` and analytics cookies and never these, so nothing
/// before the email code can close the sheet. What is KEPT is every cookie the
/// API host would receive, by name (`PrivyHomeFeed.apiCookies`) — Privy Home
/// authenticates by cookie, and its two access tokens are different values.
struct PrivyLoginSheet: View {
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrivyLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to Privy"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct PrivyLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT: the email code is read in another app, and an ephemeral
        // jar does not reliably outlive the switch (§731's reason).
        config.websiteDataStore = .default()
        // Privy Home's /login is a landing card whose "Get started" opens the
        // email form; no URL opens the form directly (read from its bundle,
        // 2026-09-17: the button calls the SDK's `login()`). Press it once, so
        // the sheet opens ON the sign-in (user: "make it so the page it first
        // hits is the actual sign in page").
        config.userContentController.addUserScript(
            WKUserScript(source: Self.skipLanding, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // Forget privy.io's old cookies first — this sheet opens only while
        // nothing is stored, so a jar still holding a refused session would be
        // captured straight back (`InstagramLoginWebView`'s lesson).
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix("privy.io") }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: URL(string: PrivyHomeFeed.loginURL)!))
            }
        }
        return webView
    }

    /// Waits up to five seconds for the landing's button, clicks it once,
    /// and does nothing on any other page or once an email field exists.
    private static let skipLanding = """
    (function() {
        if (location.hostname !== 'home.privy.io' || location.pathname.indexOf('/login') !== 0) { return; }
        var tries = 0;
        var timer = setInterval(function() {
            tries += 1;
            if (document.querySelector('input[type="email"]') || tries > 50) { clearInterval(timer); return; }
            var buttons = document.querySelectorAll('button');
            for (var i = 0; i < buttons.length; i++) {
                if ((buttons[i].textContent || '').trim() === 'Get started') {
                    clearInterval(timer);
                    buttons[i].click();
                    return;
                }
            }
        }, 100);
    })();
    """

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onCaptured: () -> Void
        private var captured = false
        var armed = false
        private var popup: WKWebView?

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        /// "Continue with Google/Apple" opens a real child window that hands
        /// its result back through `window.opener`.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            popup?.removeFromSuperview()
            let child = WKWebView(frame: webView.bounds, configuration: configuration)
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            child.navigationDelegate = self
            child.uiDelegate = self
            webView.addSubview(child)
            popup = child
            return child
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popup else { return }
            webView.removeFromSuperview()
            popup = nil
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard armed, !captured else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                let session = PrivyHomeFeed.apiCookies(
                    cookies.map { (name: $0.name, value: $0.value, domain: $0.domain) })
                guard PrivyHomeFeed.isSession(session) else { return }
                self.captured = true
                PrivyHomeAuth.store(session)
                // The session now lives in the Keychain; the jar's copy goes.
                let privy = cookies.filter { $0.domain.hasSuffix("privy.io") }
                for cookie in privy { cookieStore.delete(cookie) }
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }
}
