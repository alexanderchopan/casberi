import SwiftUI
import WebKit

/// Spotify's sign-in, run inside our own `WKWebView` — the crux of the seat.
/// The person logs in on Spotify's real page; we read the `sp_dc` session
/// cookie out of the web view's cookie store, and (when the web player hands us
/// one on the way past) the bearer token it sends. `sp_dc` alone is the
/// credential: `SpotifyAuth.refreshWebPlayerToken` mints a bearer from it the
/// way `open.spotify.com` does, with no developer app and no per-user allowlist
/// — the gate that killed the first seat is never touched.
///
/// Ported from stephancill/stupid-social (App-Store-approved). Deliberate
/// exception to §653's "a setup door opens the shared Safari sheet": that sheet
/// gives no cookie access, and the cookie IS the credential here — so this seat
/// must run its own web view. Non-persistent data store: nothing of this
/// session is left in a shared cookie jar; the one cookie we keep goes to the
/// device-only Keychain via `SpotifyAuth`, nowhere else.
///
/// **Three shipped ways this hung, all fixed here (2026-09-12, user: "Spotify
/// connects and logged me in the Spotify app successfully, but doesn't register
/// a signed in in Casberi. It just keeps spinning or has a white screen").**
/// 1. It waited for the BEARER as well as the cookie, and the bearer only ever
///    arrives if the web player's own `fetch` passes a literal headers object.
///    A sign-in that ended anywhere else — the native app, a `Request` object,
///    a service worker — left a perfect `sp_dc` sitting in the jar with nobody
///    reading it, forever. The cookie is the credential; the bearer is a bonus.
/// 2. It only looked on `didFinish`. The post-login hop is a redirect to
///    `open.spotify.com`, which iOS may hand to the SPOTIFY APP as a universal
///    link — so `didFinish` never comes and the view is left blank. It POLLS
///    the cookie store now, so the session lands whether or not this web view
///    ever paints another page.
/// 3. There was no failure or loading state at all: a cancelled navigation, an
///    unsupported scheme, a dropped connection all rendered as a white screen
///    with a Cancel button. Every one of them says something now.
struct SpotifyLoginWebView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with the harvested credential once the session cookie is in hand.
    var onCredentials: (SpotifyAuth.Credentials) -> Void

    /// Spotify's own login page. The `continue` target is the web player, which
    /// is where a real sign-in lands — we never let that page load (see
    /// `Coordinator.decidePolicyFor`), but asking for it is what makes Spotify
    /// treat this as a web-player login and mint the session we came for.
    static let loginURL = URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F%3Fnd%3D1")!

    @State private var loading = true
    @State private var failure: String?
    /// Bumped to re-load the web view after a failure, without rebuilding it.
    @State private var reloadCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                SpotifyLoginWKWebView(
                    url: Self.loginURL,
                    reloadCount: reloadCount,
                    onCredentialsFound: { creds in
                        onCredentials(creds)
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
                    }
                } else if loading {
                    stateBlock {
                        ProgressView()
                        Text("Opening Spotify's sign-in…")
                            .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .navigationTitle("Log in to Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// The cover over the web view while it has nothing to show. Opaque on the
    /// page background, because the thing it replaces is the white screen.
    @ViewBuilder private func stateBlock(@ViewBuilder content: () -> some View)
        -> some View {
        VStack(spacing: DS.Space.s3) { content() }
            .padding(DS.Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsPageBackground()
            .ignoresSafeArea()
    }
}

private struct SpotifyLoginWKWebView: UIViewRepresentable {
    let url: URL
    let reloadCount: Int
    let onCredentialsFound: (SpotifyAuth.Credentials) -> Void
    let onLoadingChanged: (Bool) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url,
                    onCredentialsFound: onCredentialsFound,
                    onLoadingChanged: onLoadingChanged,
                    onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // A private jar: this login never touches a shared cookie store, and
        // the credential we keep is copied out explicitly to the Keychain.
        config.websiteDataStore = .nonPersistent()

        let script = WKUserScript(source: Self.captureScript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "spotifyTokenCapture")

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

    /// The message handler retains the coordinator, and the poll retains a
    /// timer — both die here, or this view leaks a running clock per sign-in.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "spotifyTokenCapture")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let url: URL
        private let onCredentialsFound: (SpotifyAuth.Credentials) -> Void
        private let onLoadingChanged: (Bool) -> Void
        private let onFailure: (String) -> Void

        private var captured = false
        private var pendingBearer: String?
        private var lastReloadCount = 0
        private var poll: Timer?
        private weak var webView: WKWebView?
        /// When the web-player hop was refused. The session is normally in the
        /// jar before that hop is even asked for, but the cookie is written by
        /// a response we don't get to observe — so it is given a grace window
        /// rather than declared missing on the first look.
        private var refusedPlayerAt: Date?
        private var reportedFailure = false
        private static let sessionGrace: TimeInterval = 4

        init(url: URL,
             onCredentialsFound: @escaping (SpotifyAuth.Credentials) -> Void,
             onLoadingChanged: @escaping (Bool) -> Void,
             onFailure: @escaping (String) -> Void) {
            self.url = url
            self.onCredentialsFound = onCredentialsFound
            self.onLoadingChanged = onLoadingChanged
            self.onFailure = onFailure
        }

        deinit { poll?.invalidate() }

        /// The whole reason this seat stopped hanging: the cookie store is read
        /// on a clock, not on a page event. `sp_dc` is written by the login
        /// response itself, so it is in the jar the instant the sign-in takes —
        /// no matter where the navigation goes next, or whether it goes
        /// anywhere at all.
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
            refusedPlayerAt = nil
            reportedFailure = false
            webView.load(URLRequest(url: url))
        }

        // The injected script posts the bearer token if the web player sends
        // one on any fetch/XHR. A bonus, never a requirement — see the type
        // doc: waiting for this is what hung the seat.
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !captured, let body = message.body as? [String: String],
                  let bearer = body["bearerToken"], !bearer.isEmpty else { return }
            pendingBearer = bearer
            tryExtract()
        }

        // MARK: - Navigation

        /// Two jobs. **Keep the sign-in in this web view**: a `spotify:` (or any
        /// non-web) scheme is cancelled rather than handed to the system, which
        /// would open the Spotify app and strand this view blank mid-login.
        /// **Never load the web player**: the `continue` hop to
        /// `open.spotify.com` is the exact navigation iOS may route to the
        /// installed app as a universal link, and it is also a heavy page that
        /// paints white for seconds — by the time it is asked for, the cookie
        /// we came for is already in the jar, so we stop there and read it.
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
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame, target.host?.hasSuffix("open.spotify.com") == true {
                decisionHandler(.cancel)
                onLoadingChanged(true)
                // This view has no further use for the web player: the session
                // is either already in the jar or a few hundred ms behind, and
                // the poll is watching for it.
                if refusedPlayerAt == nil { refusedPlayerAt = Date() }
                tryExtract()
                return
            }
            decisionHandler(.allow)
            // A redirect hop is also a moment the cookie may have just landed.
            tryExtract()
        }

        /// A `target="_blank"` popup — Spotify's "Continue with Google/Apple"
        /// buttons are exactly this. Returning nil (the default) makes them
        /// dead taps, which reads as the app being frozen.
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

        /// A cancelled navigation is our own `decidePolicyFor` doing its job —
        /// never an error to show. Anything else gets said out loud rather than
        /// rendered as a blank page.
        private func report(_ error: Error) {
            guard !captured, !isCancellation(error) else { return }
            fail(String(localized: "Couldn't reach Spotify's sign-in — check your connection and tap Try again."))
        }

        /// A navigation this view cancelled on purpose, in either of the two
        /// domains WebKit reports one in. Never an error to show — the whole
        /// point of `decidePolicyFor` here is to cancel things.
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

        /// `sp_dc` is the credential: long-lived, and the one `SpotifyAuth`
        /// mints every later bearer from. A bearer we happened to catch rides
        /// along; its absence is not a reason to wait, because the first read
        /// refreshes from `sp_dc` anyway (`accessToken()`).
        private func tryExtract() {
            guard !captured, let view = webView else { return }
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                let spDC = cookies.first(where: { $0.name == "sp_dc" })?.value ?? ""
                guard !spDC.isEmpty else {
                    // Signed in, web player refused, and still no session after
                    // the grace window: say so rather than spin forever, which
                    // is the bug this whole file was rewritten for.
                    if let since = self.refusedPlayerAt,
                       Date().timeIntervalSince(since) > Self.sessionGrace {
                        self.fail(String(localized: "Spotify didn't hand back a session — tap Try again."))
                    }
                    return
                }
                self.captured = true
                self.stop()
                let creds = SpotifyAuth.Credentials(
                    bearerToken: self.pendingBearer ?? "",
                    spDC: spDC,
                    spT: cookies.first(where: { $0.name == "sp_t" })?.value,
                    spKey: cookies.first(where: { $0.name == "sp_key" })?.value,
                    accessTokenExpiresAt: nil,
                    username: nil)
                DispatchQueue.main.async { self.onCredentialsFound(creds) }
            }
        }
    }

    /// Hooks `fetch` and `XMLHttpRequest` to read the `authorization: Bearer …`
    /// header the web player attaches to its own API calls, and posts it back
    /// to the coordinator. Reads nothing else and sends nothing anywhere.
    /// Best-effort by design — the cookie, not this, is what the seat runs on.
    private static let captureScript = """
    (function() {
        function post(bearer) {
            if (bearer && bearer.indexOf('Bearer ') === 0) {
                window.webkit.messageHandlers.spotifyTokenCapture.postMessage({
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
                // fetch(Request) carries its headers on the Request itself —
                // the form the old hook read straight past.
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
