import SwiftUI
import WebKit

/// **AN AZTEC APP IN CASBERI'S BROWSER (prd §1700 item 5).** The app's page in
/// a web view, with Aztec's content-script relay (`AztecEngine/relay.js`)
/// added at document start in an isolated script world the page cannot reach;
/// the relay's messages go to `AztecEngine`, which holds the session keys and
/// the wallet, and this view names the page's origin itself — the page cannot
/// claim one. Every connect, the emoji check and every transaction ask here,
/// one sheet at a time (item 6). Proved first in `tools/aztec-dapp-spike`.
/// Opened with `ethereum`, the page also gets your account as an Ethereum
/// provider (`BrowserEthereum`): connect, then each message signed, asked
/// here the same way.
@MainActor
final class AztecBrowserModel: NSObject, ObservableObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {

    enum Request: Identifiable, Equatable {
        case connect(requestId: String, host: String)
        case emoji(sessionId: String, host: String, emoji: String)
        case send(id: Int, host: String, calls: [Call], fee: String)
        case ethConnect(id: String, host: String)
        case ethSign(id: String, host: String, text: String)

        struct Call: Equatable { let name: String; let to: String; let isPublic: Bool }

        var id: String {
            switch self {
            case .connect(let r, _): "connect-\(r)"
            case .emoji(let s, _, _): "emoji-\(s)"
            case .send(let i, _, _, _): "send-\(i)"
            case .ethConnect(let i, _): "eth-connect-\(i)"
            case .ethSign(let i, _, _): "eth-sign-\(i)"
            }
        }
    }

    static let relayWorld = WKContentWorld.world(name: "casberi")
    static let tabID = 1

    let start: URL
    let page: WKWebView
    let aztec: Bool
    let ethereum: Bool
    /// The Ethereum provider's connection, for this page's host only.
    private var ethConnectedHost: String?
    private var ethAnswers: [String: CheckedContinuation<Bool, Never>] = [:]
    @Published var ask: Request?
    @Published var host: String
    @Published var failed: String?
    private var queue: [Request] = []

    init(url: URL, aztec: Bool = true, ethereum: Bool = false) {
        start = url
        self.aztec = aztec
        self.ethereum = ethereum
        host = url.host(percentEncoded: false) ?? ""
        let relay = (Bundle.main.url(forResource: "AztecEngine", withExtension: nil)?
            .appendingPathComponent("relay.js")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let controller = WKUserContentController()
        if aztec {
            controller.addUserScript(WKUserScript(source: relay, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: Self.relayWorld))
        }
        if ethereum {
            controller.addUserScript(WKUserScript(source: BrowserEthereum.script, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: .page))
        }
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // The app's site keeps its own storage, apart from the engine's origin.
        config.websiteDataStore = .default()
        page = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        page.isInspectable = true
        #endif
        super.init()
        if aztec { controller.add(self, contentWorld: Self.relayWorld, name: "casberiRelay") }
        if ethereum { controller.addScriptMessageHandler(self, contentWorld: .page, name: "casberiEthereum") }
        page.navigationDelegate = self
    }

    /// Starts the engine first, so the relay's first message has somewhere to go.
    func open() async {
        guard aztec else { page.load(URLRequest(url: start)); return }
        do {
            try await AztecEngine.shared.start()
            AztecEngine.shared.browser = self
            page.load(URLRequest(url: start))
        } catch {
            failed = error.localizedDescription
        }
    }

    func close() {
        if AztecEngine.shared.browser === self { AztecEngine.shared.browser = nil }
        page.configuration.userContentController.removeAllScriptMessageHandlers()
        for (_, answer) in ethAnswers { answer.resume(returning: false) }
        ethAnswers.removeAll()
    }

    // MARK: - Your account, as an Ethereum provider

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.name == "casberiEthereum", ethereum, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let method = body["method"] as? String else {
            replyHandler(BrowserEthereum.Reply.unsupported.body, nil); return
        }
        // The page's host is this view's reading, never the page's word; a
        // connection is for the host it was given to.
        let here = page.url?.host(percentEncoded: false) ?? host
        guard let account = YourAccountKey.address, !DemoMode.isActive else {
            // No account to offer (or the demo): the page learns there is
            // none, and anything it asks of one is refused.
            NSLog("browserEthereum| %@ | refused: %@", method, DemoMode.isActive ? "demo" : "no account")
            let reply: BrowserEthereum.Reply = switch method {
            case "eth_accounts": .result("[]")
            case "eth_chainId": .result("\"0x1\"")
            default: .error(code: 4100, message: "There is no account here.")
            }
            replyHandler(reply.body, nil); return
        }
        let need = BrowserEthereum.need(method: method, paramsJSON: body["params"] as? String ?? "[]",
                                        account: account, connected: ethConnectedHost == here)
        Task { @MainActor in
            let reply = await self.answer(need, host: here, account: account)
            if case .error(let code, _) = reply { NSLog("browserEthereum| %@ | error %d", method, code) }
            replyHandler(reply.body, nil)
        }
    }

