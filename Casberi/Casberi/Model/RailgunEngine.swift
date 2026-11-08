import Foundation
import UIKit
import WebKit

/// THE RAILGUN ENGINE ON THE PHONE (prd §1713; built 2026-11-07).
///
/// Railgun's open wallet SDK (`@railgun-community/wallet` 11.3.0 over engine
/// 9.9.1, MIT) with ethers and snarkjs, bundled into one module script
/// (`Resources/railgun-engine.js`, built reproducibly by
/// `tools/railgun-engine`), running in a hidden `WKWebView` — the Privacy
/// Pools engine's pattern (`PrivacyEngine`), because WebKit has WebAssembly,
/// workers and a JIT and a bare `JSContext` has none of them usably.
///
/// **Three doors, all Swift's.**
/// - The page, its script and the SDK's two wasm files come from the app
///   over `casberi-railgun://`.
/// - Every network request the SDK makes is handed to Swift (`railgunNet`)
///   by the page's `fetch`; the page's Content-Security-Policy allows no other
///   host. Swift sends it only to a host the engine's `NetworkReach` entry
///   declares, through `IngestSupport`'s one funnel, so there is a receipt
///   for each. The indexer and the screening node are asked about the whole
///   pool, never about this wallet, so nothing here names you.
/// - Every line the page says arrives on `railgunLog`.
///
/// **What it does today:** open the 0zk wallet, build the pool's two trees
/// from the current-tree checkpoint and check every root (`sync`), read the
/// balances by token with what is spendable, and prepare a shield or an
/// unshield for your account to send. It SENDS nothing. Ethereum only.
/// Nothing is persisted: the trees are rebuilt on every open (§1713 item 9,
/// open at build).
@MainActor
final class RailgunEngine: NSObject {

    static let shared = RailgunEngine()

    /// The `NetworkReach` service name: the engine's reads.
    static let service = "Railgun engine"
    static let scheme = "casberi-railgun"

    typealias Wire = RailgunEngineWire

    private var webView: WKWebView?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var isReady = false
    private(set) var isOpen = false

