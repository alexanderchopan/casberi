#if DEBUG
import SwiftUI
import WebKit

/// The capture itself (prd §777) — a `WKWebView` that signs into one named
/// provider and records what its own web app then asks for. DEBUG only: it is
/// a measuring instrument, not a seat. It has no catalogue offer, it lands
/// nothing in the corpus, it stores no credential, and its jar is
/// non-persistent, so a capture leaves nothing behind.
///
/// Everything it may report is bounded by `WebSessionCapture`: hosts outside
/// the target's own are never recorded, a URL keeps its path and its query
/// NAMES, a response is sketched as its shape, and an `Authorization` header
/// is reported as its scheme. The subject is a person's money, so that is a
/// property of the code rather than a rule somebody follows.
struct WebSessionCaptureView: View {
    let target: WebSessionCapture.Target
    /// Called with the report once the capture is closed: the calls, and
    /// the target's cookie NAMES read from the jar at that moment.
    var onReport: ([WebSessionCapture.Call], [String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var calls: [WebSessionCapture.Call] = []
    @State private var jar = CaptureJar()

    var body: some View {
        NavigationStack {
            CaptureWebView(target: target, jar: jar, onCall: { calls.append($0) })
                .ignoresSafeArea()
                .dsScreenTitle(String(localized: "Measuring \(target.name)"))
                .dsSheetDismiss {
                    let captured = calls
                    jar.cookieNames { cookies in
                        onReport(captured, WebSessionCapture.cookieReport(cookies, in: target))
                        dismiss()
                    }
                }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

/// The one handle on the page's jar the close needs. Weak, so the sheet
/// never keeps a web view alive past its own dismissal.
final class CaptureJar {
    weak var webView: WKWebView?

    /// Names, domains and the `HttpOnly` flag — `HTTPCookie.value` is never
    /// read here.
    func cookieNames(_ done: @escaping ([WebSessionCapture.CookieName]) -> Void) {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else {
            done([]); return
        }
        store.getAllCookies { cookies in
            done(cookies.map {
                WebSessionCapture.CookieName(name: $0.name, domain: $0.domain, httpOnly: $0.isHTTPOnly)
            })
        }
    }
}

private struct CaptureWebView: UIViewRepresentable {
    let target: WebSessionCapture.Target
    let jar: CaptureJar
    let onCall: (WebSessionCapture.Call) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(target: target, onCall: onCall) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // NON-PERSISTENT. A measurement must not leave a money provider's
        // session sitting in the shared jar, and nothing here keeps one.
        config.websiteDataStore = .nonPersistent()
        // A landing page's autoplay video otherwise takes the whole screen in
        // the system player, and the capture reads as a black sheet.
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(
            WKUserScript(source: Self.captureScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false))
        config.userContentController.add(context.coordinator, name: "casberiCapture")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = DuolingoFeed.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        webView.load(URLRequest(url: URL(string: target.signInURL)!))
        jar.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "casberiCapture")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let target: WebSessionCapture.Target
        private let onCall: (WebSessionCapture.Call) -> Void

        init(target: WebSessionCapture.Target,
             onCall: @escaping (WebSessionCapture.Call) -> Void) {
            self.target = target
            self.onCall = onCall
        }

        /// A provider's "continue with Google/Apple" button is a popup, and
        /// with no UI delegate it is a dead tap that reads as a frozen app.
        func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures _: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        /// The page reports one call. Everything below is a filter before a
        /// record: a host outside the target's own is DROPPED rather than
        /// redacted, and nothing but the fields `Call` names is kept.
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let raw = body["url"] as? String,
                  let url = URL(string: raw),
                  WebSessionCapture.records(host: url.host, in: target) else { return }
            let call = WebSessionCapture.Call(
                method: (body["method"] as? String)?.uppercased() ?? "GET",
                url: WebSessionCapture.redactedURL(raw),
                status: (body["status"] as? Int) ?? 0,
                authScheme: WebSessionCapture.authScheme(body["auth"] as? String),
                shape: (body["body"] as? String).flatMap { text in
                    (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
                        .map { WebSessionCapture.shape($0) }
                },
                headerNames: WebSessionCapture.headerNames(body["headers"] as? [String] ?? []),
                credentials: (body["credentials"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                sentShape: (body["sent"] as? String).flatMap { text in
                    (try? JSONSerialization.jsonObject(with: Data(text.utf8)))
                        .map { WebSessionCapture.shape($0) }
                })
            DispatchQueue.main.async { self.onCall(call) }
        }
    }

    /// Hooks `fetch` and `XMLHttpRequest` and posts back the method, the URL,
    /// the status, the `authorization` header's SCHEME and the response body.
    /// The body is posted in full and sketched natively — the sketch is what
    /// is kept; the text is read once, inside the app, and never stored.
    ///
    /// A response body is cloned before it is read: reading the real one would
    /// consume the stream the page itself is about to parse, and the dashboard
    /// under measurement would break in front of the person measuring it.
    private static let captureScript = """
    (function() {
        var MAX = 200000;
        function post(method, url, status, auth, body, extra) {
            try {
                extra = extra || {};
                window.webkit.messageHandlers.casberiCapture.postMessage({
                    method: method || 'GET', url: String(url), status: status || 0,
                    auth: auth || '', body: (body || '').slice(0, MAX),
                    headers: extra.headers || [], credentials: extra.credentials || '',
                    sent: (typeof extra.sent === 'string') ? extra.sent.slice(0, MAX) : ''
                });
            } catch (e) {}
        }
        // Header NAMES only. The values stay in the page.
        function headerNames(h) {
            var out = [];
            try {
                if (!h) { return out; }
                if (typeof Headers !== 'undefined' && h instanceof Headers) {
                    h.forEach(function(_, k) { out.push(k); }); return out;
                }
                if (Array.isArray(h)) {
                    for (var i = 0; i < h.length; i++) { if (h[i]) { out.push(String(h[i][0])); } }
                    return out;
                }
                for (var k in h) { out.push(k); }
            } catch (e) {}
            return out;
        }
        function headerValue(h, name) {
            try {
                if (!h) { return ''; }
                if (typeof Headers !== 'undefined' && h instanceof Headers) { return h.get(name) || ''; }
                if (Array.isArray(h)) {
                    for (var i = 0; i < h.length; i++) {
                        if (h[i] && String(h[i][0]).toLowerCase() === name) { return h[i][1]; }
                    }
                    return '';
                }
                for (var k in h) { if (k.toLowerCase() === name) { return h[k]; } }
            } catch (e) {}
            return '';
        }
        var origFetch = window.fetch;
        window.fetch = function() {
            var args = arguments;
            var first = args[0];
            var url = (typeof Request !== 'undefined' && first instanceof Request) ? first.url : String(first);
            var method = (args[1] && args[1].method)
                || ((typeof Request !== 'undefined' && first instanceof Request) ? first.method : 'GET');
            var auth = headerValue(args[1] && args[1].headers, 'authorization')
                || ((typeof Request !== 'undefined' && first instanceof Request)
                    ? headerValue(first.headers, 'authorization') : '');
            var isRequest = (typeof Request !== 'undefined' && first instanceof Request);
            var extra = {
                headers: headerNames(args[1] && args[1].headers)
                    .concat(isRequest ? headerNames(first.headers) : []),
                credentials: (args[1] && args[1].credentials) || (isRequest ? first.credentials : ''),
                sent: args[1] && args[1].body
            };
            return origFetch.apply(this, args).then(function(response) {
                try {
                    response.clone().text().then(function(text) {
                        post(method, url, response.status, auth, text, extra);
                    }).catch(function() { post(method, url, response.status, auth, '', extra); });
                } catch (e) { post(method, url, response.status, auth, '', extra); }
                return response;
            });
        };
        var origOpen = XMLHttpRequest.prototype.open;
        var origSend = XMLHttpRequest.prototype.send;
        var origSet = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__cbMethod = method; this.__cbURL = url;
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
            (this.__cbHeaders = this.__cbHeaders || []).push(String(header));
            if (String(header).toLowerCase() === 'authorization') { this.__cbAuth = value; }
            return origSet.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function(sentBody) {
            var xhr = this;
            xhr.addEventListener('load', function() {
                var text = '';
                try { if (xhr.responseType === '' || xhr.responseType === 'text') { text = xhr.responseText; } } catch (e) {}
                post(xhr.__cbMethod, xhr.__cbURL, xhr.status, xhr.__cbAuth, text, {
                    headers: xhr.__cbHeaders || [],
                    credentials: xhr.withCredentials ? 'include' : '',
                    sent: sentBody
                });
            });
            return origSend.apply(this, arguments);
        };
    })();
    """
}
#endif
