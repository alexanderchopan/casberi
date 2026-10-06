import SwiftUI
import WebKit

/// The in-app sign-in that keeps Threads' own session cookies (prd §1131) —
/// `TikTokLiveLoginSheet`'s shape and reasoning: deliberately `WKWebView`,
/// because this door exists to read the cookie jar back, which Safari's sheet
/// is built to prevent.
///
/// Threads has no password of its own: "Log in with Instagram" goes to
/// Instagram's login and comes back to threads.com signed in (measured
/// 2026-10-05). Only threads.com's cookies are purged and kept — an Instagram
/// session already in this store is what can make that a single tap, and it
/// belongs to the Instagram seat, not this one.
struct ThreadsLiveLoginSheet: View {
    /// Fires once, when the session lands — the presenter re-reads
    /// `ThreadsLiveAuth.connected` from there.
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ThreadsLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to Threads"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct ThreadsLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT: Meta's "confirm it was you" detour outlives an ephemeral jar.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = ThreadsLiveFeed.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // FORGET threads.com's old cookies first — `InstagramLoginWebView`'s
        // lesson: the sheet opens only while nothing is stored, so a jar still
        // holding a refused session would be captured straight back and the
        // sheet would close before a login form showed.
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix("threads.com") || $0.domain.hasSuffix("threads.net") }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: URL(string: ThreadsLiveFeed.loginURL)!))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    /// `sessionid` AND `ds_user_id` on threads.com are the gate: a signed-out
    /// visit writes `mid` and `csrftoken` and never the pair, and the
    /// Instagram leg of the sign-in writes them on instagram.com, which is
    /// not this jar's. Once both appear the capture waits two seconds, so the
    /// redirect back finishes writing the rest of the jar before it is read.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onCaptured: () -> Void
        private var captured = false
        private var pending = false
        var armed = false
        private let popup = LoginPopupWindow()

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
            #if DEBUG
            NSLog("[Casberi] threadsLogin| popup %@%@", action.request.url?.host ?? "—", action.request.url?.path ?? "")
            #endif
            return popup.open(over: webView, configuration: configuration, delegate: self)
        }

        #if DEBUG
        /// Where the sign-in goes, host and path only — a query can carry a
        /// one-time login code.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            NSLog("[Casberi] threadsLogin| nav %@ %@%@ main=%d", url?.scheme ?? "—", url?.host ?? "—",
                  url?.path ?? "", action.targetFrame?.isMainFrame == true ? 1 : 0)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            NSLog("[Casberi] threadsLogin| failed %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            NSLog("[Casberi] threadsLogin| failed provisional %@", error.localizedDescription)
        }
        #endif

        func webViewDidClose(_ webView: WKWebView) {
            popup.close(webView)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
            bounceBackIfStranded(webView)
        }

        /// Instagram's login can drop the trip back: measured 2026-10-05, a
        /// sign-in from Threads' page ended on Instagram's own feed after its
        /// "Save your login info?" step, signed in to Instagram and not to
        /// Threads. Landing on Instagram's home or that step with no Threads
        /// session sends the sheet back to Threads' login, where the Instagram
        /// session just made is one tap. Twice at most, so a page that keeps
        /// sending us there is never a loop.
        private var bounces = 0
        private func bounceBackIfStranded(_ webView: WKWebView) {
            guard armed, !captured, !pending, bounces < 2,
                  let url = webView.url, (url.host ?? "").hasSuffix("instagram.com") else { return }
            let path = url.path
            guard path.isEmpty || path == "/" || path.hasPrefix("/accounts/onetap") else { return }
            bounces += 1
            webView.load(URLRequest(url: URL(string: ThreadsLiveFeed.loginURL)!))
        }

        private func threadsJar(_ cookies: [HTTPCookie]) -> [(name: String, value: String)] {
            cookies.filter { $0.domain.hasSuffix("threads.com") }.map { (name: $0.name, value: $0.value) }
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard armed, !captured, !pending else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured, !self.pending,
                      ThreadsLiveFeed.cookieHeader(self.threadsJar(cookies)) != nil
                else { return }
                self.pending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    cookieStore.getAllCookies { cookies in
                        guard !self.captured, let header = ThreadsLiveFeed.cookieHeader(self.threadsJar(cookies)) else {
                            self.pending = false
                            return
                        }
                        self.captured = true
                        ThreadsLiveAuth.store(cookieHeader: header)
                        DispatchQueue.main.async { self.onCaptured() }
                    }
                }
            }
        }
    }
}
