import SwiftUI
import WebKit

/// The in-app sign-in for the seats that took a key until prd §1584 —
/// Notion, Raindrop, Steam and OpenRouter. One sheet, two ways to finish:
///
/// - `.session`: the service's own page signs you in, and the sheet keeps the
///   cookies it leaves once the service itself says they are signed in
///   (`WebSession.verify`) — never on a cookie's name alone, since a
///   signed-out visit writes cookies too.
/// - `.redirect`: the page hands back a URL (OpenRouter's PKCE callback), which
///   the sheet stops before it loads and gives to the caller. Nothing is kept
///   from the jar.
///
/// Deliberately `WKWebView`, the stated exception to §653 that §703, §726,
/// §731 and §776 take: `.session` exists to read the cookie jar back, and
/// `.redirect` needs to stop a navigation to a localhost address no app
/// answers. The jar is PERSISTENT (an emailed code outlives an ephemeral one),
/// popups are real child windows (`LoginPopupWindow`), and the domain's old
/// cookies are cleared first, so a refused session is never captured back
/// before the form shows (`InstagramLoginWebView`'s lesson).
struct WebSessionSignInSheet: View {
    enum Capture {
        case session(WebSession.Seat)
        /// Stop at any URL starting with `prefix`; `onURL` gets it.
        case redirect(prefix: String, onURL: (URL) -> Void)
    }

    let title: String
    let start: URL
    /// The registrable domain whose old cookies are cleared before the page
    /// loads, and, for `.session`, whose jar is watched.
    let domain: String
    let capture: Capture
    /// Fires once, when the session is kept or the redirect arrives.
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebSessionLoginView(start: start, domain: domain, capture: capture, onDone: {
                onDone()
                dismiss()
            })
            .dsScreenTitle(title)
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

extension WebSessionSignInSheet {
    /// A session seat's sheet, every field read off the seat.
    init(seat: WebSession.Seat, onDone: @escaping () -> Void) {
        self.init(title: String(localized: "Sign in to \(seat.name)"), start: seat.loginURL,
                  domain: seat.domain, capture: .session(seat), onDone: onDone)
    }
}

private struct WebSessionLoginView: UIViewRepresentable {
    let start: URL
    let domain: String
    let capture: WebSessionSignInSheet.Capture
    let onDone: () -> Void

    /// Safari's own string. Google refuses its sign-in inside a web view that
    /// announces itself as one, and several of these pages offer it.
    static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    func makeCoordinator() -> Coordinator { Coordinator(capture: capture, domain: domain, onDone: onDone) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        let store = config.websiteDataStore.httpCookieStore
        let coordinator = context.coordinator
        let domain = domain
        let start = start
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.hasSuffix(domain) }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                coordinator.armed = true
                webView.load(URLRequest(url: start))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let capture: WebSessionSignInSheet.Capture
        let domain: String
        let onDone: () -> Void
        var armed = false
        private var finished = false
        /// One ask of the service at a time; a jar that changed meanwhile is
        /// asked again when the answer comes back.
        private var asking = false
        private var askAgain = false
        private let popup = LoginPopupWindow()

        init(capture: WebSessionSignInSheet.Capture, domain: String, onDone: @escaping () -> Void) {
            self.capture = capture
            self.domain = domain
            self.onDone = onDone
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            popup.open(over: webView, configuration: configuration, delegate: self)
        }

        func webViewDidClose(_ webView: WKWebView) { popup.close(webView) }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if case .redirect(let prefix, let onURL) = capture,
               let url = navigationAction.request.url, url.absoluteString.hasPrefix(prefix) {
                decisionHandler(.cancel)
                guard !finished else { return }
                finished = true
                onURL(url)
                onDone()
                return
            }
            decisionHandler(.allow)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !popup.holds(webView) else { return }
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard armed, !finished, case .session(let seat) = capture else { return }
            if asking { askAgain = true; return }
            asking = true
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let jar = cookies.filter { $0.domain.hasSuffix(self.domain) }
                if let gate = seat.gateCookie, !jar.contains(where: { $0.name == gate }) {
                    self.settle(cookieStore)
                    return
                }
                let header = WebSession.header(from: jar, for: seat.apiHost)
                guard !header.isEmpty else { self.settle(cookieStore); return }
                Task { @MainActor in
                    if await WebSession.verify(seat, header: header), !self.finished {
                        self.finished = true
                        WebSession.store(header, for: seat)
                        self.onDone()
                    }
                    self.settle(cookieStore)
                }
            }
        }

        private func settle(_ cookieStore: WKHTTPCookieStore) {
            DispatchQueue.main.async {
                self.asking = false
                if self.askAgain {
                    self.askAgain = false
                    self.check(cookieStore)
                }
            }
        }
    }
}
