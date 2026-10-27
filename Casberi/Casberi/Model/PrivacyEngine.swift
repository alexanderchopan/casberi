import Foundation
import WebKit

/// THE PRIVACY POOLS ENGINE ON THE PHONE (prd §1540, §1541; built 2026-10-26).
///
/// 0xBow's open TypeScript SDK (`@0xbow/privacy-pools-v2-sdk`, MIT) with
/// snarkjs and viem, bundled into one script (`Resources/privacy-engine.js`,
/// built reproducibly by `tools/privacy-pools-engine`), running in a hidden
/// `WKWebView`. WebKit is the host because it has WebAssembly, workers and a
/// JIT; a bare `JSContext` has none of them usably, and snarkjs needs all
/// three. The closed Rust alpha is not used (§1540 item 4).
///
/// **Three doors, all Swift's.**
/// - The page and its script come from the app over `casberi-engine://`.
/// - Circuit files come over the same scheme from `PrivacyArtifactStore`,
///   which refuses any byte that does not hash to its pin.
/// - Every network request the SDK makes is handed to Swift (`engineNet`) by
///   the page's `fetch` (src/net.js); the page's Content-Security-Policy
///   allows no other host. Swift sends it only to a host the engine's
///   `NetworkReach` entries declare, through `IngestSupport`'s one funnel —
///   so Tor for whatever names a wallet (prd §1495), and a receipt for each.
///
/// **What it does today:** derive the keys from the seed in
/// `PrivacyPoolsKey`, read whether the keystore is registered, prepare the
/// registration and a deposit (with its proof), find your notes and the
/// private balance, and prepare a private transfer or a withdrawal to an
/// address (with their proofs). It SENDS nothing: a prepared transaction is
/// for your account to send (on Ethereum, prd §1563: Face ID; on Sepolia,
/// the DEBUG test sender). Sepolia and Ethereum only (`PrivacyNetwork.check`).
/// Nothing is persisted: notes live in the page.
@MainActor
final class PrivacyEngine: NSObject {

    static let shared = PrivacyEngine()

    /// `NetworkReach` service names: the engine's reads, and its circuits.
    static let service = "Privacy Pools engine"
    static let circuitsService = "Privacy Pools circuits"
    static let scheme = "casberi-engine"

    typealias Wire = PrivacyEngineWire

    private var webView: WKWebView?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var isReady = false
    private(set) var network: PrivacyNetwork?

