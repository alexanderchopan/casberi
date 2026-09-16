import SwiftUI
import WebKit

/// The in-app sign-in that keeps Duolingo's own session cookie (prd §776) —
/// `TikTokLiveLoginSheet`'s shape and reasoning: deliberately `WKWebView`,
/// because this door exists to read the cookie jar back, which Safari's sheet
/// is built to prevent. A stated exception to §653's "every setup door opens
/// the in-app Safari sheet", for the same reason §703, §726 and §731 are.
///
/// The gate is `jwt_token` THAT DECODES. A signed-out visit to duolingo.com
/// writes cookies too, and a token carrying no `sub` claim is a credential
/// every later read would refuse — so `DuolingoFeed.bearer` asks both
/// questions and this sheet asks nothing else. No settle timer: unlike
/// TikTok's jar, the whole credential is that one cookie, and a cookie the
/// store hands back is complete.
struct DuolingoLiveLoginSheet: View {
    /// Fires once, when the session lands — the presenter re-reads
    /// `DuolingoLiveAuth.connected` from there.
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DuolingoLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to Duolingo"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct DuolingoLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT: an email verification code or a two-step detour outlives
        // an ephemeral jar (§731's reason, measured there).
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = DuolingoFeed.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        // Duolingo's login page opens Google, Facebook and Apple sign-in in a
        // POPUP window; with no UI delegate `window.open` does nothing and
        // those buttons are dead taps. The popup shares this configuration,
        // and so the cookie jar the coordinator watches.
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // FORGET duolingo.com's old cookies first — `InstagramLoginWebView`'s
        // lesson: this sheet opens only while nothing is stored, so a jar
        // still holding a refused session would be captured straight back and
        // the sheet would close before a login form ever showed.
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix("duolingo.com") }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: URL(string: DuolingoFeed.loginURL)!))
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
        /// The provider's sign-in window, laid over the login page. Kept as a
        /// real web view rather than loaded in place, because the provider
        /// hands the result back through `window.opener`.
        private var popup: WKWebView?

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            popup?.removeFromSuperview()
            let child = WKWebView(frame: webView.bounds, configuration: configuration)
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            child.customUserAgent = webView.customUserAgent
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
                let jar = cookies.filter { $0.domain.hasSuffix("duolingo.com") }
                    .map { (name: $0.name, value: $0.value) }
                guard let token = DuolingoFeed.bearer(jar) else { return }
                self.captured = true
                DuolingoLiveAuth.store(token: token)
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }
}
