import SwiftUI
import WebKit

/// Acorns' sign-in, run inside our own `WKWebView` — `SpotifyLoginWebView`'s
/// pattern, and deliberately its structure rather than a fresh one, because
/// that file is the record of three shipped ways this hangs (waiting for a
/// bearer that may never come, watching `didFinish` instead of polling, and
/// having no failure state at all). All three are designed out here.
///
/// **DEBUG-only, with the seat (see `AcornsLive`).** The way in is the
/// Diagnostics sheet; there is no catalog row and no route.
///
/// **What it captures, and in which order of confidence.** Acorns' web app
/// authenticates its API calls with an `Authorization: Bearer …` header, so
/// the injected hook below is the PRIMARY credential here — the inverse of
/// Spotify, where the cookie is the credential and the bearer is a bonus. The
/// session cookies are captured as a fallback for the case the bearer is
/// minted per-request and never passes through a hook we can see. Which of
/// the two actually authenticates a read is exactly what `-acornsProbe`
/// answers, and the reason the probe reports both.
///
/// Non-persistent data store: nothing of this session is left in a shared
/// cookie jar, and what is kept goes to the device-only Keychain via
/// `AcornsAuth`, nowhere else.
struct AcornsLoginWebView: View {
    @Environment(\.dismiss) private var dismiss
    var onCaptured: () -> Void = {}

    /// Acorns' own sign-in. `oak.acorns.com` is where `app.acorns.com`
    /// redirects an unauthenticated visitor, and it carries no captcha and no
    /// bot vendor (measured 2026-09-15) — the fact this whole seat rests on.
    static let loginURL = URL(string: "https://oak.acorns.com/sign-in")!

    @State private var loading = true
    @State private var failure: String?
    @State private var reloadCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AcornsLoginWKWebView(
                    url: Self.loginURL,
                    reloadCount: reloadCount,
                    onCaptured: {
                        onCaptured()
                        dismiss()
                    },
                    onLoadingChanged: { loading = $0 },
                    onFailure: { failure = $0; loading = false })
                    .ignoresSafeArea()
                    .opacity(failure == nil ? 1 : 0)

                if let failure {
                    stateBlock {
                        Text(failure)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            self.failure = nil
                            loading = true
                            reloadCount += 1
                        }
                        .dsText(.body17).foregroundStyle(DS.tint)
                        .padding(.horizontal, DS.Space.s4)
                        .dsTapTarget(Capsule(style: .continuous))
                    }
                } else if loading {
                    stateBlock {
                        DSSpinner(size: .regular)
                        Text("Opening Acorns' sign-in…")
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .dsScreenTitle("Log in to Acorns")
            .dsSheetDismiss { dismiss() }
        }
    }

    @ViewBuilder private func stateBlock(@ViewBuilder content: () -> some View)
        -> some View {
        VStack(spacing: DS.Space.s3) { content() }
            .padding(DS.Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsPageBackground()
            .ignoresSafeArea()
    }
}

