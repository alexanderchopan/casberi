import SwiftUI
import WebKit

/// Spotify's sign-in, run inside our own `WKWebView` — the crux of the seat.
/// The person logs in on Spotify's real page; we watch the web player's own
/// network calls for the bearer token it sends, and read the `sp_dc` session
/// cookie out of the web view's cookie store. Those two together let
/// `SpotifyAuth` read the web player's endpoints as the person, with no
/// developer app and no per-user allowlist — the gate that killed the first
/// seat is never touched.
///
/// Ported from stephancill/stupid-social (App-Store-approved). Deliberate
/// exception to §653's "a setup door opens the shared Safari sheet": that sheet
/// gives no cookie access, and the cookie IS the credential here — so this seat
/// must run its own web view. Non-persistent data store: nothing of this
/// session is left in a shared cookie jar; the one cookie we keep goes to the
/// device-only Keychain via `SpotifyAuth`, nowhere else.
struct SpotifyLoginWebView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with the harvested credential once both halves are in hand.
    var onCredentials: (SpotifyAuth.Credentials) -> Void

    var body: some View {
        NavigationStack {
            SpotifyLoginWKWebView(
                url: URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F%3Fnd%3D1")!,
                onCredentialsFound: { creds in
                    onCredentials(creds)
                    dismiss()
                }
            )
            .ignoresSafeArea()
            .navigationTitle("Log in to Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SpotifyLoginWKWebView: UIViewRepresentable {
    let url: URL
    let onCredentialsFound: (SpotifyAuth.Credentials) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCredentialsFound: onCredentialsFound)
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
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onCredentialsFound: (SpotifyAuth.Credentials) -> Void
        private var captured = false
        private var pendingBearer: String?
        private weak var webView: WKWebView?

        init(onCredentialsFound: @escaping (SpotifyAuth.Credentials) -> Void) {
            self.onCredentialsFound = onCredentialsFound
        }

        // The injected script posts the bearer token the moment the web player
        // sends it on any fetch/XHR.
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !captured, let body = message.body as? [String: String],
                  let bearer = body["bearerToken"], !bearer.isEmpty else { return }
            pendingBearer = bearer
            tryExtract()
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            self.webView = webView
            tryExtract()
        }

        /// Both halves must be present: the bearer token (from the script) AND
        /// the `sp_dc`/`sp_t` session cookies (from the store). `sp_dc` is the
        /// long-lived one `SpotifyAuth` refreshes from; without it there's no
        /// durable session, so we wait rather than store a half-credential.
        private func tryExtract() {
            guard !captured, let bearer = pendingBearer, let view = webView else { return }
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                let spDC = cookies.first(where: { $0.name == "sp_dc" })?.value ?? ""
                guard !spDC.isEmpty else { return }
                self.captured = true
                let creds = SpotifyAuth.Credentials(
                    bearerToken: bearer,
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
    private static let captureScript = """
    (function() {
        function post(bearer) {
            if (bearer && bearer.indexOf('Bearer ') === 0) {
                window.webkit.messageHandlers.spotifyTokenCapture.postMessage({
                    bearerToken: bearer.replace('Bearer ', '')
                });
            }
        }
        const origFetch = window.fetch;
        window.fetch = function() {
            try {
                const h = arguments[1] && arguments[1].headers;
                if (h instanceof Headers) { post(h.get('authorization')); }
                else if (h && typeof h === 'object') {
                    for (const k in h) { if (k.toLowerCase() === 'authorization') post(h[k]); }
                }
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
