import Foundation
import UIKit
import WebKit

/// YOUR AZTEC ACCOUNT'S ENGINE (prd §1700).
///
/// Aztec's own wallet (`EmbeddedWallet`, a PXE on this device) on Aztec
/// mainnet, bundled from `tools/aztec-engine` into a hidden `WKWebView` that no
/// app page can load: the page comes from `AztecEngineServer` on loopback, its
/// proofs from Aztec's native prover (`AztecProver`), its network only through
/// the app (`AztecEngineServer`'s `/net`, the hosts declared below). The
/// account's keys derive from `AztecRoot` inside the page. Proved first in
/// `tools/aztec-dapp-spike` (simulator and iPhone, 2026-11-04).
///
/// Casberi's own reads go through `call`; Aztec apps in Casberi's browser
/// reach the same wallet through Aztec's wallet-sdk handler in the page, and
/// every connect and transaction of theirs asks the person first.
@MainActor
final class AztecEngine: NSObject {

    static let shared = AztecEngine()

    /// `NetworkReach` service names: the account's node, and the proving
    /// parameters Aztec's prover downloads once.
    static let service = "Your Aztec account"
    static let parametersService = "Aztec proving parameters"

    /// The `NetworkReach` service a page request belongs to, or nil when the
    /// engine is not declared to reach its host (it is then refused).
    nonisolated static func service(for url: URL) -> String? {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return nil }
        for name in [service, parametersService] {
            let hosts = NetworkReach.endpoint(forService: name)?.hosts ?? []
            if hosts.contains(where: { host == $0.lowercased() || host.hasSuffix("." + $0.lowercased()) }) { return name }
        }
        return nil
    }

    private var server: AztecEngineServer?
    private var webView: WKWebView?
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var calls: [Int: CheckedContinuation<Any?, Error>] = [:]
    private var nextCall = 0

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Starting

    /// Serves the page and loads it; returns once the page says it is ready.
    func start() async throws {
        if isReady { return }
        if webView == nil {
            let server = try AztecEngineServer()
            self.server = server
            let listening: Bool = await withCheckedContinuation { done in
                server.start { ok in done.resume(returning: ok) }
            }
            guard listening else { throw Failure(message: "the engine's port is taken") }
            let config = WKWebViewConfiguration()
            let controller = config.userContentController
            let relay = AztecEngineMessages(engine: self)
            for name in Self.messages { controller.add(relay, name: name) }
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            #if DEBUG
            view.isInspectable = true
            #endif
            view.navigationDelegate = self
            view.isHidden = true
            webView = view
            attachToWindow(view)
            view.load(URLRequest(url: URL(string: AztecEngineServer.origin + "/")!))
        }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    /// WebKit throttles a web view that is in no window, and the wallet's
    /// storage worker then never answers (measured 2026-11-04: the PXE stalled
    /// at "Creating … SQLite-OPFS data store" until the view joined a window).
    /// So the engine's view rides the app's window, hidden; it is re-attached
    /// whenever the engine is asked for something and has lost its window.
    private func attachToWindow(_ view: WKWebView) {
        guard view.window == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first
        window?.addSubview(view)
        if window == nil { NSLog("aztecEngine| page | no window to ride yet") }
    }

    static let messages = ["engineReady", "engineLog", "engineNeedsRoot", "engineReply",
                           "engineToTab", "engineConnect", "engineApprove", "engineEmoji"]

    // MARK: - Casberi's own calls

    /// One of the engine's own calls (`account`, `chain`); the wallet starts on
    /// the first (a PXE, a few seconds).
    func call(_ method: String, _ args: [Any] = []) async throws -> Any? {
        try await start()
        guard let webView else { throw Failure(message: "the engine stopped") }
        attachToWindow(webView)
        nextCall += 1
        let id = nextCall
        let argsJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: args)) ?? Data("[]".utf8), as: UTF8.self)
        return try await withCheckedThrowingContinuation { done in
            calls[id] = done
            webView.callAsyncJavaScript("casberiEngine.call(id, method, argsJSON)",
                                        arguments: ["id": id, "method": method, "argsJSON": argsJSON],
                                        in: nil, in: .page) { _ in }
        }
    }

    /// The account's address.
    func accountAddress() async throws -> String {
        guard let answer = try await call("account") as? [String: Any], let address = answer["address"] as? String else {
            throw Failure(message: "no account")
        }
        return address
    }

    // MARK: - The page's messages

    fileprivate func received(_ name: String, _ body: [String: Any]) {
        switch name {
        case "engineReady":
            isReady = true
            for waiter in readyWaiters { waiter.resume() }
            readyWaiters = []
        case "engineNeedsRoot":
            guard let root = AztecRoot.ensure() else {
                NSLog("aztecEngine| root | unavailable")
                return
            }
            NSLog("aztecEngine| root | %@", root.made ? "made" : "found")
            let hex = root.bytes.map { String(format: "%02x", $0) }.joined()
            webView?.callAsyncJavaScript("casberiEngine.setRoot(hex)", arguments: ["hex": hex], in: nil, in: .page) { _ in }
        case "engineReply":
            guard let id = body["id"] as? Int, let done = calls.removeValue(forKey: id) else { return }
            if let error = body["error"] as? String { done.resume(throwing: Failure(message: error)) } else { done.resume(returning: body["result"]) }
        case "engineLog":
            let event = body["event"] as? String ?? "?"
            // A library's console line carries `text`; the engine's own events `detail`.
            let detail = (body["text"] as? String)
                ?? (body["detail"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
                    .map { String(decoding: $0, as: UTF8.self) } ?? ""
            NSLog("aztecEngine| %@ | %@", event, String(detail.prefix(600)))
        default:
            // The app-facing half (engineToTab, engineConnect, engineApprove,
            // engineEmoji) is the browser's, wired with it (prd §1700 step 3).
            NSLog("aztecEngine| %@ | not wired yet", name)
        }
    }

    fileprivate func pageFailed(_ message: String) {
        NSLog("aztecEngine| page | %@", message)
        isReady = false
        for waiter in readyWaiters { waiter.resume(throwing: Failure(message: message)) }
        readyWaiters = []
        for (_, done) in calls { done.resume(throwing: Failure(message: message)) }
        calls = [:]
        webView = nil
        server?.stop()
        server = nil
    }
}

extension AztecEngine: WKNavigationDelegate {
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { pageFailed("the engine's process ended") }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { pageFailed(error.localizedDescription) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { pageFailed(error.localizedDescription) }
    }
}

/// The page's messages, held weakly so the content controller does not keep
/// the engine alive.
private final class AztecEngineMessages: NSObject, WKScriptMessageHandler {
    weak var engine: AztecEngine?
    init(engine: AztecEngine) { self.engine = engine }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "127.0.0.1",
              message.frameInfo.securityOrigin.port == Int(AztecEngineServer.port) else { return }
        let text = message.body as? String ?? ""
        let body = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        MainActor.assumeIsolated { engine?.received(message.name, body) }
    }
}