private struct AcornsLoginWKWebView: UIViewRepresentable {
    let url: URL
    let reloadCount: Int
    let onCaptured: () -> Void
    let onLoadingChanged: (Bool) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url,
                    onCaptured: onCaptured,
                    onLoadingChanged: onLoadingChanged,
                    onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let script = WKUserScript(source: Self.captureScript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "acornsTokenCapture")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.reloadIfAsked(reloadCount, in: webView)
    }

    /// The message handler retains the coordinator and the poll retains a
    /// timer — both die here, or this view leaks a running clock per sign-in.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "acornsTokenCapture")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let url: URL
        private let onCaptured: () -> Void
        private let onLoadingChanged: (Bool) -> Void
        private let onFailure: (String) -> Void

        private var captured = false
        private var pendingBearer: String?
        private var lastReloadCount = 0
        private var poll: Timer?
        private weak var webView: WKWebView?
        private var reportedFailure = false
        /// When the app shell was first seen — i.e. the sign-in took. The
        /// credential is given a grace window from that moment rather than
        /// declared missing on the first look, since the bearer arrives on the
        /// shell's own first API call, not on the navigation.
        private var signedInAt: Date?
        private static let credentialGrace: TimeInterval = 8
        /// When this view started. The ABSOLUTE bound, and it is a fix rather
        /// than a precaution: every other deadline here hangs off `signedInAt`,
        /// which is only set when a post-login navigation is RECOGNISED. If
        /// Acorns lands somewhere this code does not expect — a host or path
        /// that has never been seen from here, since the flow cannot be run
        /// without an account — nothing would ever capture and nothing would
        /// ever fail, and the view would spin forever with a Cancel button.
        /// That is precisely the third bug `SpotifyLoginWebView` records as
        /// shipped; it does not get to ship twice.
        private var startedAt = Date()
        private static let absoluteBound: TimeInterval = 60

        init(url: URL,
             onCaptured: @escaping () -> Void,
             onLoadingChanged: @escaping (Bool) -> Void,
             onFailure: @escaping (String) -> Void) {
            self.url = url
            self.onCaptured = onCaptured
            self.onLoadingChanged = onLoadingChanged
            self.onFailure = onFailure
        }

        deinit { poll?.invalidate() }

        /// Read on a clock, not on a page event — `SpotifyLoginWebView`'s one
        /// load-bearing lesson. A session that lands mid-redirect, or in a
        /// navigation this view never sees finish, is still in the jar.
        func attach(_ webView: WKWebView) {
            self.webView = webView
            guard poll == nil else { return }
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.tryExtract()
            }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        }

        func stop() {
            poll?.invalidate()
            poll = nil
        }

        func reloadIfAsked(_ count: Int, in webView: WKWebView) {
            guard count != lastReloadCount else { return }
            lastReloadCount = count
            signedInAt = nil
            startedAt = Date()          // Try again restarts the watchdog too.
            reportedFailure = false
            webView.load(URLRequest(url: url))
        }

        /// Acorns' own sign-in paths, from its bundle (`/sign-in`,
        /// `/oauth/sign-in`, `/forgot-password`, `/reset-password`). A page
        /// under any of these is still the login, not the app.
        private static let authPaths = ["/sign-in", "/oauth", "/forgot-password",
                                        "/reset-password"]

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !captured, let body = message.body as? [String: String],
                  let bearer = body["bearerToken"], !bearer.isEmpty else { return }
            pendingBearer = bearer
            tryExtract()
        }

        // MARK: - Navigation

        /// Keep the sign-in in this web view: a non-web scheme would hand the
        /// flow to the Acorns app and strand this view blank mid-login. The
        /// post-login hop to `app.acorns.com` is ALLOWED here, unlike
        /// Spotify's web-player hop — that hop is where the shell makes its
        /// first authenticated API call, which is the only moment the bearer
        /// passes through the hook.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            let scheme = target.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel)
                tryExtract()
                return
            }
            // Any Acorns page that is not part of the sign-in flow means the
            // sign-in took. Deliberately broader than `app.acorns.com`: the
            // post-login destination cannot be verified from here without an
            // account, and pinning one host is what would leave this view
            // waiting on a navigation that never comes.
            if (navigationAction.targetFrame?.isMainFrame ?? true),
               signedInAt == nil,
               target.host?.contains("acorns.") == true,
               !Self.authPaths.contains(where: { target.path.hasPrefix($0) }) {
                signedInAt = Date()
            }
            decisionHandler(.allow)
            tryExtract()
        }

        /// A `target="_blank"` popup — a "Continue with…" button is exactly
        /// this. Returning nil makes those dead taps, which reads as a freeze.
        func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures _: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let target = navigationAction.request.url {
                webView.load(URLRequest(url: target))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            self.webView = webView
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            self.webView = webView
            onLoadingChanged(false)
            tryExtract()
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            guard !captured, !isCancellation(error) else { return }
            fail(String(localized: "Couldn't reach Acorns' sign-in — check your connection and tap Try again."))
        }

        private func isCancellation(_ error: Error) -> Bool {
            let e = error as NSError
            if e.domain == NSURLErrorDomain {
                return e.code == NSURLErrorCancelled || e.code == NSURLErrorUnsupportedURL
            }
            // 102 = frame load interrupted, 101 = unsupported URL.
            return e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 101)
        }

        private func fail(_ message: String) {
            guard !captured, !reportedFailure else { return }
            reportedFailure = true
            onLoadingChanged(false)
            onFailure(message)
        }

        // MARK: - The credential

        /// The bearer is the credential Acorns' own app sends, so it is what
        /// this waits for — but not forever, and not alone: once the shell has
        /// been reached, the session cookies are taken as a fallback after the
        /// grace window rather than leaving the view spinning on a header that
        /// may never pass through a hook.
        private func tryExtract() {
            guard !captured, let view = webView else { return }
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                let acorns = cookies.filter { ($0.domain).contains("acorns.") }
                let header = acorns
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")

                let haveBearer = !(self.pendingBearer ?? "").isEmpty
                let signedInLongEnough = self.signedInAt
                    .map { Date().timeIntervalSince($0) > Self.credentialGrace } ?? false

                // A bearer ends it immediately. Cookies alone end it only once
                // the shell was actually reached AND the grace has passed —
                // otherwise a pre-login visitor cookie would "succeed".
                guard haveBearer || (signedInLongEnough && !header.isEmpty) else {
                    if signedInLongEnough, header.isEmpty {
                        self.fail(String(localized: "Acorns didn't hand back a session — tap Try again."))
                    } else if Date().timeIntervalSince(self.startedAt) > Self.absoluteBound {
                        // The watchdog: signed in or not, this view has waited
                        // long enough to say something rather than spin.
                        self.fail(String(localized: "Casberi couldn't read a session from Acorns. If you're signed in, this is the probe's problem, not yours — tap Try again."))
                    }
                    return
                }
                self.captured = true
                self.stop()
                AcornsAuth.store(bearer: self.pendingBearer,
                                 cookieHeader: header.isEmpty ? nil : header)
                DispatchQueue.main.async { self.onCaptured() }
            }
        }
    }

    /// Hooks `fetch` and `XMLHttpRequest` to read the `authorization: Bearer …`
    /// header the web app attaches to its own API calls. Reads nothing else
    /// and sends nothing anywhere — the same script `SpotifyLoginWebView`
    /// runs, pointed at this seat's message handler.
    private static let captureScript = """
    (function() {
        function post(bearer) {
            if (bearer && bearer.indexOf('Bearer ') === 0) {
                window.webkit.messageHandlers.acornsTokenCapture.postMessage({
                    bearerToken: bearer.replace('Bearer ', '')
                });
            }
        }
        function readHeaders(h) {
            if (!h) { return; }
            if (typeof Headers !== 'undefined' && h instanceof Headers) { post(h.get('authorization')); return; }
            if (Array.isArray(h)) {
                for (const pair of h) {
                    if (pair && pair.length === 2 && String(pair[0]).toLowerCase() === 'authorization') { post(pair[1]); }
                }
                return;
            }
            if (typeof h === 'object') {
                for (const k in h) { if (k.toLowerCase() === 'authorization') post(h[k]); }
            }
        }
        const origFetch = window.fetch;
        window.fetch = function() {
            try {
                const first = arguments[0];
                if (typeof Request !== 'undefined' && first instanceof Request) { readHeaders(first.headers); }
                readHeaders(arguments[1] && arguments[1].headers);
            } catch (e) {}
            return origFetch.apply(this, arguments);
        };
        const origSet = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
            try { if (header.toLowerCase() === 'authorization') post(value); } catch (e) {}
            return origSet.apply(this, arguments);
        };
    })();
    """
}
