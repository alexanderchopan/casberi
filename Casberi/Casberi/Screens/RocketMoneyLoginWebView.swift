import SwiftUI
import WebKit

/// Rocket Money's sign-in, run inside our own `WKWebView` — `AcornsLoginWebView`'s
/// structure, which is `SpotifyLoginWebView`'s, so the three shipped hangs that
/// file records (waiting on a header that may never come, watching `didFinish`
/// instead of polling, no failure state at all) stay designed out.
///
/// **It captures TWO things, and the second is what makes this seat possible.**
/// The bearer, like Acorns. And every GraphQL operation the page sends: Rocket
/// Money's schema is closed (introspection and field suggestions both off), so
/// the only honest way to learn its documents is to watch the real app use
/// them. See `RocketMoneyLive` for why that beats reconstructing them from the
/// publisher's bundle.
///
/// **A MUTATION IS NEVER RECORDED.** The hook posts every `/graphql` body it
/// sees, and `RocketMoneyOperations.record` drops anything that is not a read
/// before it reaches the store. 114 of this app's operations are mutations
/// over somebody's bank account, so the filter is in Swift, where it can be
/// audited, rather than in the injected script where a page could confuse it.
///
/// **Signing in teaches it more than signing in.** The operations are learned
/// from pages the person actually opens, so the sheet says so: visiting
/// Subscriptions and Transactions inside this view is what fills the
/// catalogue. That is a real instruction, not decoration, and the probe's
/// "not yet seen" line names exactly what is still missing.
///
/// Non-persistent data store: nothing of this session is left in a shared
/// cookie jar, and the credential goes to the device-only Keychain via
/// `RocketMoneyAuth`, nowhere else.
struct RocketMoneyLoginWebView: View {
    @Environment(\.dismiss) private var dismiss
    var onCaptured: () -> Void = {}

    static let loginURL = URL(string: "https://app.rocketmoney.com/login")!

    @State private var loading = true
    @State private var failure: String?
    @State private var reloadCount = 0
    /// How many reads the page has taught us, live — the reason to keep
    /// browsing rather than closing the sheet the moment login takes.
    @State private var learned = 0
    @State private var signedIn = false
    /// The view is opening the person's own pages to finish the connect.
    @State private var walking = false

