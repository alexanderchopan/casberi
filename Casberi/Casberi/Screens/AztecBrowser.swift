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
/// here the same way. With `sends` (Apps on Aztec, prd §1700k) a page may
/// also send a transaction on Ethereum: the sheet says what it does, then
/// Face ID and, when the account needs both keys, the Signer.
@MainActor
final class AztecBrowserModel: NSObject, ObservableObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {

    enum Request: Identifiable, Equatable {
        case connect(requestId: String, host: String)
        case emoji(sessionId: String, host: String, emoji: String)
        case send(id: Int, host: String, calls: [Call], fee: String)
        case ethConnect(id: String, host: String)
        case ethSign(id: String, host: String, text: String)
        /// An app's transaction on Ethereum, in words: what it does, its
        /// lines, and whether Casberi could read it at all.
        case ethSend(id: String, host: String, says: String, lines: [String], unread: Bool)

        struct Call: Equatable { let name: String; let to: String; let isPublic: Bool }

        var id: String {
            switch self {
            case .connect(let r, _): "connect-\(r)"
            case .emoji(let s, _, _): "emoji-\(s)"
            case .send(let i, _, _, _): "send-\(i)"
            case .ethConnect(let i, _): "eth-connect-\(i)"
            case .ethSign(let i, _, _): "eth-sign-\(i)"
            case .ethSend(let i, _, _, _, _): "eth-send-\(i)"
            }
        }
    }

    static let relayWorld = WKContentWorld.world(name: "casberi")
    static let tabID = 1

    let start: URL
    let page: WKWebView
    let aztec: Bool
    let ethereum: Bool
    /// Whether this page may send a transaction from your account (prd §1700k).
    let sends: Bool
    /// The Ethereum provider's connection, for this page's host only.
    private var ethConnectedHost: String?
    private var ethAnswers: [String: CheckedContinuation<Bool, Never>] = [:]
    @Published var ask: Request?
    @Published var host: String
    @Published var failed: String?
    /// An app's transaction on its way, said under the page.
    @Published var sending: String?
    private var queue: [Request] = []

