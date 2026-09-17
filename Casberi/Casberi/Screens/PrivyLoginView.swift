import SwiftUI
import WebKit

/// Privy Home's sign-in, inside our own `WKWebView` (prd §803c) — Duolingo's
/// shape (`DuolingoLiveLoginSheet`) and its reason: this door exists to read
/// the session back, which Safari's sheet is built to prevent. A stated
/// exception to §653, as §703, §726, §731 and §776 are.
///
/// The gate is BOTH halves of a Privy session in the jar: an access token
/// (`privy-token` or `privy-access-token`) and `privy-refresh-token`. A
/// signed-out visit writes `privy-session` and analytics cookies and never
/// these, so nothing before the email code can close the sheet.
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
                let jar = cookies.filter { $0.domain.hasSuffix("privy.io") }
                    .map { (name: $0.name, value: $0.value) }
                guard let session = PrivyHomeFeed.session(jar) else { return }
                self.captured = true
                PrivyHomeAuth.store(access: session.access, refresh: session.refresh)
                // The session now lives in the Keychain; the jar's copy goes.
                let privy = cookies.filter { $0.domain.hasSuffix("privy.io") }
                for cookie in privy { cookieStore.delete(cookie) }
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }
}