    var body: some View {
        NavigationStack {
            ZStack {
                RocketMoneyLoginWKWebView(
                    url: Self.loginURL,
                    reloadCount: reloadCount,
                    onSignedIn: { signedIn = true },
                    onLearned: { learned = $0 },
                    onWalkChanged: { walking = $0 },
                    onWalkDone: { onCaptured(); dismiss() },
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
                        Text("Opening Rocket Money's sign-in…")
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Says what is happening, never what to do — the view is doing
                // it. Plain words for a plain fact: it is reading the account.
                if walking {
                    HStack(spacing: DS.Space.s2) {
                        DSSpinner()
                        Text("Setting up your account…")
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity)
                    .dsPageBackground()
                }
            }
            .dsScreenTitle("Log in to Rocket Money")
            .dsSheetDismiss {
                onCaptured()
                dismiss()
            }
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

private struct RocketMoneyLoginWKWebView: UIViewRepresentable {
    let url: URL
    let reloadCount: Int
    let onSignedIn: () -> Void
    let onLearned: (Int) -> Void
    let onWalkChanged: (Bool) -> Void
    let onWalkDone: () -> Void
    let onLoadingChanged: (Bool) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onSignedIn: onSignedIn, onLearned: onLearned,
                    onWalkChanged: onWalkChanged, onWalkDone: onWalkDone,
                    onLoadingChanged: onLoadingChanged, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let script = WKUserScript(source: Self.captureScript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "rocketCapture")

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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "rocketCapture")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let url: URL
        private let onSignedIn: () -> Void
        private let onLearned: (Int) -> Void
        private let onWalkChanged: (Bool) -> Void
        private let onWalkDone: () -> Void
        private let onLoadingChanged: (Bool) -> Void
        private let onFailure: (String) -> Void

        private var pendingBearer: String?
        private var lastReloadCount = 0
        private var poll: Timer?
        private weak var webView: WKWebView?
        private var reportedFailure = false
        private var announcedSignIn = false
        private var signedInAt: Date?
        private static let credentialGrace: TimeInterval = 8
        /// The ABSOLUTE bound — `AcornsLoginWebView`'s, for its reason: every
        /// other deadline hangs off `signedInAt`, which is only set when a
        /// post-login navigation is recognised, so an unrecognised landing
        /// would spin forever with no error. Longer than Acorns' because this
        /// flow is deliberately slower — the person is meant to browse.
        private var startedAt = Date()
        private static let absoluteBound: TimeInterval = 90

        /// The pages this view opens by itself once the sign-in takes, and the
        /// reason there is no button asking anybody to do it.
        ///
        /// **Nobody should have to know how this seat works** (user, on the
        /// button this replaced: "wtf is 'teach it your pages' who talks like
        /// that"). Rocket Money publishes no schema, so the seat learns its
        /// reads by watching the real app make them — which is an
        /// implementation detail, and asking a person to go click through four
        /// pages to satisfy it is that detail wearing a control. The view does
        /// the browsing. It is the person's own session doing exactly what
        /// their own hand would do, one page at a time.
        ///
        /// Routes taken from Rocket Money's own bundle, so a rename shows up
        /// as a page that teaches nothing rather than a wrong URL.
        private static let walkPaths = ["/dashboard", "/recurring",
                                        "/transactions", "/net-worth"]
        /// Long enough for a Next.js route to mount and fire its queries.
        private static let dwell: TimeInterval = 3.5
        private var walking = false
        private var walkIndex = 0

        private func startWalk() {
            guard !walking else { return }
            walking = true
            walkIndex = 0
            onWalkChanged(true)
            stepWalk()
        }

        private func stepWalk() {
            guard walking, walkIndex < Self.walkPaths.count, let view = webView else {
                finishWalk(); return
            }
            let path = Self.walkPaths[walkIndex]
            walkIndex += 1
            guard let url = URL(string: "https://app.rocketmoney.com" + path) else {
                stepWalk(); return
            }
            view.load(URLRequest(url: url))
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell) { [weak self] in
                self?.stepWalk()
            }
        }

        private func finishWalk() {
            guard walking else { return }
            walking = false
            onWalkChanged(false)
            // Everything the pages taught is already stored; the credential is
            // in hand. Nothing here needs the person, so the sheet closes
            // itself rather than leaving them on a page they never asked for.
            onWalkDone()
        }

        init(url: URL, onSignedIn: @escaping () -> Void, onLearned: @escaping (Int) -> Void,
             onWalkChanged: @escaping (Bool) -> Void, onWalkDone: @escaping () -> Void,
             onLoadingChanged: @escaping (Bool) -> Void, onFailure: @escaping (String) -> Void) {
            self.url = url
            self.onSignedIn = onSignedIn
            self.onLearned = onLearned
            self.onWalkChanged = onWalkChanged
            self.onWalkDone = onWalkDone
            self.onLoadingChanged = onLoadingChanged
            self.onFailure = onFailure
        }

        deinit { poll?.invalidate() }

        /// Read on a clock, not on a page event. Unlike the other two seats
        /// this view does NOT stop at the first credential — the catalogue
        /// fills while the person browses, so the poll runs until the sheet is
        /// closed and the credential is refreshed as it changes.
        func attach(_ webView: WKWebView) {
            self.webView = webView
            guard poll == nil else { return }
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
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

        // MARK: - What the page told us

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: String] else { return }
            if let bearer = body["bearerToken"], !bearer.isEmpty {
                pendingBearer = bearer
                tryExtract()
            }
            // The operation the page just sent. `record` is what refuses a
            // mutation — never this script, and never the page.
            if let name = body["operationName"], let query = body["query"] {
                RocketMoneyOperations.record(name: name, query: query)
                let n = RocketMoneyOperations.catalogue.count
                DispatchQueue.main.async { self.onLearned(n) }
            }
        }

        // MARK: - Navigation

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
            // Every in-app page is allowed on purpose: browsing IS the capture.
            if (navigationAction.targetFrame?.isMainFrame ?? true),
               target.host?.hasSuffix("app.rocketmoney.com") == true,
               target.path != "/login", signedInAt == nil {
                signedInAt = Date()
                // The sign-in took. Walk the pages ourselves rather than ask
                // the person to — see `walk()`.
                startWalk()
            }
            decisionHandler(.allow)
            tryExtract()
        }

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
            guard !isCancellation(error), !announcedSignIn else { return }
            fail(String(localized: "Couldn't reach Rocket Money's sign-in — check your connection and tap Try again."))
        }

        private func isCancellation(_ error: Error) -> Bool {
            let e = error as NSError
            if e.domain == NSURLErrorDomain {
                return e.code == NSURLErrorCancelled || e.code == NSURLErrorUnsupportedURL
            }
            return e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 101)
        }

        private func fail(_ message: String) {
            guard !reportedFailure else { return }
            reportedFailure = true
            onLoadingChanged(false)
            onFailure(message)
        }

        // MARK: - The credential

        /// Stores whatever is in hand and keeps going. The bearer may rotate
        /// while the person browses, so the newest one wins; cookies are taken
        /// once the app shell has been reached and the grace has passed.
        private func tryExtract() {
            guard let view = webView else { return }
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let header = cookies
                    .filter { $0.domain.contains("rocketmoney.") }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")

                let haveBearer = !(self.pendingBearer ?? "").isEmpty
                let signedInLongEnough = self.signedInAt
                    .map { Date().timeIntervalSince($0) > Self.credentialGrace } ?? false
                guard haveBearer || (signedInLongEnough && !header.isEmpty) else {
                    if !self.announcedSignIn,
                       Date().timeIntervalSince(self.startedAt) > Self.absoluteBound {
                        self.fail(String(localized: "Casberi couldn't read a session from Rocket Money. If you're signed in, this is the probe's problem, not yours — tap Try again."))
                    }
                    return
                }

                RocketMoneyAuth.store(bearer: self.pendingBearer,
                                      cookieHeader: header.isEmpty ? nil : header)
                guard !self.announcedSignIn else { return }
                self.announcedSignIn = true
                DispatchQueue.main.async { self.onSignedIn() }
            }
        }
    }

    /// Hooks `fetch` and `XMLHttpRequest` for two things: the
    /// `authorization: Bearer …` header, and the BODY of any POST to a
    /// `/graphql` path. Reads nothing else and sends nothing anywhere — the
    /// message handler is Casberi's own, and the mutation filter is in Swift.
    private static let captureScript = """
    (function() {
        function post(msg) {
            try { window.webkit.messageHandlers.rocketCapture.postMessage(msg); } catch (e) {}
        }
        function postBearer(bearer) {
            if (bearer && bearer.indexOf('Bearer ') === 0) {
                post({ bearerToken: bearer.replace('Bearer ', '') });
            }
        }
        function readHeaders(h) {
            if (!h) { return; }
            if (typeof Headers !== 'undefined' && h instanceof Headers) { postBearer(h.get('authorization')); return; }
            if (Array.isArray(h)) {
                for (const pair of h) {
                    if (pair && pair.length === 2 && String(pair[0]).toLowerCase() === 'authorization') { postBearer(pair[1]); }
                }
                return;
            }
            if (typeof h === 'object') {
                for (const k in h) { if (k.toLowerCase() === 'authorization') postBearer(h[k]); }
            }
        }
        function readBody(url, body) {
            try {
                if (!url || String(url).indexOf('/graphql') === -1) { return; }
                if (typeof body !== 'string') { return; }
                const parsed = JSON.parse(body);
                const list = Array.isArray(parsed) ? parsed : [parsed];
                for (const op of list) {
                    if (op && op.query && op.operationName) {
                        post({ operationName: String(op.operationName), query: String(op.query) });
                    }
                }
            } catch (e) {}
        }
        const origFetch = window.fetch;
        window.fetch = function() {
            try {
                const first = arguments[0];
                const opts = arguments[1];
                if (typeof Request !== 'undefined' && first instanceof Request) { readHeaders(first.headers); }
                readHeaders(opts && opts.headers);
                const url = (typeof first === 'string') ? first : (first && first.url);
                readBody(url, opts && opts.body);
            } catch (e) {}
            return origFetch.apply(this, arguments);
        };
        const origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            try { this.__rmURL = url; } catch (e) {}
            return origOpen.apply(this, arguments);
        };
        const origSet = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
            try { if (header.toLowerCase() === 'authorization') postBearer(value); } catch (e) {}
            return origSet.apply(this, arguments);
        };
        const origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function(body) {
            try { readBody(this.__rmURL, body); } catch (e) {}
            return origSend.apply(this, arguments);
        };
    })();
    """
}
