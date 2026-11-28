import Foundation
import UIKit
import WebKit
import CryptoKit

/// THE TACIT ENGINE ON THE PHONE: YOUR TACIT ACCOUNT, READ-ONLY.
///
/// Tacit's own standalone private-ETH wallet (github.com/z0r0z/tacit, MIT),
/// pinned by hash and bundled into one script (`Resources/tacit-engine.js`,
/// built reproducibly by `tools/tacit-engine`), running in a hidden
/// `WKWebView`, on the Privacy Pools engine's pattern (`PrivacyEngine`).
///
/// **View-only.** The wallet is opened with no provider, so it has nothing to
/// send with: it derives your Tacit address and receive address from one
/// 32-byte key, finds your notes in the pool's own history and adds them up.
/// It proves nothing and sends nothing; making money private, sending and
/// taking out are not built.
///
/// **Two doors, both Swift's.**
/// - The page and its script come from the app over `casberi-tacit://`.
/// - Every network request the wallet makes is handed to Swift (`engineNet`)
///   by the page's `fetch` (src/net.js); the page's Content-Security-Policy
///   allows no other host. Swift sends it only to a host the engine's
///   `NetworkReach` entry declares, through `IngestSupport`'s one funnel: Tor
///   on iOS, and a receipt for each.
///
/// Nothing is persisted: the key and the notes live in the page, and go when
/// it does.
@MainActor
final class TacitEngine: NSObject {

    static let shared = TacitEngine()

    /// The `NetworkReach` service the engine's reads are filed under.
    static let service = "Tacit engine"
    static let scheme = "casberi-tacit"

    typealias Wire = TacitEngineWire

    private var webView: WKWebView?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var isReady = false
    private(set) var isOpen = false