    /// The page's Content-Security-Policy: its own scheme for the module
    /// script and the wasm; workers and WebAssembly for snarkjs; no host.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src \(scheme): blob: 'unsafe-eval' 'wasm-unsafe-eval'",
        "worker-src blob:",
        "connect-src \(scheme):",
    ].joined(separator: "; ")

    /// One fixed identifier: the same store every launch, and only this
    /// engine's (`forget` removes it).
    static let storeID = UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000001")!
    static var store: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: storeID) }

    /// Deletes the kept trees and wallet records: the next open builds them
    /// again from the checkpoint.
    func forget() async throws {
        stop()
        // Clearing the store's data, not removing the store:
        // `WKWebsiteDataStore.remove(forIdentifier:)` never returned on the
        // simulator (measured 2026-11-07), even with no web view using it.
        await Self.store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    static var page: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        </head><body><script type="module" src="railgun-engine.js"></script></body></html>
        """
    }

    // MARK: - Starting and stopping

    /// Loads the page and the bundle; returns when the script says `ready`.
    func start() async throws {
        if isReady { return }
        if webView == nil {
            let config = WKWebViewConfiguration()
            // The engine's OWN persistent store, apart from every other web
            // view: the pool's trees live there in IndexedDB, so a launch after
            // the first resumes from the last block it read instead of
            // rebuilding them (prd §1713 item 9). What is kept is the public
            // pool and the SDK's wallet record, which it encrypts with the
            // Keychain's key; no cookie is ever set, the page reaches no host.
            config.websiteDataStore = Self.store
            config.setURLSchemeHandler(RailgunEngineScheme.shared, forURLScheme: Self.scheme)
            let controller = config.userContentController
            controller.addScriptMessageHandler(RailgunEngineNet(), contentWorld: .page, name: "railgunNet")
            controller.add(RailgunEngineLog(engine: self), name: "railgunLog")
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            #if DEBUG
            view.isInspectable = true
            #endif
            view.navigationDelegate = self
            // In the window, 1×1 and all but invisible, never in anyone's
            // way: to WebKit a web view outside the window is a background
            // page, whose timers it freezes (measured 2026-11-07: a sync
            // that never came back, `isFreezable=1` in the log), and the
            // SDK's sync runs on them.
            view.alpha = 0.01
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                window.addSubview(view)
            }
            webView = view
            view.load(URLRequest(url: URL(string: "\(Self.scheme)://engine/index.html")!))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.readyTimeout))
                guard let self, !self.isReady, self.webView === view else { return }
                self.pageFailed(Wire.Failure(name: "NotReady", message: "the engine did not load in \(Int(Self.readyTimeout)) s"))
                self.stop()
            }
        }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    static let readyTimeout: Double = 60

    /// Drops the page, its wallet and every prepared transaction with it.
    func stop() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.removeFromSuperview()
        webView = nil
        isReady = false
        isOpen = false
        for waiter in readyWaiters { waiter.resume(throwing: Wire.Failure(name: "Stopped", message: "engine stopped")) }
        readyWaiters = []
    }

    fileprivate func pageSaid(_ line: String) {
        if line == "ready" {
            isReady = true
            for waiter in readyWaiters { waiter.resume() }
            readyWaiters = []
            return
        }
        NSLog("railgunEngine| page | %@", line)
    }

    fileprivate func pageFailed(_ error: Error) {
        for waiter in readyWaiters { waiter.resume(throwing: error) }
        readyWaiters = []
    }

    // MARK: - Calls

    func call<Params: Encodable, Value: Decodable>(_ method: Wire.Method, _ params: Params,
                                                  as type: Value.Type) async throws -> Value {
        try await start()
        guard let webView else { throw Wire.Failure(name: "Stopped", message: "engine stopped") }
        let reply = try await webView.callAsyncJavaScript(
            "return await casberiRailgun.call(method, params)",
            arguments: ["method": method.rawValue, "params": try Wire.encode(params)],
            in: nil, contentWorld: .page)
        guard let json = reply as? String else {
            throw Wire.Failure(name: "BadReply", message: "not a string")
        }
        return try Wire.decode(type, from: json)
    }

    func info() async throws -> Wire.Info {
        try await call(.info, Wire.Empty(), as: Wire.Info.self)
    }

    /// Opens the 0zk wallet on Ethereum through the account's node. Without
    /// a mnemonic the page makes a random wallet and keeps nothing.
    func open(mnemonic: String? = nil, encryptionKey: String? = nil, walletID: String? = nil,
              creationBlock: Int? = nil, persist: Bool = true) async throws -> Wire.Opened {
        let opened = try await call(.open, Wire.Open(mnemonic: mnemonic, encryptionKey: encryptionKey, walletID: walletID,
                                                      rpcUrl: PrivacyNetwork.ethereum.rpcUrl, creationBlock: creationBlock,
                                                      persist: persist),
                                    as: Wire.Opened.self)
        isOpen = true
        return opened
    }

    /// Builds the trees, scans the wallet and checks every root. Spend from
    /// it only when `Wire.trusted` says so.
    func sync(capMs: Int = 600_000) async throws -> Wire.Synced {
        try await call(.sync, Wire.Sync(capMs: capMs), as: Wire.Synced.self)
    }

    func balances() async throws -> [Wire.Balance] {
        try await call(.balances, Wire.Empty(), as: Wire.Balances.self).balances
    }

    /// A shield of `amount` (0x-hex base units) of `token` into the wallet,
    /// for your account to send: the proxy call and its approval.
    func prepareShield(token: String, amount: String) async throws -> Wire.PreparedShield {
        try await call(.prepareShield, Wire.Shield(token: token, amount: amount), as: Wire.PreparedShield.self)
    }

    /// An unshield to `to`, proved, for your account to send.
    func prepareUnshield(token: String, amount: String, to: String, forSafe: Bool = true,
                         maxFeePerGas: String? = nil, maxPriorityFeePerGas: String? = nil) async throws -> Wire.PreparedUnshield {
        try await call(.prepareUnshield, Wire.Unshield(token: token, amount: amount, to: to, forSafe: forSafe,
                                                        maxFeePerGas: maxFeePerGas, maxPriorityFeePerGas: maxPriorityFeePerGas),
                       as: Wire.PreparedUnshield.self)
    }

    func close() async {
        _ = try? await call(.close, Wire.Empty(), as: Wire.Empty.self)
        isOpen = false
    }

    /// The hosts the engine may reach: its `NetworkReach` entry's.
    static var declaredHosts: [String] {
        NetworkReach.endpoint(forService: service)?.hosts ?? []
    }
}

// MARK: - The page's process

extension RailgunEngine: WKNavigationDelegate {
    /// iOS ends a web-content process that grows too large or that it
    /// reclaims in the background. The wallet and the trees went with it:
    /// drop the page, so the next call loads a fresh one and the caller opens
    /// the wallet again.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            NSLog("railgunEngine| page | the web-content process ended; the engine will reload")
            stop()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { pageFailed(error); stop() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { pageFailed(error); stop() }
    }
}

// MARK: - The page's log

private final class RailgunEngineLog: NSObject, WKScriptMessageHandler {
    weak var engine: RailgunEngine?
    init(engine: RailgunEngine) { self.engine = engine }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        MainActor.assumeIsolated { engine?.pageSaid(line) }
    }
}

// MARK: - The network door

/// Every request the SDK makes arrives here as `{url, method, headers,
/// body}`. A host the engine does not declare is refused; the rest go
/// through `IngestSupport`'s funnel and come back as `{status, type,
/// body64}` — base64, because the proving files are binary.
private final class RailgunEngineNet: NSObject, WKScriptMessageHandlerWithReply {

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let raw = body["url"] as? String, let url = URL(string: raw) else {
            replyHandler(nil, "malformed request")
            return
        }
        let declared = MainActor.assumeIsolated { RailgunEngine.declaredHosts }
        guard RailgunEngineWire.allows(url, declared: declared) else {
            NSLog("railgunEngine| refused | %@", url.host ?? raw)
            replyHandler(nil, "host not declared: \(url.host ?? "?")")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) ?? "GET"
        for (field, value) in (body["headers"] as? [String: String]) ?? [:]
        where field.lowercased() != "host" && field.lowercased() != "content-length" {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let text = body["body"] as? String, request.httpMethod != "GET" { request.httpBody = Data(text.utf8) }
        // A proving file is tens of megabytes from an IPFS gateway.
        request.timeoutInterval = 120
        #if DEBUG
        let rpcMethods = PrivacyEngineWire.rpcMethods(body["body"] as? String)
        let what = rpcMethods.isEmpty ? url.path : rpcMethods.joined(separator: ",")
        let tor: Bool = if case .tor = TorRoute.way(for: request, service: RailgunEngine.service) { true } else { false }
        let began = Date()
        NSLog("railgunEngine| net > | %@ | %@%@", url.host ?? "?", String(what.prefix(80)), tor ? " | tor" : "")
        #endif
        Task { @MainActor in
            let answer = await Self.send(request)
            #if DEBUG
            NSLog("railgunEngine| net < | %@ | %@ | %d ms | %@", url.host ?? "?", String(what.prefix(80)),
                  Int(Date().timeIntervalSince(began) * 1000),
                  answer.map { "\($0.1.statusCode) \($0.0.count) B" } ?? "no answer")
            #endif
            guard let (data, http) = answer else {
                replyHandler(nil, "no answer from \(url.host ?? "?")")
                return
            }
            replyHandler(["status": http.statusCode,
                          "type": http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
                          "body64": data.base64EncodedString()], nil)
        }
    }

    /// One request through the funnel. A connection the phone dropped
    /// mid-download (the indexer's big answers, measured on an iPhone over
    /// Wi-Fi) is asked again, a few times, before it is an outage.
    @MainActor
    private static func send(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        for attempt in 0..<4 {
            if let answer = await IngestSupport.sendRequest(request, service: RailgunEngine.service) {
                let text = String(decoding: answer.0.prefix(512), as: UTF8.self)
                if PrivacyEngineWire.throttled(status: answer.1.statusCode, body: text), attempt < 3 {
                    try? await Task.sleep(for: .milliseconds(500 << attempt))
                    continue
                }
                return answer
            }
            NSLog("railgunEngine| no answer | %@ | try %d", request.url?.host ?? "?", attempt + 1)
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
        return nil
    }
}

// MARK: - The app's scheme: the page, the bundle, the wasm

final class RailgunEngineScheme: NSObject, WKURLSchemeHandler {
    static let shared = RailgunEngineScheme()

    /// The SDK's two wasm modules, loaded by name beside the script.
    static let wasm: Set<String> = ["poseidon_hash_wasm_bg", "curve25519_scalarmult_wasm_bg"]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let name = task.request.url?.lastPathComponent ?? ""
        switch name {
        case "index.html":
            answer(task, Data(RailgunEngine.page.utf8), type: "text/html")
        case "railgun-engine.js":
            guard let data = resource("railgun-engine", "js") else { fail(task, 404, "no bundle"); return }
            answer(task, data, type: "text/javascript")
        case let file where file.hasSuffix(".wasm") && Self.wasm.contains(String(file.dropLast(5))):
            guard let data = resource(String(file.dropLast(5)), "wasm") else { fail(task, 404, "no wasm"); return }
            answer(task, data, type: "application/wasm")
        default:
            fail(task, 404, "not the engine's")
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func resource(_ name: String, _ ext: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? Data(contentsOf: $0) }
    }

    private func answer(_ task: any WKURLSchemeTask, _ data: Data, type: String) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": type,
                  "Content-Length": String(data.count),
                  "Content-Security-Policy": RailgunEngine.contentSecurityPolicy,
                  "Cache-Control": "no-store",
              ]) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask, _ status: Int, _ why: String) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/plain"]) else { return }
        task.didReceive(response)
        task.didReceive(Data(why.utf8))
        task.didFinish()
    }
}
