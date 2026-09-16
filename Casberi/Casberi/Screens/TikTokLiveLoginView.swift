import SwiftUI
import WebKit

/// The in-app sign-in that keeps TikTok's own session cookies (prd §731) —
/// `InstagramLiveLoginSheet`'s shape and reasoning: deliberately `WKWebView`,
/// because this door exists to read the cookie jar back, which Safari's sheet
/// is built to prevent.
///
/// Two differences from Instagram's. It loads the DESKTOP site
/// (`TikTokLiveFeed.desktopUserAgent`), the one whose reads were measured and
/// whose sign-in does not steer toward the app. And it keeps the WHOLE
/// tiktok.com jar rather than three named cookies: the reads were measured to
/// need the session cookie, not which of its companions, so the header is
/// exactly what the page itself would send.
struct TikTokLiveLoginSheet: View {
    /// Fires once, when the session lands — the presenter re-reads
    /// `TikTokLiveAuth.connected` from there.
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TikTokLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to TikTok"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct TikTokLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT: a two-step verification detour outlives an ephemeral jar.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = TikTokLiveFeed.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        // The login page opens Apple, Facebook, X and Google sign-in in a
        // POPUP window; with no UI delegate `window.open` does nothing and
        // those buttons are dead. The popup shares this configuration (and so
        // the cookie jar the coordinator watches).
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // FORGET tiktok.com's old cookies first — `InstagramLoginWebView`'s
        // lesson: the sheet opens only while nothing is stored, so a jar still
        // holding a refused session would be captured straight back and the
        // sheet would close before a login form showed.
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix("tiktok.com") }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: URL(string: TikTokLiveFeed.loginURL)!))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    /// `sessionid` is the gate: a signed-out visit writes a dozen tiktok.com
    /// cookies and never that one. Once it appears the capture waits two
    /// seconds, so the redirect after sign-in finishes writing the rest of the
    /// jar before it is read.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onCaptured: () -> Void
        private var captured = false
        private var pending = false
        var armed = false
        private let popup = LoginPopupWindow()

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for _: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
            popup.open(over: webView, configuration: configuration, delegate: self)
        }

        func webViewDidClose(_ webView: WKWebView) {
            popup.close(webView)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard armed, !captured, !pending else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured, !self.pending,
                      cookies.contains(where: { $0.name == "sessionid" && $0.domain.hasSuffix("tiktok.com") && !$0.value.isEmpty })
                else { return }
                self.pending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    cookieStore.getAllCookies { cookies in
                        let jar = cookies.filter { $0.domain.hasSuffix("tiktok.com") }
                            .map { (name: $0.name, value: $0.value) }
                        guard !self.captured, let header = TikTokLiveFeed.cookieHeader(jar) else {
                            self.pending = false
                            return
                        }
                        self.captured = true
                        TikTokLiveAuth.store(cookieHeader: header)
                        DispatchQueue.main.async { self.onCaptured() }
                    }
                }
            }
        }
    }
}