    /// The page's Content-Security-Policy: its own scheme for script and
    /// data, and no host at all.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src \(scheme): 'wasm-unsafe-eval'",
        "connect-src \(scheme):",
    ].joined(separator: "; ")

    static var page: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        </head><body><script src="tacit-engine.js"></script></body></html>
        """
    }

    // MARK: - Starting and stopping

    /// Loads the page and the bundle; returns when the script says `ready`.
    func start() async throws {
        if isReady { return }
        if webView == nil {
            let config = WKWebViewConfiguration()
            // Nothing the page does is kept on disk: no cookies, no storage.
            config.websiteDataStore = .nonPersistent()
            config.setURLSchemeHandler(TacitEngineScheme.shared, forURLScheme: Self.scheme)
            let controller = config.userContentController
            controller.addScriptMessageHandler(TacitEngineNet(), contentWorld: .page, name: "engineNet")
            controller.addScriptMessageHandler(TacitEngineLogs(), contentWorld: .page, name: "engineLogs")
            controller.add(TacitEngineLog(engine: self), name: "engineLog")
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            #if DEBUG
            view.isInspectable = true
            #endif
            view.navigationDelegate = self
            // **IN THE WINDOW (2026-11-27, on the phone: "it is reading the
            // fee … and is taking a while").** Outside the window WebKit
            // treats the page as a background one and freezes its timers, as
            // Railgun's sync and Privacy Pools' proof measured; likely why a
            // send's proof stood past two minutes (§1994). 1×1, all but
            // invisible, in no one's way.
            view.alpha = 0.01
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                window.addSubview(view)
            }
            webView = view
            view.load(URLRequest(url: URL(string: "\(Self.scheme)://engine/index.html")!))
            // A page that never says `ready` fails its waiters instead of
            // holding them forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.readyTimeout))
                guard let self, !self.isReady, self.webView === view else { return }
                self.pageFailed(Wire.Failure(name: "NotReady", message: "the engine did not load in \(Int(Self.readyTimeout)) s"))
                self.stop()
            }
        }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    static let readyTimeout: Double = 30

    /// Drops the page, and the key and notes with it.
    func stop() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.removeFromSuperview()
        webView = nil
        isReady = false
        let wasOpen = isOpen
        isOpen = false
        if wasOpen { TacitAccount.shared.engineStopped() }
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
        NSLog("tacitEngine| page | %@", line)
    }

    fileprivate func pageFailed(_ error: Error) {
        for waiter in readyWaiters { waiter.resume(throwing: error) }
        readyWaiters = []
    }

    // MARK: - Calls

    private func call<Params: Encodable, Value: Decodable>(_ method: Wire.Method, _ params: Params,
                                                          as type: Value.Type) async throws -> Value {
        try await start()
        guard let webView else { throw Wire.Failure(name: "Stopped", message: "engine stopped") }
        let reply = try await webView.callAsyncJavaScript(
            "return await casberiEngine.call(method, params)",
            arguments: ["method": method.rawValue, "params": try PrivacyEngineWire.encode(params)],
            in: nil, contentWorld: .page)
        guard let json = reply as? String else {
            throw Wire.Failure(name: "BadReply", message: "not a string")
        }
        return try PrivacyEngineWire.decode(type, from: json)
    }

    func info() async throws -> Wire.Info {
        try await call(.info, Wire.Empty(), as: Wire.Info.self)
    }

    /// Opens the account `key` makes on `networks`: the keys are derived
    /// inside the page. The key is not kept by this object.
    func open(key: [UInt8], networks: [TacitNetwork] = TacitNetwork.all) async throws -> Wire.Opened {
        guard key.count == 32 else { throw Wire.Failure(name: "BadKey", message: "the key must be 32 bytes") }
        let request = Wire.Open(key: "0x" + key.map { String(format: "%02x", $0) }.joined(), networks: networks)
        let opened = try await call(.open, request, as: Wire.Opened.self)
        isOpen = true
        return opened
    }

    /// Your notes on one network, found in the pool's own history.
    func read(chainId: Int) async throws -> Wire.Reading {
        try await call(.read, Wire.Read(chainId: chainId), as: Wire.Reading.self)
    }

    /// Your private TAC on the Tacit chain: the chain's notes tried with the
    /// open account's key. About ten seconds on a Mac for 3,200 notes.
    func chain(from: Int = 0, known: [Wire.KeptNote] = []) async throws -> Wire.ChainReading {
        try await call(.chain, Wire.Chain(rpcUrl: TacitNetwork.ethereum.rpcUrl, blocks: TacitChain.blocks,
                                          leader: TacitChain.leader, from: from, known: known),
                       as: Wire.ChainReading.self)
    }

    /// Your private TAC in Tacit's DeFi pool. About 20 to 40 seconds.
    func defi() async throws -> Wire.DefiReading {
        try await call(.defi, Wire.Empty(), as: Wire.DefiReading.self)
    }

    /// Tacit's farms: rates' inputs, read for anyone, no key (prd §1993).
    func farms() async throws -> Wire.Farms {
        try await call(.farms, Wire.Empty(), as: Wire.Farms.self)
    }

    /// The open account's farm positions, found with its key.
    func farmed() async throws -> Wire.Farmed {
        try await call(.farmed, Wire.Empty(), as: Wire.Farmed.self)
    }

    // MARK: - Making TAC private

    private func shieldAsk(_ units: UInt64) -> Wire.ShieldAsk {
        Wire.ShieldAsk(rpcUrl: TacitNetwork.ethereum.rpcUrl, blocks: TacitChain.blocks, leader: TacitChain.leader,
                       units: "0x" + String(units, radix: 16))
    }

    func shieldQuote(units: UInt64) async throws -> Wire.ShieldQuote {
        try await call(.shieldQuote, shieldAsk(units), as: Wire.ShieldQuote.self)
    }

    func shieldProve(units: UInt64) async throws -> Wire.ShieldProved {
        try await call(.shieldProve, shieldAsk(units), as: Wire.ShieldProved.self)
    }

    func shieldHand(_ permit: Wire.ShieldHand) async throws -> Wire.ShieldHanded {
        try await call(.shieldHand, permit, as: Wire.ShieldHanded.self)
    }

    func shieldOffer() async throws -> Wire.ShieldHanded {
        try await call(.shieldOffer, Wire.Empty(), as: Wire.ShieldHanded.self)
    }

    // MARK: Back to public (prd §1977)

    private func outAsk(to: String, units: UInt64) -> Wire.OutAsk {
        Wire.OutAsk(rpcUrl: TacitNetwork.ethereum.rpcUrl, blocks: TacitChain.blocks, leader: TacitChain.leader,
                    to: to, units: "0x" + String(units, radix: 16))
    }

    func outQuote(units: UInt64) async throws -> Wire.OutQuote {
        try await call(.outQuote, outAsk(to: "", units: units), as: Wire.OutQuote.self)
    }

    func outProve(to: String, units: UInt64) async throws -> Wire.OutProved {
        try await call(.outProve, outAsk(to: to, units: units), as: Wire.OutProved.self)
    }

    /// Answers once the leader has queued it: its id, as a shield's.
    func outHand() async throws -> Wire.ShieldHanded {
        try await call(.outHand, Wire.Empty(), as: Wire.ShieldHanded.self)
    }

    // MARK: Send privately (prd §1982)

    func payQuote(units: UInt64) async throws -> Wire.OutQuote {
        try await call(.payQuote, outAsk(to: "", units: units), as: Wire.OutQuote.self)
    }

    func payProve(to: String, units: UInt64) async throws -> Wire.OutProved {
        try await call(.payProve, outAsk(to: to, units: units), as: Wire.OutProved.self)
    }

    /// Throws when `to` names no Tacit account the chain can pay.
    func payCheck(to: String) async throws {
        _ = try await call(.payCheck, outAsk(to: to, units: 0), as: Wire.Empty.self)
    }

    func owed(_ address: String) async throws -> Wire.Owed {
        try await call(.owed, Wire.OwedAsk(rpcUrl: TacitNetwork.ethereum.rpcUrl, blocks: TacitChain.blocks,
                                           leader: TacitChain.leader, address: address), as: Wire.Owed.self)
    }

    func shieldStatus(id: String) async throws -> Wire.ShieldStatus {
        try await call(.shieldStatus, Wire.ShieldStatusAsk(leader: TacitChain.leader, id: id), as: Wire.ShieldStatus.self)
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

extension TacitEngine: WKNavigationDelegate {
    /// iOS may end a web-content process it reclaims in the background. The
    /// key and notes went with it: drop the page, so the next call loads a
    /// fresh one and the caller opens the account again.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            NSLog("tacitEngine| page | the web-content process ended; the engine will reload")
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

private final class TacitEngineLog: NSObject, WKScriptMessageHandler {
    weak var engine: TacitEngine?
    init(engine: TacitEngine) { self.engine = engine }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        MainActor.assumeIsolated { engine?.pageSaid(line) }
    }
}

// MARK: - The network door

/// Every request the wallet makes arrives here as `{url, method, headers,
/// body}`. A host the engine does not declare is refused; the rest go through
/// `IngestSupport`'s funnel and come back as `{status, headers, body64}`.
/// Tacit's pool logs, kept between launches (user, 2026-11-25: Make private
/// took two minutes, most of it the DeFi read fetching every pool log again
/// because the engine's page keeps nothing). Public chain logs only, one file
/// per query in Caches, never backed up; Tacit's library checks them against
/// the chain's trees before it trusts them, and deletes a set that fails.
final class TacitEngineLogs: NSObject, WKScriptMessageHandlerWithReply {

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TacitPoolLogs", isDirectory: true)
    }

    static func file(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name + ".json")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let text = message.body as? String, let data = text.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = body["op"] as? String, let key = body["key"] as? String else {
            replyHandler(nil, "malformed")
            return
        }
        let value = body["value"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        Task.detached(priority: .utility) {
            let url = Self.file(key)
            var reply: String?
            switch op {
            case "get":
                reply = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
            case "put":
                if let value {
                    try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                    try? value.write(to: url, options: .atomic)
                    var keep = url
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? keep.setResourceValues(values)
                }
            case "del":
                try? FileManager.default.removeItem(at: url)
            default: break
            }
            await replyHandler(reply, nil)
        }
    }
}

private final class TacitEngineNet: NSObject, WKScriptMessageHandlerWithReply {

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let raw = body["url"] as? String, let url = URL(string: raw) else {
            replyHandler(nil, "malformed request")
            return
        }
        let declared = MainActor.assumeIsolated { TacitEngine.declaredHosts }
        guard PrivacyEngineWire.allows(url, declared: declared) else {
            NSLog("tacitEngine| refused | %@", url.host ?? raw)
            replyHandler(nil, "host not declared: \(url.host ?? "?")")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) ?? "GET"
        for (field, value) in (body["headers"] as? [String: String]) ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let text = body["body"] as? String { request.httpBody = Data(text.utf8) }
        request.timeoutInterval = 60
        Task { @MainActor in
            guard let (data, http) = await Self.send(request) else {
                replyHandler(nil, "no answer from \(url.host ?? "?")")
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            replyHandler(["status": http.statusCode, "headers": headers,
                          "body64": data.base64EncodedString()], nil)
        }
    }

    /// One request through the funnel; a free node's 429 is waited out, a few
    /// times, before it is an answer.
    @MainActor
    private static func send(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        for attempt in 0..<5 {
            guard let (data, http) = await IngestSupport.sendRequest(request, service: TacitEngine.service) else {
                NSLog("tacitEngine| no answer | %@", request.url?.host ?? "?")
                return nil
            }
            let text = String(decoding: data.prefix(2048), as: UTF8.self)
            if PrivacyEngineWire.throttled(status: http.statusCode, body: text), attempt < 4 {
                try? await Task.sleep(for: .milliseconds(500 << attempt))
                continue
            }
            return (data, http)
        }
        return nil
    }
}

// MARK: - The app's scheme: the page and the bundle

final class TacitEngineScheme: NSObject, WKURLSchemeHandler {
    static let shared = TacitEngineScheme()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        switch path {
        case "index.html":
            answer(task, 200, Data(TacitEngine.page.utf8), type: "text/html")
        // Tacit's prover's own files (`tools/tacit-engine/build.mjs`): read by
        // the page, never by the network.
        case "btc-pool/btc_pool_halo2_bg.wasm", "btc-pool/params-k13.bin", "btc-pool/vk.bin":
            let name = ["btc-pool/btc_pool_halo2_bg.wasm": ("tacit-halo2", "wasm"),
                        "btc-pool/params-k13.bin": ("tacit-halo2-params", "bin"),
                        "btc-pool/vk.bin": ("tacit-halo2-vk", "bin")][path]!
            guard let url = Bundle.main.url(forResource: name.0, withExtension: name.1),
                  let data = try? Data(contentsOf: url) else {
                answer(task, 404, Data("no prover".utf8), type: "text/plain")
                return
            }
            answer(task, 200, data, type: name.1 == "wasm" ? "application/wasm" : "application/octet-stream")
        case "tacit-engine.js":
            guard let url = Bundle.main.url(forResource: "tacit-engine", withExtension: "js"),
                  let data = try? Data(contentsOf: url) else {
                answer(task, 404, Data("no bundle".utf8), type: "text/plain")
                return
            }
            answer(task, 200, data, type: "text/javascript")
        default:
            answer(task, 404, Data("not served".utf8), type: "text/plain")
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func answer(_ task: any WKURLSchemeTask, _ status: Int, _ data: Data, type: String) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": type,
                  "Content-Length": String(data.count),
                  "Content-Security-Policy": TacitEngine.contentSecurityPolicy,
                  "Cache-Control": "no-store",
              ]) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