    /// The page's Content-Security-Policy: its own scheme for script, data
    /// and circuits; workers and WebAssembly for snarkjs; no host at all.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src \(scheme): blob: 'unsafe-eval' 'wasm-unsafe-eval'",
        "worker-src blob:",
        "connect-src \(scheme):",
    ].joined(separator: "; ")

    static var page: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        </head><body><script src="privacy-engine.js"></script></body></html>
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
            config.setURLSchemeHandler(PrivacyEngineScheme.shared, forURLScheme: Self.scheme)
            let controller = config.userContentController
            controller.addScriptMessageHandler(PrivacyEngineNet(), contentWorld: .page, name: "engineNet")
            controller.add(PrivacyEngineLog(engine: self), name: "engineLog")
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            #if DEBUG
            view.isInspectable = true
            #endif
            view.navigationDelegate = self
            webView = view
            view.load(URLRequest(url: URL(string: "\(Self.scheme)://engine/index.html")!))
            // A page that never says `ready` (a script that threw while
            // loading) fails its waiters instead of holding them forever.
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

    /// Drops the page, its keys and every prepared transaction with it.
    func stop() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        isReady = false
        network = nil
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
        NSLog("privacyEngine| page | %@", line)
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
            "return await casberiEngine.call(method, params)",
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

    /// Opens your private account on `network`: derives the protocol keys
    /// from `seed` inside the page. The seed is not kept by this object.
    func open(seed: Data, owner: String, network: PrivacyNetwork = .sepolia,
              revocableKeyIndex: Int = 0) async throws -> Wire.Opened {
        try network.check()
        let request = Wire.Open(seed: "0x" + seed.map { String(format: "%02x", $0) }.joined(),
                                revocableKeyIndex: "0x" + String(revocableKeyIndex, radix: 16),
                                owner: owner, network: network)
        let opened = try await call(.open, request, as: Wire.Opened.self)
        self.network = network
        return opened
    }

    func close() async {
        _ = try? await call(.close, Wire.Empty(), as: Wire.Empty.self)
        network = nil
    }

    func isRegistered() async throws -> Wire.Registered {
        try await call(.isRegistered, Wire.Empty(), as: Wire.Registered.self)
    }

    /// The keystore registration's transactions, for your account to send.
    func prepareRegister() async throws -> Wire.Registration {
        try await call(.prepareRegister, Wire.Empty(), as: Wire.Registration.self)
    }

    /// A deposit (and its proof) of `value` (0x-hex base units) of `tokenId`.
    func prepareDeposit(tokenId: String, value: String) async throws -> Wire.PreparedDeposit {
        try await call(.prepareDeposit, Wire.Deposit(tokenId: tokenId, value: value), as: Wire.PreparedDeposit.self)
    }

    /// Your notes and the private balance per token.
    func discover() async throws -> Wire.Discovered {
        try await call(.discover, Wire.Empty(), as: Wire.Discovered.self)
    }

    /// A private transfer to `recipient` through the relayer, proof included.
    func prepareTransfer(tokenId: String, amount: String, to recipient: String) async throws -> Wire.PreparedSpend {
        try await call(.prepareTransfer, Wire.Spend(tokenId: tokenId, amount: amount, recipient: recipient),
                       as: Wire.PreparedSpend.self)
    }

    /// A withdrawal to any address through the relayer, proof included.
    func prepareWithdraw(tokenId: String, amount: String, to recipient: String) async throws -> Wire.PreparedSpend {
        try await call(.prepareWithdraw, Wire.Spend(tokenId: tokenId, amount: amount, recipient: recipient),
                       as: Wire.PreparedSpend.self)
    }

    /// Hands a prepared spend to the relayer, which posts it and pays its
    /// gas (prd §1554); the handle is spent either way.
    func relay(handle: String) async throws -> Wire.Relayed {
        try await call(.relay, Wire.Handle(handle: handle), as: Wire.Relayed.self)
    }

    /// Take it back (prd §1561): a ragequit of one whole note to the account's
    /// owner, proof included, for the owner to sign. `discover` first.
    func prepareRagequit(commitment: String) async throws -> Wire.PreparedRagequit {
        try await call(.prepareRagequit, Wire.Ragequit(commitment: commitment), as: Wire.PreparedRagequit.self)
    }

    /// Into a yield pool (prd §1563): a deposit of at most `budget` (0x-hex
    /// base units, fees included) of `tokenId` (ETH or USDC), proved, for
    /// your account to send. Nothing is sent here.
    func prepareYieldDeposit(tokenId: String, budget: String) async throws -> Wire.PreparedYieldDeposit {
        try await call(.prepareYieldDeposit, Wire.YieldDeposit(tokenId: tokenId, budget: budget), as: Wire.PreparedYieldDeposit.self)
    }

    /// One proof on `circuit` with this network's real keys and synthetic
    /// inputs: what a proof costs on this phone, with no funds and no send.
    /// Poseidon(label), decimal: the id 0xBow's ASP files a deposit under.
    func labelHash(_ label: String) async throws -> String {
        try await call(.labelHash, Wire.Label(label: label), as: Wire.LabelHash.self).labelHash
    }

    func bench(circuit: String, singleThread: Bool = false) async throws -> Wire.Benched {
        try await call(.bench, Wire.Bench(circuit: circuit, singleThread: singleThread), as: Wire.Benched.self)
    }

    /// The circuits the page reads belong to the network that is open (or
    /// Sepolia's before one is).
    var pins: [String: PrivacyArtifacts.Circuit] {
        PrivacyArtifacts.pins(chainId: (network ?? .sepolia).chainId) ?? [:]
    }

    /// The hosts the engine may reach: its `NetworkReach` entry's.
    static var declaredHosts: [String] {
        NetworkReach.endpoint(forService: service)?.hosts ?? []
    }
}