    private func answer(_ need: BrowserEthereum.Need, host: String, account: String) async -> BrowserEthereum.Reply {
        switch need {
        case .answer(let reply):
            return reply
        case .connect:
            guard await ask(.ethConnect(id: UUID().uuidString, host: host)) else { return .rejected }
            ethConnectedHost = host
            return .result("[\"\(account)\"]")
        case .signText(let text):
            guard await ask(.ethSign(id: UUID().uuidString, host: host, text: text)) else { return .rejected }
            do {
                let sig = try await YourAccountMessage.signText(text, on: YourAccountOp.ethereum, account: account,
                                                                reason: String(localized: "Sign for \(host)"))
                return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
            } catch {
                return .error(code: 4001, message: error.localizedDescription)
            }
        case .signTyped(let json, let summary):
            guard await ask(.ethSign(id: UUID().uuidString, host: host, text: summary)),
                  let typed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return .rejected }
            do {
                let sig = try await YourAccountMessage.signTypedData(typed, on: YourAccountOp.ethereum, account: account,
                                                                     reason: String(localized: "Sign for \(host)"))
                return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
            } catch {
                return .error(code: 4001, message: error.localizedDescription)
            }
        case .read(let method, let params):
            guard let value = try? await YourAccountChain.rpc(YourAccountOp.ethereum, method, params),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
                return .error(code: -32603, message: "Ethereum did not answer.")
            }
            return .result(String(data: data, encoding: .utf8))
        }
    }

    /// Raises an ask and waits for the person's answer.
    private func ask(_ request: Request) async -> Bool {
        await withCheckedContinuation { answer in
            ethAnswers[request.id] = answer
            enqueue(request)
        }
    }

    // MARK: - The relay

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "casberiRelay", message.world == Self.relayWorld,
              message.frameInfo.isMainFrame, let body = message.body as? String else { return }
        // The origin is this view's reading of the page, never the page's word.
        AztecEngine.shared.fromPage(body, tabID: Self.tabID, url: page.url?.absoluteString ?? "")
    }

    /// What the engine sends back to the page's relay, into its world only.
    func deliver(_ json: String) {
        page.callAsyncJavaScript("window.__casberiDeliver(json)", arguments: ["json": json],
                                 in: nil, in: Self.relayWorld) { _ in }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        host = webView.url?.host(percentEncoded: false) ?? host
    }

    // MARK: - Asking

    func enqueue(_ next: Request) {
        if ask == nil { ask = next } else { queue.append(next) }
    }

    /// The sheet has gone; the next ask, if any.
    func sheetGone() {
        guard ask == nil, !queue.isEmpty else { return }
        ask = queue.removeFirst()
    }

    func answer(_ ask: Request, yes: Bool) async {
        if case .send = ask, yes {
            do { try await PrivateRootKey.unlock(reason: String(localized: "Approve this Aztec transaction")) } catch { return }
        }
        queue.removeAll { $0.id == ask.id }
        if let waiting = ethAnswers.removeValue(forKey: ask.id) {
            waiting.resume(returning: yes)
        } else {
            AztecEngine.shared.answer(ask, yes: yes)
        }
        if self.ask?.id == ask.id { self.ask = nil }
    }
}

