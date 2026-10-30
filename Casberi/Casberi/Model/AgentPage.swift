import Foundation
import UIKit
import WebKit

/// An agent's own web page, kept open out of sight in WebKit's default jar —
/// the host `MuseWeb` and `ChatGPTWeb` share (prd §1619, §1623). The cookies
/// are the ones `WebSessionSignInSheet` left there; nothing here reads or
/// stores them.
///
/// **Inside the window, UNDER the app's own screen.** Off the window's edge
/// (Muse's first cut) WebKit counted the page as not visible and its chat
/// never loaded or sent (measured 2026-10-30: no history after 30 s, the
/// question never reached the chat); in no window at all it is slowed the
/// same way. The app's opaque screen covers it, so nobody sees it.
@MainActor
final class AgentPage: NSObject {

    /// Why an ask through an agent's page came back with no answer.
    enum Failure: Error {
        case signedOut
        case noPage
        case couldNotSend
        case noReply
    }

    let home: URL
    let domain: String
    private let script: String

    private var webView: WKWebView?
    private var loaded = false
    private var loadWaiters: [CheckedContinuation<Bool, Never>] = []

    init(home: URL, domain: String, script: String) {
        self.home = home
        self.domain = domain
        self.script = script
    }

    /// Where the page is now, or nil before it opens.
    var url: URL? { webView?.url }

    /// Loads `url` (home by default) unless the page is already open there.
    /// False when the page never finished.
    func open(_ url: URL? = nil, reload: Bool = false) async -> Bool {
        let target = url ?? home
        if webView != nil, loaded, !reload, url == nil || webView?.url == target { return true }
        // A load already under way is waited on, never started twice.
        if webView != nil, !loadWaiters.isEmpty, !reload, url == nil {
            return await withCheckedContinuation { loadWaiters.append($0) }
        }
        if webView == nil {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            // muse.ai's signed-out page plays a video, and on a phone WebKit
            // plays video FULL SCREEN unless told otherwise: the hidden page
            // took over the whole screen (seen 2026-10-30). Inline, and
            // never without a tap, which this page never gets.
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = .all
            config.allowsPictureInPictureMediaPlayback = false
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            view.customUserAgent = WebSession.safariUserAgent
            view.isUserInteractionEnabled = false
            view.navigationDelegate = self
            #if DEBUG
            if #available(iOS 16.4, *) { view.isInspectable = true }
            #endif
            if let window = Self.hostWindow() {
                view.frame = window.bounds
                window.insertSubview(view, at: 0)
            }
            webView = view
        }
        loaded = false
        webView?.load(URLRequest(url: target))
        return await withCheckedContinuation { loadWaiters.append($0) }
    }

    private static func hostWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private func settleLoad(_ finished: Bool) {
        loaded = finished
        for waiter in loadWaiters { waiter.resume(returning: finished) }
        loadWaiters = []
    }

    /// Runs `js` as an async function body in the page; nil on any failure.
    func run(_ js: String, _ arguments: [String: Any] = [:]) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.callAsyncJavaScript(js, arguments: arguments, in: nil, contentWorld: .page)
    }

    /// Asks `check` (a script returning true or false) up to `tries` times,
    /// half a second apart.
    func waitFor(_ check: String, tries: Int = 20) async -> Bool {
        for _ in 0..<tries {
            if (await run(check) as? Bool) == true { return true }
            try? await Task.sleep(for: .seconds(0.5))
        }
        return false
    }

    /// Signing out of the seat: the page closes and the domain's cookies go.
    func forget() {
        webView?.removeFromSuperview()
        webView = nil
        settleLoad(false)
        let domain = domain
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.hasSuffix(domain) {
                store.delete(cookie)
            }
        }
    }
}

extension AgentPage: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { settleLoad(true) }
    }

    /// A navigation cancelled by the next load is not a failure: the next
    /// load's own finish answers its waiters.
    private nonisolated static func cancelled(_ error: any Error) -> Bool {
        (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard !Self.cancelled(error) else { return }
        MainActor.assumeIsolated { settleLoad(false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: any Error) {
        guard !Self.cancelled(error) else { return }
        MainActor.assumeIsolated { settleLoad(false) }
    }

    /// iOS reclaims a page's process in the background; the next ask opens a
    /// fresh one.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            self.webView?.removeFromSuperview()
            self.webView = nil
            settleLoad(false)
        }
    }
}