// MARK: - The page's process

extension PrivacyEngine: WKNavigationDelegate {
    /// iOS ends a web-content process that grows too large (a proof is the
    /// engine's peak, ~455 MB measured for transact_2x2) or that it reclaims
    /// in the background. Its keys and notes went with it: drop the page, so
    /// the next call loads a fresh one and the caller opens the account again.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            NSLog("privacyEngine| page | the web-content process ended; the engine will reload")
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

private final class PrivacyEngineLog: NSObject, WKScriptMessageHandler {
    weak var engine: PrivacyEngine?
    init(engine: PrivacyEngine) { self.engine = engine }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        MainActor.assumeIsolated { engine?.pageSaid(line) }
    }
}

// MARK: - The network door

/// Every request the SDK makes arrives here as `{url, method, headers,
/// body}`. A host the engine does not declare is refused; the rest go
/// through `IngestSupport`'s funnel and come back as `{status, headers, body}`.
private final class PrivacyEngineNet: NSObject, WKScriptMessageHandlerWithReply {

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let raw = body["url"] as? String, let url = URL(string: raw) else {
            replyHandler(nil, "malformed request")
            return
        }
        let declared = MainActor.assumeIsolated { PrivacyEngine.declaredHosts }
        guard PrivacyEngineWire.allows(url, declared: declared) else {
            NSLog("privacyEngine| refused | %@", url.host ?? raw)
            replyHandler(nil, "host not declared: \(url.host ?? "?")")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) ?? "GET"
        for (field, value) in (body["headers"] as? [String: String]) ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let text = body["body"] as? String
        if let text { request.httpBody = Data(text.utf8) }
        request.timeoutInterval = 60
        // Old logs from the node that keeps them (prd §1554); the rest, and a
        // range past its head, from the network's own node.
        let network = MainActor.assumeIsolated { PrivacyEngine.shared.network ?? .sepolia }
        let routed = network.logsUrl.map { PrivacyEngineWire.routed(url, body: text, rpcUrl: network.rpcUrl, logsUrl: $0) } ?? url
        Task { @MainActor in
            guard let (data, http) = await Self.send(request, to: routed, fallback: url, relayerUrl: network.relayerUrl) else {
                replyHandler(nil, "no answer from \(url.host ?? "?")")
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            replyHandler(["status": http.statusCode, "headers": headers,
                                "body": String(decoding: data, as: UTF8.self)], nil)
        }
    }

    /// One request through the funnel, to `url` (a routed log read) and back
    /// to `fallback` when that node has not reached the head yet; a free
    /// node's 429 is waited out, a few times, before it is an answer.
    @MainActor
    private static func send(_ request: URLRequest, to url: URL, fallback: URL, relayerUrl: String) async -> (Data, HTTPURLResponse)? {
        var request = request
        request.url = url
        var unanswered = 0
        for attempt in 0..<6 {
            guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.service) else {
                // The relayer's front end refuses some Tor exits, and a quote
                // or a relay that dies there is the whole move (measured
                // 2026-10-26: two of two failed on one circuit). Its
                // requests get two more circuits before they are an outage;
                // they never leave Tor (prd §1554).
                unanswered += 1
                let relayer = url.host?.lowercased() == URL(string: relayerUrl)?.host?.lowercased()
                NSLog("privacyEngine| no answer | %@ | try %d", url.host ?? "?", unanswered)
                if relayer, unanswered < 3 { continue }
                return nil
            }
            let text = String(decoding: data.prefix(2048), as: UTF8.self)
            if PrivacyEngineWire.throttled(status: http.statusCode, body: text), attempt < 5 {
                try? await Task.sleep(for: .milliseconds(500 << attempt))
                continue
            }
            if request.url != fallback, PrivacyEngineWire.missesHead(text) {
                request.url = fallback
                continue
            }
            return (data, http)
        }
        return nil
    }
}