    init(url: URL, aztec: Bool = true, ethereum: Bool = false, sends: Bool = false) {
        start = url
        self.aztec = aztec
        self.ethereum = ethereum
        self.sends = ethereum && sends
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
        // A swipe from the edge goes back a page and forward again: Home's
        // door opens a directory you walk through (prd §1700i).
        page.allowsBackForwardNavigationGestures = true
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
                                        account: account, connected: ethConnectedHost == here, sends: sends)
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
                let why = AztecEngine.words(error)
                NSLog("browserEthereum| sign failed | %@", why)
                return .error(code: 4001, message: why)
            }
        case .signTyped(let json, let summary):
            guard await ask(.ethSign(id: UUID().uuidString, host: host, text: summary)),
                  let typed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return .rejected }
            do {
                let sig = try await YourAccountMessage.signTypedData(typed, on: YourAccountOp.ethereum, account: account,
                                                                     reason: String(localized: "Sign for \(host)"))
                return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
            } catch {
                let why = AztecEngine.words(error)
                NSLog("browserEthereum| sign failed | %@", why)
                return .error(code: 4001, message: why)
            }
        case .disconnect:
            ethConnectedHost = nil
            return .result(nil)
        case .send(let to, let data, let value):
            let said = await reading(to: to, data: data, value: value, account: account)
            guard await ask(.ethSend(id: UUID().uuidString, host: host, says: said.says, lines: said.lines,
                                     unread: said.unread)) else { return .rejected }
            failed = nil
            sending = String(localized: "Sending on Ethereum…")
            defer { sending = nil }
            do {
                let sent = try await YourAccountChain.appCalls(
                    [(to: to, data: data, value: value)], on: YourAccountOp.ethereum,
                    reason: String(localized: "Send for \(host)"),
                    signer: { SignerRequestSheet.coSigner(owner: $0, chainId: YourAccountOp.ethereum.chainId) }) { _ in }
                switch sent.outcome {
                case .landed(let tx?, _):
                    NSLog("browserEthereum| sent | %@", tx)
                    return .result("\"\(tx)\"")
                case .landed(nil, _):
                    return .error(code: -32603, message: "Sent. Ethereum has not said which transaction carried it; Casberi's Wallet shows it.")
                case .pending:
                    return .error(code: -32603, message: "Sent, and not seen on Ethereum yet. Casberi's Wallet shows it once it lands.")
                case .dryRun:
                    return .rejected
                }
            } catch {
                let why = AztecEngine.words(error)
                NSLog("browserEthereum| send failed | %@", why)
                failed = why
                return .error(code: 4001, message: why)
            }
        case .read(let method, let params):
            guard let value = try? await YourAccountChain.rpc(YourAccountOp.ethereum, method, params),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
                return .error(code: -32603, message: "Ethereum did not answer.")
            }
            return .result(String(data: data, encoding: .utf8))
        }
    }

    /// What an app's transaction does, in words (prd §1700k): a token
    /// approval read here, any other call through clear signing
    /// (`ClearSign`, the Ethereum Foundation's registry), tokens named off
    /// their own contracts; a call neither can read says so.
    private func reading(to: String, data: String, value: String, account: String)
        async -> (says: String, lines: [String], unread: Bool) {
        let net = YourAccountOp.ethereum
        var lines: [String] = []
        if value != "0" {
            lines.append(String(localized: "Pays \(YourAccountOp.spoken(value, decimals: 18)) ETH"))
        }
        if let a = BrowserEthereum.approval(data) {
            let token = await YourAccountTokens.lookUp(to, on: net)?.token
            let name = token?.symbol ?? AddressTail.short(to)
            let amount = a.unlimited ? String(localized: "No limit")
                : token.map { "\(YourAccountOp.display(a.amount, decimals: $0.decimals)) \($0.symbol)" }
                    ?? String(localized: "\(a.amount) base units")
            return (String(localized: "Lets \(AddressTail.short(a.spender)) spend your \(name)"), [amount] + lines, false)
        }
        guard let bytes = SafeABI.hexBytes(data) else {
            return (String(localized: "A call to \(AddressTail.short(to))"), lines, true)
        }
        if bytes.isEmpty {
            return (String(localized: "Sends to \(AddressTail.short(to))"), lines, false)
        }
        await ClearSign.warm()
        var facts: [String: (symbol: String?, decimals: Int?)] = [:]
        for asked in ClearSign.tokensAsked(chainId: net.chainId, to: to, data: bytes, value: value, from: account) {
            if let token = await YourAccountTokens.lookUp(asked, on: net)?.token {
                facts[asked.lowercased()] = (token.symbol, token.decimals)
            }
        }
        var style = ClearSign.Style.casberi(facts: facts)
        style.sender = String(localized: "your account")
        if let r = ClearSign.describe(chainId: net.chainId, to: to, data: bytes, value: value, from: account, style: style) {
            return (r.headline, r.lines.map { "\($0.label): \($0.value)" } + lines, false)
        }
        return (String(localized: "A call to \(AddressTail.short(to))"), lines, true)
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
        if case .send(_, let host, let calls, _) = ask, yes {
            do {
                try await PrivateRootKey.unlock(reason: String(localized: "Approve this Aztec transaction"))
                // The co-signer approves an app's transaction too (prd §1700f item 4).
                try await AztecCoSign.approve(String(localized: "\(host): \(calls.map(\.name).joined(separator: ", "))"))
            } catch {
                failed = AztecEngine.words(error)
                return
            }
        }
        queue.removeAll { $0.id == ask.id }
        // A declined connect ends the session: its emoji check is not asked
        // (the session's id is the connect's request id, prd §1700j).
        if case .connect(let session, _) = ask, !yes {
            queue.removeAll { if case .emoji(session, _, _) = $0 { true } else { false } }
        }
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

    init(url: URL, aztec: Bool = true, ethereum: Bool = false, sends: Bool = false) {
        _model = StateObject(wrappedValue: AztecBrowserModel(url: url, aztec: aztec, ethereum: ethereum, sends: sends))
    }

    var body: some View {
        VStack(spacing: 0) {
            AztecPage(view: model.page)
            if let sending = model.sending {
                Text(verbatim: sending).dsText(.subhead12).foregroundStyle(DS.textSecondary).padding()
            }
            if let failed = model.failed {
                Text(verbatim: failed).dsText(.subhead12).foregroundStyle(DS.destructiveInk).padding()
            }
        }
        .navigationTitle(Text(verbatim: model.host))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.open() }
        .onDisappear { model.close() }
        .sheet(item: $model.ask, onDismiss: { model.sheetGone() }) { ask in
            AztecAskSheet(ask: ask, sends: model.sends) { yes in Task { await model.answer(ask, yes: yes) } }
        }
    }
}