struct AztecBrowserView: View {
    @StateObject private var model: AztecBrowserModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL, aztec: Bool = true, ethereum: Bool = false) {
        _model = StateObject(wrappedValue: AztecBrowserModel(url: url, aztec: aztec, ethereum: ethereum))
    }

    var body: some View {
        VStack(spacing: 0) {
            AztecPage(view: model.page)
            if let failed = model.failed {
                Text(verbatim: failed).dsText(.subhead12).foregroundStyle(DS.destructiveInk).padding()
            }
        }
        .navigationTitle(Text(verbatim: model.host))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.open() }
        .onDisappear { model.close() }
        .sheet(item: $model.ask, onDismiss: { model.sheetGone() }) { ask in
            AztecAskSheet(ask: ask) { yes in Task { await model.answer(ask, yes: yes) } }
        }
    }
}

private struct AztecPage: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// One ask: connect, the emoji check, or a transaction. Two choices each.
struct AztecAskSheet: View {
    let ask: AztecBrowserModel.Request
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            switch ask {
            case .connect(_, let host):
                Text("Connect \(host)?").dsText(.heading24).foregroundStyle(DS.textPrimary)
                Text("It sees your Aztec account's address. Casberi asks you before anything it sends.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            case .emoji(_, let host, let emoji):
                Text("Check the site shows").dsText(.heading24).foregroundStyle(DS.textPrimary)
                Text(verbatim: emoji).dsText(.heading34).frame(maxWidth: .infinity)
                Text("If \(host) shows the same nine, nothing sits between you.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            case .send(_, let host, let calls, let fee):
                Text("\(host) wants to send").dsText(.heading24).foregroundStyle(DS.textPrimary)
                ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                        Image(systemName: call.isPublic ? "eye" : "lock.fill")
                            .foregroundStyle(call.isPublic ? DS.attention : DS.textSecondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: call.name.replacingOccurrences(of: "_", with: " "))
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            Text(verbatim: "\(call.isPublic ? String(localized: "Public") : String(localized: "Private")) · \(call.to)")
                                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        }
                    }
                }
                Text(verbatim: fee).dsText(.subhead12).foregroundStyle(DS.textSecondary)
            case .ethConnect(_, let host):
                Text("Connect \(host) to your account?").dsText(.heading24).foregroundStyle(DS.textPrimary)
                Text("It sees your account's address. Casberi asks before every signature and sends nothing from this page.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            case .ethSign(_, let host, let text):
                Text("\(host) asks your account to sign").dsText(.heading24).foregroundStyle(DS.textPrimary)
                ScrollView {
                    Text(verbatim: text).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                Text("Signing proves this is your account. It moves nothing.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s3) {
                Button(declineWord) { answer(false) }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                Button(acceptWord) { answer(true) }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
        }
        .padding(DS.Space.s6)
        .dsSizedSheet(420)
        // An app's ask is answered, never swiped away unanswered: the two
        // buttons are the way out (way-back-audit ALLOWED).
        .interactiveDismissDisabled()
    }

    private var acceptWord: LocalizedStringKey {
        switch ask { case .connect, .ethConnect: "Connect"; case .emoji: "They match"; case .send: "Approve"; case .ethSign: "Sign" }
    }
    private var declineWord: LocalizedStringKey {
        switch ask { case .connect, .send, .ethConnect, .ethSign: "Decline"; case .emoji: "They don't" }
    }
}
