import SwiftUI
import WebKit

/// The in-app sign-in that harvests Instagram's own session cookies (prd
/// §726) — `XLiveLoginSheet`'s shape, one seat over, and its reasoning
/// verbatim: deliberately `WKWebView`, not `DSWebSheet`'s Safari sheet,
/// because this door exists to read `sessionid`/`csrftoken`/`ds_user_id` back
/// out of its OWN cookie store the moment the person signs in, which is
/// precisely the isolation Safari is built to keep.
///
/// The default, PERSISTENT `WKWebsiteDataStore`: Instagram's sign-in routinely
/// detours through a two-factor prompt or a "confirm it's you" checkpoint, and
/// an ephemeral store's cookies would be gone before that slow flow could be
/// trusted to have finished writing them. `isInspectable` is DEBUG-only.
struct InstagramLiveLoginSheet: View {
    /// Fires once, the moment all three cookies land — the presenter dismisses
    /// and re-reads `InstagramLiveAuth.connected` from there, the page's own
    /// ownership rule: the ONE thing that closes this sheet is the caller.
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InstagramLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to Instagram"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct InstagramLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // PERSISTENT on purpose — see the sheet's own header note.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // FORGET instagram.com's old cookies before the page loads. The sheet
        // only opens while `InstagramLiveAuth` holds nothing — never signed in,
        // or cleared because Instagram refused the session — and the persistent
        // store would otherwise hand that SAME refused session straight back on
        // the first `didFinish`, closing the sheet before a login form ever
        // showed: tap Connect, flash, refused, cleared, forever. The coordinator
        // is armed only once the purge has finished, so no half-deleted jar is
        // read in between.
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix("instagram.com") }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    /// Both signals, `XLoginWebView`'s reasoning: `cookiesDidChange` for the
    /// common case (Instagram writes `csrftoken` on the first page load and
    /// `sessionid`/`ds_user_id` the moment the password is accepted, well
    /// before any navigation finishes) and `didFinish` for a session already
    /// sitting in this device's store from an earlier sign-in, where the flow
    /// redirects straight past login with no new cookie write to observe.
    ///
    /// **`ds_user_id` is the gate, not `sessionid` alone.** A signed-OUT visit
    /// leaves a stale `sessionid` on some accounts; `ds_user_id` is written
    /// only by a completed sign-in and cleared by a sign-out, so requiring all
    /// three is what keeps a half-finished login from being stored as a whole
    /// one — §711's anonymous-token lesson, at the cookie layer.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onCaptured: () -> Void
        private var captured = false
        /// False until `makeUIView`'s purge of the old instagram.com cookies
        /// has finished — see there.
        var armed = false

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }
        private let popup = LoginPopupWindow()

        /// "Continue with Apple/Google" opens a REAL popup — see `LoginPopupWindow`.
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
            guard armed, !captured else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                func value(_ name: String) -> String? {
                    cookies.first {
                        $0.name == name && $0.domain.hasSuffix("instagram.com") && !$0.value.isEmpty
                    }?.value
                }
                guard let session = value("sessionid"),
                      let csrf = value("csrftoken"),
                      let user = value("ds_user_id")
                else { return }
                self.captured = true
                InstagramLiveAuth.store(sessionID: session, csrfToken: csrf, userID: user)
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }
}