// MARK: - The app's scheme: the page, the bundle, the circuits

final class PrivacyEngineScheme: NSObject, WKURLSchemeHandler {
    static let shared = PrivacyEngineScheme()

    /// Tasks WebKit has stopped: answering one after `stop` is a crash.
    @MainActor private var stopped = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let path = task.request.url?.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        switch path {
        case "index.html":
            answer(task, Data(PrivacyEngine.page.utf8), type: "text/html")
        case "privacy-engine.js":
            guard let url = Bundle.main.url(forResource: "privacy-engine", withExtension: "js"),
                  let data = try? Data(contentsOf: url) else { fail(task, 404, "no bundle"); return }
            answer(task, data, type: "text/javascript")
        default:
            let pins = MainActor.assumeIsolated { PrivacyEngine.shared.pins }
            guard let wanted = PrivacyArtifacts.request(path: path, pins: pins) else {
                fail(task, 404, "not a pinned circuit file")
                return
            }
            let id = ObjectIdentifier(task)
            Task { @MainActor in
                defer { stopped.remove(id) }
                do {
                    let data = try await PrivacyArtifactStore.shared.data(for: wanted.file)
                    guard !stopped.contains(id) else { return }
                    answer(task, data, type: wanted.kind == .vkey ? "application/json" : "application/octet-stream")
                } catch {
                    guard !stopped.contains(id) else { return }
                    fail(task, 502, "\(wanted.name)/\(wanted.kind.rawValue): \(error)")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        MainActor.assumeIsolated { _ = stopped.insert(ObjectIdentifier(task)) }
    }

    private func answer(_ task: any WKURLSchemeTask, _ data: Data, type: String) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": type,
                  "Content-Length": String(data.count),
                  "Content-Security-Policy": PrivacyEngine.contentSecurityPolicy,
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

// MARK: - The circuit files

/// Downloads each pinned circuit file once, checks it against its pin, keeps
/// it in Application Support under its hash, and re-checks it on every read.
actor PrivacyArtifactStore {
    static let shared = PrivacyArtifactStore()

    enum Failure: Error { case noCopyMatched(String), noDirectory }

    private var inFlight: [String: Task<Data, Error>] = [:]

    private func directory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Failure.noDirectory
        }
        let dir = base.appendingPathComponent("PrivacyPools/circuits", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = dir
        try? copy.setResourceValues(values)
        return dir
    }

    func data(for file: PrivacyArtifacts.File) async throws -> Data {
        if let running = inFlight[file.sha256] { return try await running.value }
        let task = Task<Data, Error> { try await self.load(file) }
        inFlight[file.sha256] = task
        defer { inFlight[file.sha256] = nil }
        return try await task.value
    }

    /// Whether a file is already here and verified (no download).
    func isCached(_ file: PrivacyArtifacts.File) -> Bool {
        guard let dir = try? directory(),
              let data = try? Data(contentsOf: PrivacyArtifacts.cacheURL(for: file, in: dir)) else { return false }
        return PrivacyArtifacts.verify(data, against: file)
    }

    private func load(_ file: PrivacyArtifacts.File) async throws -> Data {
        let path = PrivacyArtifacts.cacheURL(for: file, in: try directory())
        if let kept = try? Data(contentsOf: path) {
            if PrivacyArtifacts.verify(kept, against: file) { return kept }
            try? FileManager.default.removeItem(at: path)
        }
        for url in PrivacyArtifacts.urls(for: file) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivacyEngine.circuitsService),
                  http.statusCode == 200 else { continue }
            guard PrivacyArtifacts.verify(data, against: file) else {
                NSLog("privacyEngine| artifact | refused %@ from %@ (hash)", file.cid, url.host ?? "?")
                continue
            }
            try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return data
        }
        throw Failure.noCopyMatched(file.cid)
    }
}