private struct AztecPage: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// One ask: connect, the emoji check, or a transaction. Two choices each:
/// the yes is the act's tile (`DSActVerb`), the no a door row under it, the
/// `SafeAskSheet` shape, on ink like every other ask the wallet raises.
struct AztecAskSheet: View {
    let ask: AztecBrowserModel.Request
    /// Whether this page may send from your account, so Connect says so.
    var sends = false
    let answer: (Bool) -> Void

    var body: some View {
        DSTray(title: title, height: height, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                content
                DSActVerb(title: acceptWord, glyph: acceptGlyph) { answer(true) }
                DSDoorRow(icon: "xmark", title: Text(declineWord), role: .destructive) { answer(false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // An app's ask is answered, never swiped away unanswered: the two
        // verbs are the way out (way-back-audit ALLOWED).
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var content: some View {
        switch ask {
        case .connect:
            DSProse.text("It sees your Aztec account's address. Casberi asks you before anything it sends.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .emoji(_, _, let emoji):
            // The nine in one row, the way they are read: left to right.
            Text(verbatim: emoji)
                .dsText(.heading34)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .send(_, _, let calls, let fee):
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
        case .ethConnect:
            if sends {
                DSProse.text("It sees your account's address. Casberi asks before every signature and every send.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DSProse.text("It sees your account's address. Casberi asks before every signature and sends nothing from this page.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ethSend(_, _, let says, let lines, let unread):
            Text(verbatim: says).dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if unread {
                Text("Casberi cannot read what this call does. It runs on Ethereum first, and nothing is signed if it would fail.")
                    .dsText(.subhead12).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("It runs on Ethereum first, and nothing is signed if it would fail.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ethSign(_, _, let text):
            ScrollView {
                Text(verbatim: text).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            Text("Signing proves this is your account. It moves nothing.")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
        }
    }

    private var title: String {
        switch ask {
        case .connect(_, let host): String(localized: "Connect \(host)?")
        case .emoji: String(localized: "Check the site shows")
        case .send(_, let host, _, _): String(localized: "\(host) wants to send")
        case .ethConnect(_, let host): String(localized: "Connect \(host) to your account?")
        case .ethSign(_, let host, _): String(localized: "\(host) asks your account to sign")
        case .ethSend(_, let host, _, _, _): String(localized: "\(host) wants to send")
        }
    }

    private var height: CGFloat {
        switch ask { case .connect, .ethConnect: 400; case .emoji: 360; case .send, .ethSign, .ethSend: 520 }
    }

    private var acceptWord: String {
        switch ask {
        case .connect, .ethConnect: String(localized: "Connect")
        case .emoji: String(localized: "They match")
        case .send, .ethSend: String(localized: "Approve")
        case .ethSign: String(localized: "Sign")
        }
    }
    private var acceptGlyph: String {
        switch ask {
        case .connect, .ethConnect: "link"
        case .emoji: "checkmark"
        case .send, .ethSign, .ethSend: "faceid"
        }
    }
    private var declineWord: String {
        switch ask { case .emoji: String(localized: "They don't"); default: String(localized: "Decline") }
    }
}
