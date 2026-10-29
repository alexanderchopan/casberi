import SwiftUI
import WebKit

/// Deposit's proof, its capture (prd §1607): the payment app's own sign-in in
/// our web view, the one request Peer's template names caught as the page
/// makes it, and the session sealed to Peer's proven enclave key. DEBUG only
/// (`-peerCapture cashapp`) until Deposit ships; nothing is sent to the
/// enclave's verify call and nothing is signed.
///
/// `RocketMoneyLoginWebView`'s shape: a non-persistent data store, so the
/// session never reaches a shared cookie jar; a script at document start
/// that wraps `fetch` and `XMLHttpRequest` and posts only requests matching
/// the template; the decision about what was caught made in Swift
/// (`PeerCapture`), where it can be checked, not in the page. The user agent
/// is the template's own (Peer's SDK loads Cash App as desktop Safari).
///
/// What is caught is a credential: held in memory until sealed, then
/// dropped. The log names what was present, never a value.
struct PeerCaptureSheet: View {
    @Bindable var model: PeerCaptureModel
    var close: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PeerCaptureWebView(model: model)
                    .ignoresSafeArea()
                if model.loading {
                    VStack(spacing: DS.Space.s3) {
                        DSSpinner(size: .regular)
                        Text("Opening \(model.appName)'s sign-in…")
                            .dsText(.body17).foregroundStyle(DS.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dsPageBackground()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(model.status)
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity)
                    .dsPageBackground()
            }
            .dsScreenTitle("Sign in to \(model.appName)")
            .dsSheetDismiss { close() }
        }
    }

    /// Show the sheet over whatever is on screen.
    @MainActor
    static func present(_ model: PeerCaptureModel) {
        var dismiss: () -> Void = {}
        let host = UIHostingController(rootView: PeerCaptureSheet(model: model, close: { dismiss() }))
        host.view.backgroundColor = .systemBackground
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(host, animated: true)
        dismiss = { [weak host] in host?.dismiss(animated: true) }
    }
}

@MainActor @Observable
final class PeerCaptureModel {
    let template: PeerCapture.Template
    let appName: String
    var loading = true
    var status: String
    /// The sealed session and the params a verify call would take; held for
    /// the next step, never written anywhere.
    @ObservationIgnored private(set) var sealed: String?
    @ObservationIgnored private(set) var payments: [PeerCapture.Payment] = []
    @ObservationIgnored private var handled = false
    @ObservationIgnored let log: (String) -> Void

    init(template: PeerCapture.Template, appName: String, log: @escaping (String) -> Void) {
        self.template = template
        self.appName = appName
        self.log = log
        status = "Casberi reads your recent \(appName) payments to find the one you made."
    }

    /// The page made the template's request: build the session, check it
    /// holds what the enclave needs, read the payments, seal it.
    func caught(headers: [String: String], body: String?, response: String?,
                cookies: [(name: String, value: String)], userAgent: String) {
        guard !handled else { return }
        handled = true
        let session = PeerCapture.session(headers: headers, body: body, cookies: cookies, userAgent: userAgent)
        let missing = PeerCapture.missing(session, platform: template.platform)
        log("caught headers=\(session.keys.filter { $0 != "body" }.sorted().joined(separator: ",")) body=\(session["body"] != nil) cookies=\(cookies.count) missing=\(missing.isEmpty ? "-" : missing.joined(separator: ","))")
        let json = response.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        payments = json.map { PeerCapture.payments(template, in: $0) } ?? []
        let withParams = json.map { j in payments.indices.filter { PeerCapture.params(template, in: j, index: $0) != nil }.count } ?? 0
        let first = payments.first
        log("payments rows=\(payments.count) withParams=\(withParams) firstHas=recipient:\(first?.recipient != nil),amount:\(first?.amount != nil),date:\(first?.date != nil),id:\(first?.paymentId != nil),state:\(first?.state != nil)")
        guard missing.isEmpty else {
            status = "\(appName) answered without what Peer needs (\(missing.joined(separator: ", ")))."
            return
        }
        status = "Found \(payments.count) payments. Sealing them for Peer…"
        Task {
            do {
                let key = try await PeerAttestation.fetch()
                sealed = try PeerSessionEnvelope.seal(platform: template.platform, actionType: template.actionType,
                                                      session: session, to: key)
                status = "Found \(payments.count) payments, sealed so only Peer's enclave can read them."
                log("sealed chars=\(sealed?.count ?? 0)")
            } catch {
                status = "Found \(payments.count) payments; Peer's enclave could not be reached."
                log("seal refused \(error)")
            }
        }
    }
}

