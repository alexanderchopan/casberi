import SwiftUI
import WebKit

/// Connect Bankr: sign in on Bankr's own page, and the key is made for you
/// (prd §800). What this may do, and why, is `BankrKeyMint`'s header.
///
/// `WKWebView`, not `DSWebSheet`, for `XLiveLoginSheet`'s reason: the call
/// that makes the key has to run on bankr.bot's page, with the session that
/// page just signed in. Unlike X's sheet the jar is NON-PERSISTENT — the key
/// is the credential this seat keeps, and a Bankr session is a wallet's
/// session, so nothing of it outlives the sheet.
///
/// The sheet never reads a cookie's value, a keystroke or the page. It learns
/// three things: that `privy-token` exists (a name), whether Privy called the
/// sign-in a NEW account (one boolean, so the result can say so), and the key
/// the one call returns.
struct BankrSignInSheet: View {
    /// The key, and whether this sign-in created the Bankr account. The
    /// presenter checks the key with Bankr before anything is stored.
    let onKey: (_ key: String, _ newAccount: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    /// What the bottom line says: nothing while signing in, the making of the
    /// key once signed in, and a failure in words (§83 — a sheet that simply
    /// stays open says nothing about why).
    @State private var making = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            BankrSignInWebView(
                onKey: { key, fresh in
                    onKey(key, fresh)
                    dismiss()
                },
                onMaking: { making = true; failure = nil },
                onFailure: { making = false; failure = $0 })
            .dsScreenTitle(String(localized: "Sign in to Bankr"))
            .dsSheetDismiss { dismiss() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if making || failure != nil {
                    BridgeSyncStatusRows(syncing: making,
                                         syncingLine: String(localized: "Making a read-only key…"),
                                         proof: failure.map { .failed($0) })
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s3)
                        .dsPageBackground()
                }
            }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct BankrSignInWebView: UIViewRepresentable {
    let onKey: (String, Bool) -> Void
    let onMaking: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKey: onKey, onMaking: onMaking, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // bankr.bot's landing page autoplays a video; without this it takes
        // the whole screen in the system player and the sheet reads as black.
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(
            WKUserScript(source: Self.newAccountScript, injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: Coordinator.newAccountMessage)
        config.userContentController.addUserScript(
            WKUserScript(source: Self.openSignInScript, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.webView = webView
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.load(URLRequest(url: BankrKeyMint.startURL))
        context.coordinator.startWatching()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopWatching()
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: Coordinator.newAccountMessage)
    }

    /// Signed out, bankr.bot's chat is a page with one "Sign in" button, and
    /// the sign-in methods are behind it (user, 2026-09-16: "you have to click
    /// that to get to sign in page, but it's not clear to all users"). The
    /// sheet presses it once, as soon as it renders. Nothing else on the page
    /// is touched, and a renamed button costs only the tap this saves: the
    /// page still shows it.
    private static let openSignInScript = """
    (function() {
        if (!/^\\/terminal\\/chat/.test(location.pathname)) { return; }
        var tries = 0;
        var timer = setInterval(function() {
            tries += 1;
            var button = Array.prototype.find.call(document.querySelectorAll('button'), function(b) {
                return (b.textContent || '').trim() === 'Sign in';
            });
            if (button) { clearInterval(timer); button.click(); }
            else if (tries > 40) { clearInterval(timer); }
        }, 250);
    })();
    """

    /// Privy answers every sign-in method (`passwordless`, `oauth`,
    /// `farcaster`, `telegram`) with `is_new_user`. The page's own response is
    /// cloned and only that one boolean crosses; nothing else is posted.
    private static let newAccountScript = """
    (function() {
        var orig = window.fetch;
        window.fetch = function() {
            var args = arguments;
            var first = args[0];
            var url = (typeof Request !== 'undefined' && first instanceof Request) ? first.url : String(first);
            return orig.apply(this, args).then(function(response) {
                try {
                    if (/(^|\\.)privy\\.bankr\\.bot\\//.test(url.replace(/^https?:\\/\\//, ''))) {
                        response.clone().json().then(function(data) {
                            if (data && data.is_new_user === true) {
                                window.webkit.messageHandlers.bankrNewAccount.postMessage(true);
                            }
                        }).catch(function() {});
                    }
                } catch (e) {}
                return response;
            });
        };
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                             WKHTTPCookieStoreObserver, WKScriptMessageHandler {
        static let newAccountMessage = "bankrNewAccount"

        let onKey: (String, Bool) -> Void
        let onMaking: () -> Void
        let onFailure: (String) -> Void
        weak var webView: WKWebView?
        /// SEEN on the first real run (2026-09-16): the sheet sat signed in on
        /// the key page with nothing happening — the cookie observer is the
        /// suspect, since a non-persistent store's notifications are not
        /// promised. The jar is asked on a short timer too, and the observer
        /// stays as the fast path where it does fire.
        private var watch: Timer?
        private let popup = LoginPopupWindow()
        private var newAccount = false
        private var minting = false
        private var done = false
        /// A `signedOut` answer right after sign-in is usually a session still
        /// being written; the next cookie change retries, a bounded number of
        /// times, so a refused session cannot loop.
        private var attempts = 0
        private static let maxAttempts = 3
        /// Signed in while the page was somewhere other than bankr.bot (an
        /// X or Telegram hop): mint once bankr.bot has loaded again.
        private var mintOnLoad = false

        init(onKey: @escaping (String, Bool) -> Void, onMaking: @escaping () -> Void,
             onFailure: @escaping (String) -> Void) {
            self.onKey = onKey
            self.onMaking = onMaking
            self.onFailure = onFailure
        }

        func startWatching() {
            watch?.invalidate()
            watch = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                guard let self, let store = self.webView?.configuration.websiteDataStore.httpCookieStore
                else { return }
                self.check(store)
            }
        }

        func stopWatching() {
            watch?.invalidate()
            watch = nil
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.body as? Bool == true { newAccount = true }
        }

        // MARK: Sign-in finished?

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            guard !popup.holds(webView) else { return }
            if mintOnLoad, BankrKeyMint.isBankrPage(webView.url) {
                mintOnLoad = false
                mint()
                return
            }
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            guard !done, !minting, attempts < Self.maxAttempts else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.done, !self.minting else { return }
                guard BankrKeyMint.isSignedIn(cookies.map { ($0.name, $0.domain) }) else { return }
                DispatchQueue.main.async { self.startMint() }
            }
        }

        private func startMint() {
            guard let webView, !done, !minting else { return }
            if BankrKeyMint.isBankrPage(webView.url) && popup.child == nil {
                mint()
            } else {
                // Close any sign-in popup and come home, then mint.
                if let child = popup.child { popup.close(child) }
                mintOnLoad = true
                webView.load(URLRequest(url: BankrKeyMint.startURL))
            }
        }

        // MARK: The one call

        /// Asked from bankr.bot's page, in an isolated script world so the
        /// page's own `fetch` wrappers never see it. WebKit attaches the
        /// session cookie; this code never touches it.
        private func mint() {
            guard let webView, !done, !minting else { return }
            minting = true
            attempts += 1
            onMaking()
            let body = BankrKeyMint.requestBody(name: BankrKeyMint.keyName(on: Date()))
            webView.callAsyncJavaScript("""
                const r = await fetch(endpoint, {
                    method: 'POST', credentials: 'include',
                    headers: {'content-type': 'application/json'}, body: body
                });
                return {status: r.status, body: await r.text()};
                """,
                arguments: ["endpoint": BankrKeyMint.endpoint, "body": body],
                in: nil, in: .defaultClient) { [weak self] result in
                guard let self else { return }
                self.minting = false
                var status = 0
                var text = ""
                if case .success(let value) = result, let dict = value as? [String: Any] {
                    status = (dict["status"] as? NSNumber)?.intValue ?? 0
                    text = dict["body"] as? String ?? ""
                }
                let outcome = BankrKeyMint.outcome(status: status, body: text)
                if case .minted(let key) = outcome {
                    self.done = true
                    self.stopWatching()
                    self.onKey(key, self.newAccount)
                } else if outcome == .signedOut, self.attempts < Self.maxAttempts {
                    // The next tick retries; a session still being written
                    // is the usual reason.
                } else if let line = BankrKeyMint.line(for: outcome) {
                    // A key wider than asked, a refused session after its
                    // retries, or a failure: stop, and say which.
                    self.done = true
                    self.stopWatching()
                    self.onFailure(line)
                }
            }
        }

        // MARK: Popups and other apps

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               navigationAction.targetFrame?.isMainFrame ?? true,
               BankrKeyMint.isAppHandoff(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// "Continue with X/Telegram" opens a popup — `LoginPopupWindow`.
        /// Farcaster's approval is its own app's, so that one leaves.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures _: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, BankrKeyMint.isAppHandoff(url) {
                UIApplication.shared.open(url)
                return nil
            }
            return popup.open(over: webView, configuration: configuration, delegate: self)
        }

        func webViewDidClose(_ webView: WKWebView) {
            popup.close(webView)
        }
    }
}
