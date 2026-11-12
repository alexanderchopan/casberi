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
/// `tools/aztec-dapp-spike` (simulator and iPhone, 2026-11-04; the spike
/// is in the repository's history, removed 2026-11-11).
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
        // Your own Aztec node: its address is yours (http on a home network
        // too), asked directly, never through Tor (§1509 item 5).
        if let own = OwnNodeStore.aztecNode.flatMap(URL.init(string:)),
           url.host?.lowercased() == own.host?.lowercased(), url.port == own.port, url.scheme == own.scheme {
            return OwnNodeStore.service
        }
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return nil }
        for name in [service, parametersService] {
            let hosts = NetworkReach.endpoint(forService: name)?.hosts ?? []
            if hosts.contains(where: { host == $0.lowercased() || host.hasSuffix("." + $0.lowercased()) }) { return name }
        }
        return nil
    }

    /// The Aztec app open in Casberi's browser, if any: where the relay's
    /// answers and the person's asks go (one browser at a time).
    weak var browser: AztecBrowserModel?

    private var server: AztecEngineServer?
    private var webView: WKWebView?
    private var isReady = false
    private var starting = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var calls: [Int: CheckedContinuation<Any?, Error>] = [:]
    private var nextCall = 0

    /// An error in words a person can read: the Safe's failures carry
    /// theirs in `message` (they are not `LocalizedError`), every other in
    /// its description. Without it a Safe's refusal read "The operation
    /// couldn't be completed (YourAccountChain.Failure error 1)" (seen on
    /// the phone, 2026-11-04).
    nonisolated static func words(_ error: Error) -> String {
        (error as? YourAccountChain.Failure)?.message ?? error.localizedDescription
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Starting

    /// Serves the page and loads it; returns once the page says it is ready.
    func start() async throws {
        if isReady { return }
        // One start makes the page; any other asked meanwhile waits for it.
        if webView == nil, !starting {
            starting = true
            defer { starting = false }
            // A recycled page keeps the server it had (`recycle`): a second
            // one would find the port taken.
            if server == nil {
                let made = try AztecEngineServer()
                let listening: Bool = await withCheckedContinuation { done in
                    made.start { ok in done.resume(returning: ok) }
                }
                guard listening else {
                    let failure = Failure(message: "the engine's port is taken")
                    for waiter in readyWaiters { waiter.resume(throwing: failure) }
                    readyWaiters = []
                    throw failure
                }
                server = made
            }
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
            // Your own Aztec node, when you set one (prd §1700f item 3).
            var page = URLComponents(string: AztecEngineServer.origin + "/")!
            if let own = OwnNodeStore.aztecNode { page.queryItems = [URLQueryItem(name: "node", value: own)] }
            view.load(URLRequest(url: page.url!))
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
                           "engineToTab", "engineConnect", "engineApprove", "engineEmoji", "engineStep",
                           "engineBroken", "engineAskGone"]

    // MARK: - A store that stopped answering

    /// **THE WALLET'S STORE CAN GO DEAD UNDER A RUNNING PAGE (seen on a
    /// phone, 2026-11-12).** RavenHouse drew `SQLITE_IOERR … disk I/O error`
    /// on the first call after Connect. The wallet keeps its notes in SQLite
    /// over WebKit's private files, and a page whose files stopped answering
    /// fails every later call the same way until the app is quit. So the
    /// page is thrown away and a new one made: the keys are in the Keychain
    /// and the notes are on disk, so nothing is lost but the app's session,
    /// which connects again. WHY the files die is unmeasured (the likeliest
    /// is the app sitting suspended); this heals whichever cause a fresh
    /// page survives, and no other.
    nonisolated static func storeFailed(_ message: String) -> Bool {
        message.range(of: #"SQLITE_(IOERR|CANTOPEN|CORRUPT|NOTADB)|disk I/O error"#,
                      options: [.regularExpression, .caseInsensitive]) != nil
    }

    private var lastRecycle: Date?

    /// The wallet inside the page is starting (a PXE, seconds on a phone)
    /// while a connected app waits on it: the browser's band says so. A
    /// wallet warming under a page nobody has connected says nothing.
    private var walletStarting = false { didSet { tellBrowser() } }
    private var appWaiting = false { didSet { tellBrowser() } }
    var appWaitsOnWallet: Bool { walletStarting && appWaiting }
    private func tellBrowser() { browser?.wallet(starting: appWaitsOnWallet) }

    /// Throws the page away for a new one, once a minute at most: storage
    /// that is really gone (a full disk) fails again and is said, never
    /// looped on. True when it did.
    @discardableResult
    private func recycle(_ why: String) -> Bool {
        guard lastRecycle.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return false }
        lastRecycle = Date()
        NSLog("aztecEngine| store | recycling the page | %@", String(why.prefix(200)))
        isReady = false
        walletStarting = false
        appWaiting = false
        let message = String(localized: "Your Aztec account restarted. Try again.")
        for waiter in readyWaiters { waiter.resume(throwing: Failure(message: message)) }
        readyWaiters = []
        for (_, done) in calls { done.resume(throwing: Failure(message: message)) }
        calls = [:]
        // Off the window and released, so its process and its workers end
        // and let go of the files.
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        return true
    }

    // MARK: - Casberi's own calls

    /// One of the engine's own calls (`account`, `chain`); the wallet starts on
    /// the first (a PXE, a few seconds). A call the store failed is asked
    /// once more of a new page.
    func call(_ method: String, _ args: [Any] = []) async throws -> Any? {
        do {
            return try await ask(method, args)
        } catch let failure as Failure where Self.storeFailed(failure.message) {
            recycle(failure.message)
            return try await ask(method, args)
        }
    }

    #if DEBUG
    /// `-aztecEngineProbe recycle`: the next call fails as a dead store does,
    /// before the page is asked, so the restart and the second ask can be
    /// watched on a simulator, whose store does not die by itself.
    var failNextAsk = false
    #endif

    private func ask(_ method: String, _ args: [Any]) async throws -> Any? {
        #if DEBUG
        if failNextAsk {
            failNextAsk = false
            throw Failure(message: "SQLITE_IOERR: sqlite3 result code 10: disk I/O error")
        }
        #endif
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
            // An account used on this phone finds its own root or nothing: a
            // new root would be a different, empty Aztec account.
            guard let root = AztecRoot.ensure(create: !AztecAccountStore.shared.snapshot.used) else {
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
            // The page's band says the wallet is starting until it has
            // an account or has answered (prd §1756).
            switch event {
            case "walletStarting": walletStarting = true
            case "accountReady": walletStarting = false
            case "connected": appWaiting = true
            case "answered", "refused": walletStarting = false; appWaiting = false
            default: break
            }
        case "engineAskGone":
            // The app ended the session its Connect or emoji check was for
            // (RavenHouse gives up on a slow wallet and starts over): a
            // sheet left standing asked about nothing (prd §1756).
            if let id = body["id"] as? String { browser?.withdraw(session: id) }
        case "engineBroken":
            // An app's call found the store dead; the app has its answer,
            // and the next page is made now.
            // The app's page is loaded again once it is: an app may not let
            // Casberi be picked twice.
            if recycle(body["error"] as? String ?? "?") {
                Task {
                    try? await start()
                    browser?.engineRestarted()
                }
            }
        case "engineStep":
            // A send's steps, for the screen that started it (prd §1700w).
            PrivateSendSteps.shared.received(body, plan: .send(.aztec))
        case "engineToTab":
            guard let inner = body["message"], let data = try? JSONSerialization.data(withJSONObject: inner) else { return }
            browser?.deliver(String(decoding: data, as: UTF8.self))
        case "engineConnect":
            // Asked when the person picks Casberi in the app, never on the
            // app's discovery, which the engine answers at once (prd §1700j).
            guard let requestId = body["requestId"] as? String else { return }
            guard let browser else {
                // No browser to ask in: a connect nobody can see is declined.
                answer(.connect(requestId: requestId, host: ""), yes: false)
                return
            }
            browser.enqueue(.connect(requestId: requestId, host: Self.host(body["origin"])))
        case "engineEmoji":
            guard let sessionId = body["sessionId"] as? String, let emoji = body["emoji"] as? String else { return }
            guard let browser else {
                answer(.emoji(sessionId: sessionId, host: "", emoji: emoji), yes: false)
                return
            }
            browser.enqueue(.emoji(sessionId: sessionId, host: Self.host(body["origin"]), emoji: emoji))
        case "engineApprove":
            guard let id = body["id"] as? Int else { return }
            guard let browser else {
                // No browser to ask in: a transaction nobody can see is declined.
                webView?.callAsyncJavaScript("casberiEngine.answerApproval(id, false)", arguments: ["id": id], in: nil, in: .page) { _ in }
                return
            }
            let calls = (body["calls"] as? [[String: Any]] ?? []).map {
                AztecBrowserModel.Request.Call(name: $0["name"] as? String ?? "?", to: $0["to"] as? String ?? "",
                                           isPublic: ($0["type"] as? String) == "public")
            }
            browser.enqueue(.send(id: id, host: Self.host(body["origin"]), calls: calls,
                                  fee: body["fee"] as? String ?? ""))
        default:
            break
        }
    }

    private static func host(_ origin: Any?) -> String {
        (origin as? String).flatMap { URL(string: $0)?.host(percentEncoded: false) } ?? String(localized: "This site")
    }

    // MARK: - Apps' door

    /// A message from an app page's relay, with the tab and the page's URL as
    /// the browser read them.
    func fromPage(_ json: String, tabID: Int, url: String) {
        webView?.callAsyncJavaScript("casberiEngine.fromContent(json, tabId, url)",
                                     arguments: ["json": json, "tabId": tabID, "url": url], in: nil, in: .page) { _ in }
    }

    /// The person's answer to an ask.
    func answer(_ ask: AztecBrowserModel.Request, yes: Bool) {
        switch ask {
        case .connect(let requestId, _):
            webView?.callAsyncJavaScript("casberiEngine.answerConnect(r, yes)", arguments: ["r": requestId, "yes": yes], in: nil, in: .page) { _ in }
            if yes {
                // A connect is a use (prd §1700a item 2): the row appears.
                Task { if let address = try? await accountAddress() { AztecAccountStore.shared.markUsed(address: address) } }
            }
        case .emoji(let sessionId, _, _):
            webView?.callAsyncJavaScript("casberiEngine.confirmEmoji(s, match)", arguments: ["s": sessionId, "match": yes], in: nil, in: .page) { _ in }
        case .send(let id, _, _, _):
            webView?.callAsyncJavaScript("casberiEngine.answerApproval(id, yes)", arguments: ["id": id, "yes": yes], in: nil, in: .page) { _ in }
        case .ethConnect, .ethSign, .ethSend, .ethTopUp:
            break // the browser answers its own Ethereum asks
        }
    }

    fileprivate func pageFailed(_ message: String) {
        NSLog("aztecEngine| page | %@", message)
        isReady = false
        walletStarting = false
        appWaiting = false
        for waiter in readyWaiters { waiter.resume(throwing: Failure(message: message)) }
        readyWaiters = []
        for (_, done) in calls { done.resume(throwing: Failure(message: message)) }
        calls = [:]
        // Off the window too: a view the window still holds keeps its page.
        webView?.removeFromSuperview()
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