private struct PeerCaptureWebView: UIViewRepresentable {
    let model: PeerCaptureModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let script = WKUserScript(source: Self.captureScript(pattern: model.template.urlPattern),
                                  injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "peerCapture")
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = model.template.userAgent
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.load(URLRequest(url: model.template.authLink))
        return web
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator _: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "peerCapture")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: PeerCaptureModel
        weak var web: WKWebView?
        init(model: PeerCaptureModel) { self.model = model }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            Task { @MainActor in model.loading = false }
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            Task { @MainActor in model.loading = false }
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            Task { @MainActor in model.loading = false }
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let m = message.body as? [String: Any],
                  let url = m["url"] as? String, let method = m["method"] as? String,
                  PeerCapture.isTarget(model.template, method: method, url: url),
                  (m["status"] as? Int).map({ (200..<300).contains($0) }) ?? false,
                  let headers = m["headers"] as? [String: String],
                  let store = web?.configuration.websiteDataStore.httpCookieStore,
                  let host = URL(string: url)?.host()
            else { return }
            let body = m["body"] as? String, response = m["response"] as? String
            let userAgent = web?.customUserAgent ?? ""
            store.getAllCookies { all in
                let cookies = all.filter { c in
                    let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                    return host == domain || host.hasSuffix("." + domain)
                }.map { (name: $0.name, value: $0.value) }
                Task { @MainActor in
                    self.model.caught(headers: headers, body: body, response: response,
                                      cookies: cookies, userAgent: userAgent)
                }
            }
        }
    }

    /// Wraps `fetch` and `XMLHttpRequest` and posts a request only when its
    /// URL matches the template's pattern: its method, URL, headers, body,
    /// status and answer. Swift decides again (`PeerCapture.isTarget`).
    static func captureScript(pattern: String) -> String {
        let quoted = (try? JSONSerialization.data(withJSONObject: [pattern], options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"$^\"]"
        return """
        (function() {
            var TARGET = new RegExp('^(?:' + \(quoted)[0] + ')$');
            function post(m) { try { window.webkit.messageHandlers.peerCapture.postMessage(m); } catch (e) {} }
            function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return String(u); } }
            function headersOf(h) {
                var out = {};
                try {
                    if (!h) return out;
                    if (typeof Headers !== 'undefined' && h instanceof Headers) { h.forEach(function(v, k) { out[k] = v; }); return out; }
                    if (Array.isArray(h)) { h.forEach(function(p) { if (p && p.length === 2) out[String(p[0])] = String(p[1]); }); return out; }
                    for (var k in h) out[k] = String(h[k]);
                } catch (e) {}
                return out;
            }
            var nativeFetch = window.fetch;
            window.fetch = function(input, init) {
                var url = abs(input && input.url ? input.url : input);
                if (!TARGET.test(url)) return nativeFetch.apply(this, arguments);
                init = init || {};
                var method = String(init.method || (input && input.method) || 'GET').toUpperCase();
                var headers = headersOf(input && input.headers);
                var extra = headersOf(init.headers);
                for (var k in extra) headers[k] = extra[k];
                headers['User-Agent'] = navigator.userAgent;
                var body = typeof init.body === 'string' ? init.body : null;
                return nativeFetch.apply(this, arguments).then(function(res) {
                    res.clone().text().then(function(t) {
                        post({ url: url, method: method, headers: headers, body: body, status: res.status, response: t });
                    }).catch(function() {});
                    return res;
                });
            };
            var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send,
                setHeader = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.open = function(m, u) {
                this.__peer = { method: String(m).toUpperCase(), url: abs(u), headers: {} };
                return open.apply(this, arguments);
            };
            XMLHttpRequest.prototype.setRequestHeader = function(k, v) {
                if (this.__peer) this.__peer.headers[k] = String(v);
                return setHeader.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function(body) {
                var meta = this.__peer;
                if (meta && TARGET.test(meta.url)) {
                    meta.headers['User-Agent'] = navigator.userAgent;
                    meta.body = typeof body === 'string' ? body : null;
                    this.addEventListener('load', function() {
                        var t = (this.responseType === '' || this.responseType === 'text') ? this.responseText : null;
                        post({ url: meta.url, method: meta.method, headers: meta.headers, body: meta.body, status: this.status, response: t });
                    });
                }
                return send.apply(this, arguments);
            };
        })();
        """
    }
}
