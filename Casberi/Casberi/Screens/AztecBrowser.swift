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
        /// Your co-signer cannot pay an app's send: move what it lacks from
        /// your account first (prd §1700l item 10). Amounts in wei.
        case ethTopUp(id: String, host: String, signer: String, amount: String, holds: String, needs: String)

        struct Call: Equatable { let name: String; let to: String; let isPublic: Bool }

        var id: String {
            switch self {
            case .connect(let r, _): "connect-\(r)"
            case .emoji(let s, _, _): "emoji-\(s)"
            case .send(let i, _, _, _): "send-\(i)"
            case .ethConnect(let i, _): "eth-connect-\(i)"
            case .ethSign(let i, _, _): "eth-sign-\(i)"
            case .ethSend(let i, _, _, _, _): "eth-send-\(i)"
            case .ethTopUp(let i, _, _, _, _, _): "eth-top-up-\(i)"
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
    /// The page is connected as your co-signer, not your account (prd
    /// §1700l): the co-signer's address, for an app that takes only a plain
    /// key's signature. Nil while connected as your account.
    @Published private(set) var ethCoSigner: String?
    /// Your account's co-signer on Ethereum, read when the page opens: the
    /// connect sheet offers it in a quiet line, and only when there is one.
    @Published private(set) var coSigner: String?
    /// The connect sheet's answer was "Use your co-signer instead".
    private var choseCoSigner = false
    /// You signed into this site with your co-signer before, so its Connect
    /// leads with it and says so (prd §1700l item 11).
    @Published private(set) var rememberedCoSigner = false
    /// Lands a co-signer's send for an app in the Wallet's Activity (prd
    /// §1700l item 13); the view hands it its model context.
    var landActivity: ((_ hash: String, _ title: String) -> Void)?
    /// Your co-signer signed for this page since it connected as your
    /// co-signer; until then, a connect again leads with the co-signer.
    private var coSignerSigned = false
    /// When your account last signed for this page: a connect soon after
    /// is a sign-in the app turned down (prd §1700l).
    private var accountSignedAt: Date?
    /// This Connect follows a sign-in the app turned down, so it leads
    /// with your co-signer.
    @Published private(set) var reconnecting = false
    private var ethAnswers: [String: CheckedContinuation<Bool, Never>] = [:]
    @Published var ask: Request? {
        didSet { if ask != nil { askSheetUp = true } }
    }
    /// An ask sheet is on screen or still leaving it. The Signer sheet is
    /// raised over whatever is on top, so it waits for this one to go: raised
    /// while it slides away, it went with it and nothing showed (build 951,
    /// prd §1700l item 7).
    private var askSheetUp = false
    private var askSheetGoneWaiters: [CheckedContinuation<Void, Never>] = []
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
        if ethereum, sends, let account = YourAccountKey.address, !DemoMode.isActive {
            #if DEBUG
            // `-coSignerSample <0x…>`: a co-signer for the simulator, which has none (prd §1700l).
            if let sample = UserDefaults.standard.string(forKey: "coSignerSample") { coSigner = sample }
            // `-connectRetrySample YES`: the first Connect is the retry after a turned-down sign-in.
            if UserDefaults.standard.bool(forKey: "connectRetrySample") { reconnecting = true }
            #endif
            if coSigner == nil {
                Task { coSigner = try? await YourAccountChain.knownSigners(YourAccountOp.ethereum, account).first }
            }
        }
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
        // Connected as your co-signer, the page knows the co-signer's address,
        // never sends, and is asked again when it connects again (prd §1700l).
        var connected = ethConnectedHost == here, mayEnd = sends
        if ethCoSigner != nil {
            (connected, mayEnd) = BrowserEthereum.asCoSigner(method: method, connected: connected, sends: mayEnd)
            // Connecting again before the co-signer's sign-in finished is the
            // same sign-in tried again: it leads with the co-signer.
            if !connected, ethConnectedHost == here, !coSignerSigned { reconnecting = true }
        }
        // Your account signed and the page connects again: it turned the
        // sign-in down, so Connect is asked again, co-signer first.
        if ethCoSigner == nil, connected,
           BrowserEthereum.asksAgainAfterSign(method: method, signedAt: accountSignedAt, now: Date(), hasCoSigner: coSigner != nil) {
            connected = false
            reconnecting = true
        }
        let need = BrowserEthereum.need(method: method, paramsJSON: body["params"] as? String ?? "[]",
                                        account: ethCoSigner ?? account, connected: connected, sends: mayEnd)
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
            choseCoSigner = false
            rememberedCoSigner = coSigner != nil && CoSignerApps.remembers(host)
            guard await ask(.ethConnect(id: UUID().uuidString, host: host)) else { return .rejected }
            ethConnectedHost = host
            ethCoSigner = choseCoSigner ? coSigner : nil
            rememberedCoSigner = false
            if coSigner != nil { CoSignerApps.remember(host, coSigner: ethCoSigner != nil) }
            reconnecting = false
            accountSignedAt = nil
            coSignerSigned = false
            return .result("[\"\(ethCoSigner ?? account)\"]")
        case .signText(let text):
            guard await ask(.ethSign(id: UUID().uuidString, host: host, text: text)) else { return .rejected }
            if let co = ethCoSigner {
                let hex = "0x" + Array(text.utf8).map { String(format: "%02x", $0) }.joined()
                return await coSign("personal_sign", params: [hex, co], digest: EIP191.hash(text: text), signer: co)
            }
            do {
                let sig = try await YourAccountMessage.signText(text, on: YourAccountOp.ethereum, account: account,
                                                                reason: String(localized: "Sign for \(host)"))
                accountSignedAt = Date()
                return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
            } catch {
                let why = AztecEngine.words(error)
                NSLog("browserEthereum| sign failed | %@", why)
                return .error(code: 4001, message: why)
            }
        case .signTyped(let json, let summary):
            guard await ask(.ethSign(id: UUID().uuidString, host: host, text: summary)),
                  let typed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return .rejected }
            if let co = ethCoSigner {
                guard let td = EIP712.parse(typed), let digest = EIP712.digest(td) else {
                    return .error(code: 4001, message: "The typed data could not be read.")
                }
                return await coSign("eth_signTypedData_v4", params: [co, json], digest: digest, signer: co)
            }
            do {
                let sig = try await YourAccountMessage.signTypedData(typed, on: YourAccountOp.ethereum, account: account,
                                                                     reason: String(localized: "Sign for \(host)"))
                accountSignedAt = Date()
                return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
            } catch {
                let why = AztecEngine.words(error)
                NSLog("browserEthereum| sign failed | %@", why)
                return .error(code: 4001, message: why)
            }
        case .disconnect:
            ethConnectedHost = nil
            ethCoSigner = nil
            accountSignedAt = nil
            return .result(nil)
        case .send(let to, let data, let value):
            if let co = ethCoSigner { return await coSend(to: to, data: data, value: value, host: host, signer: co) }
            let said = await reading(to: to, data: data, value: value, account: account)
            guard await ask(.ethSend(id: UUID().uuidString, host: host, says: said.says, lines: said.lines,
                                     unread: said.unread)) else { return .rejected }
            failed = nil
            sending = String(localized: "Sending on Ethereum…")
            defer { sending = nil }
            // The Signer sheet may be raised for this send: not over the ask
            // sheet while it leaves (prd §1700l item 7).
            await untilAskSheetGone()
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

    /// Returns once the answered ask sheet has left the screen (its
    /// `onDismiss`), or after two seconds whatever happened.
    private func untilAskSheetGone() async {
        guard askSheetUp, ask == nil else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            askSheetGoneWaiters.append(done)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.releaseAskSheetWaiters()
            }
        }
    }

    private func releaseAskSheetWaiters() {
        let waiting = askSheetGoneWaiters
        askSheetGoneWaiters = []
        waiting.forEach { $0.resume() }
    }

    /// A signature from your co-signer's own wallet (prd §1700l), over a
    /// pairing that asks for this one method and is let go once answered;
    /// the Signer sheet shows the link, as it does for a send.
    private func coSign(_ method: String, params: [String], digest: [UInt8], signer: String) async -> BrowserEthereum.Reply {
        await untilAskSheetGone()
        do {
            let sig = try await SignerRequestSheet.asking(signer: signer, title: String(localized: "Your co-signer signs")) { ask in
                try await YourAccountSignerLink.signForApp(method: method, params: params, digest: digest,
                                                          signer: signer, resend: ask.resends,
                                                          sent: { ask.ask(kept: $0) },
                                                          show: { ask.pair($0); Self.openWallet(holding: signer, onto: $0) })
            }
            coSignerSigned = true
            NSLog("browserEthereum| co-signer signed %@", method)
            return .result("\"0x\(sig.map { String(format: "%02x", $0) }.joined())\"")
        } catch is CancellationError {
            return .rejected
        } catch {
            let why = (error as? YourAccountSignerLink.Failure) == .notProven
                ? String(localized: "That wallet is not your co-signer, so nothing was signed")
                : String(localized: "Your co-signer did not sign")
            NSLog("browserEthereum| co-signer sign failed | %@", String(describing: error))
            failed = why
            return .error(code: 4001, message: why)
        }
    }

    /// An app's send, paid by your co-signer (prd §1700l item 9): said on the
    /// sheet, run on Ethereum from the co-signer's address first (a call that
    /// would fail, or a balance that cannot pay, asks no wallet), then sent by
    /// the co-signer's own wallet, which shows the amount again.
    private func coSend(to: String, data: String, value: String, host: String, signer: String) async -> BrowserEthereum.Reply {
        let said = await reading(to: to, data: data, value: value, account: signer, sender: String(localized: "your co-signer"))
        guard await ask(.ethSend(id: UUID().uuidString, host: host, says: said.says, lines: said.lines,
                                 unread: said.unread)) else { return .rejected }
        failed = nil
        guard let hexValue = BrowserEthereum.hexQuantity(decimal: value) else { return .unsupported }
        let tx = ["from": signer, "to": to, "data": data, "value": hexValue]
        if !(await runsFrom(tx)) {
            // It cannot pay: offer to move what it lacks from your account,
            // then run it again (prd §1700l item 10).
            if let toppedUp = await topUp(signer: signer, value: value, host: host) { return toppedUp }
            guard await runsFrom(tx) else {
                let why = String(localized: "This would fail on Ethereum from your co-signer (\(AddressTail.short(signer))), so nothing was sent.")
                failed = why
                return .error(code: -32603, message: why)
            }
        }
        await untilAskSheetGone()
        sending = String(localized: "Waiting for your co-signer…")
        defer { sending = nil }
        do {
            let hash = try await SignerRequestSheet.asking(signer: signer, title: String(localized: "Your co-signer sends")) { ask in
                try await YourAccountSignerLink.sendForApp(tx: tx, signer: signer, resend: ask.resends,
                                                          sent: { ask.ask(kept: $0) },
                                                          show: { ask.pair($0); Self.openWallet(holding: signer, onto: $0) })
            }
            NSLog("browserEthereum| co-signer sent | %@", hash)
            landActivity?(hash, TitleSeam.join(host, String(localized: "\(YourAccountOp.spoken(value, decimals: 18)) ETH from your co-signer")))
            return .result("\"\(hash)\"")
        } catch is CancellationError {
            return .rejected
        } catch {
            let why = String(localized: "Your co-signer did not send")
            NSLog("browserEthereum| co-signer send failed | %@", String(describing: error))
            failed = why
            return .error(code: 4001, message: why)
        }
    }

    /// Whether `tx` runs on Ethereum from its sender as it stands.
    private func runsFrom(_ tx: [String: String]) async -> Bool {
        do {
            _ = try await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_estimateGas", [tx])
            return true
        } catch {
            NSLog("browserEthereum| would fail from %@ | %@", tx["from"] ?? "?", String(describing: error))
            return false
        }
    }

    /// The co-signer cannot pay `value` and its fee: say what it holds and
    /// what it needs, and on yes send the difference from your account (your
    /// account's own send: Face ID, and the Signer if it needs both keys).
    /// Nil to carry on (sent and landed, or the shortfall is not the reason);
    /// otherwise the reply the page gets.
    private func topUp(signer: String, value: String, host: String) async -> BrowserEthereum.Reply? {
        guard YourAccountKey.address != nil,
              let balance = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getBalance", [signer, "latest"]) as? String,
              let price = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_gasPrice", []) as? String,
              let amount = BrowserEthereum.topUp(balanceHex: balance, valueWei: value, gasPriceHex: price) else { return nil }
        let holds = BrowserEthereum.decimal(hexQuantity: balance) ?? "0"
        guard await ask(.ethTopUp(id: UUID().uuidString, host: host, signer: signer, amount: amount,
                                  holds: holds, needs: value)) else { return .rejected }
        await untilAskSheetGone()
        sending = String(localized: "Moving ETH to your co-signer…")
        defer { sending = nil }
        do {
            let sent = try await YourAccountChain.appCalls(
                [(to: signer, data: "0x", value: amount)], on: YourAccountOp.ethereum,
                reason: String(localized: "Move ETH to your co-signer"),
                signer: { SignerRequestSheet.coSigner(owner: $0, chainId: YourAccountOp.ethereum.chainId) }) { _ in }
            guard case .landed = sent.outcome else {
                let why = String(localized: "The ETH for your co-signer is on its way. Try again once it lands.")
                failed = why
                return .error(code: -32603, message: why)
            }
            NSLog("browserEthereum| topped up the co-signer")
            return nil
        } catch {
            let why = AztecEngine.words(error)
            failed = why
            return .error(code: 4001, message: why)
        }
    }

    /// Opens the co-signer's own wallet onto a fresh pairing, on the phone,
    /// when a session it settled before names which wallet holds it (prd
    /// §1700l item 12). The Signer sheet's doors stay for any other.
    private static func openWallet(holding signer: String, onto pairing: URL) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let wallet = YourAccountSignerLink.walletHolding(signer),
              let link = SignerSwitch.link(wallet, pairing: pairing) else { return }
        UIApplication.shared.open(link)
    }

    /// What an app's transaction does, in words (prd §1700k): a token
    /// approval read here, any other call through clear signing
    /// (`ClearSign`, the Ethereum Foundation's registry), tokens named off
    /// their own contracts; a call neither can read says so.
    private func reading(to: String, data: String, value: String, account: String,
                         sender: String = String(localized: "your account"))
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
        style.sender = sender
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
        if ask == nil { askSheetUp = false; releaseAskSheetWaiters() }
        guard ask == nil, !queue.isEmpty else { return }
        ask = queue.removeFirst()
    }

    /// The connect sheet's quiet line: connect as your co-signer (prd §1700l).
    func connectAsCoSigner(_ ask: Request) async {
        guard case .ethConnect = ask, coSigner != nil else { return }
        choseCoSigner = true
        await answer(ask, yes: true)
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
    @Environment(\.modelContext) private var modelContext

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
        .task {
            let context = modelContext
            model.landActivity = { hash, title in CoSignerApps.land(hash: hash, title: title, context: context) }
            await model.open()
        }
        .onDisappear { model.close() }
        .sheet(item: $model.ask, onDismiss: { model.sheetGone() }) { ask in
            AztecAskSheet(ask: ask, sends: model.sends, coSigner: model.coSigner, asCoSigner: model.ethCoSigner != nil, reconnecting: model.reconnecting,
                          remembered: model.rememberedCoSigner,
                          useCoSigner: { Task { await model.connectAsCoSigner(ask) } }) { yes in Task { await model.answer(ask, yes: yes) } }
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
    /// Your co-signer, offered on Connect in a quiet line (prd §1700l).
    var coSigner: String? = nil
    /// The page is connected as your co-signer, so it signs there.
    var asCoSigner = false
    /// Connect again after a sign-in the app turned down: the co-signer leads.
    var reconnecting = false
    /// You signed in here with your co-signer before (prd §1700l item 11).
    var remembered = false
    var useCoSigner: () -> Void = {}

    private var leadsWithCoSigner: Bool {
        if case .ethConnect = ask { return (reconnecting || remembered) && coSigner != nil }
        return false
    }
    let answer: (Bool) -> Void

    var body: some View {
        DSTray(title: title, height: height, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                content
                if leadsWithCoSigner {
                    // The app turned your account's sign-in down (prd §1700l).
                    DSActVerb(title: String(localized: "Use your co-signer"), glyph: "person.badge.key") { useCoSigner() }
                    DSDoorRow(icon: "link", title: Text(reconnecting ? "Connect your account anyway" : "Connect your account instead")) { answer(true) }
                    DSDoorRow(icon: "xmark", title: Text(declineWord), role: .destructive) { answer(false) }
                } else {
                    DSActVerb(title: acceptWord, glyph: acceptGlyph) { answer(true) }
                    DSDoorRow(icon: "xmark", title: Text(declineWord), role: .destructive) { answer(false) }
                }
                // For an app that takes only a plain key's signature (prd §1700l).
                if case .ethConnect = ask, !leadsWithCoSigner, let coSigner {
                    DSDoorRow(icon: "person.badge.key",
                              title: Text("Use your co-signer instead (\(AddressTail.short(coSigner)))")) { useCoSigner() }
                }
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
        case .ethConnect where leadsWithCoSigner && reconnecting:
            DSProse.text("It needs a sign-in from an Ethereum wallet outside Casberi. Sign in with your co-signer (\(AddressTail.short(coSigner ?? ""))).")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .ethConnect where leadsWithCoSigner:
            DSProse.text("You signed in here with your co-signer (\(AddressTail.short(coSigner ?? ""))) before.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .ethTopUp(_, _, let signer, let amount, let holds, let needs):
            DSProse.text("Your co-signer (\(AddressTail.short(signer))) holds \(YourAccountOp.spoken(holds, decimals: 18)) ETH. This needs \(YourAccountOp.spoken(needs, decimals: 18)) ETH and its fee.")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Casberi sends \(YourAccountOp.spoken(amount, decimals: 18)) ETH from your account to your co-signer, then asks it to send.")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                Text(asCoSigner ? "Casberi cannot read what this call does. Your co-signer's wallet sends it; it runs on Ethereum first, and nothing is sent if it would fail."
                                : "Casberi cannot read what this call does. It runs on Ethereum first, and nothing is signed if it would fail.")
                    .dsText(.subhead12).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(asCoSigner ? "Your co-signer's wallet sends it. It runs on Ethereum first, and nothing is sent if it would fail."
                                : "It runs on Ethereum first, and nothing is signed if it would fail.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ethSign(_, _, let text):
            // The whole message on the sheet (user: "i shouldn't have to
            // scroll in this message"); a longer one than fits still scrolls.
            ScrollView {
                Text(verbatim: text).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Text(asCoSigner ? "Your co-signer's wallet signs it. It moves nothing."
                            : "Signing proves this is your account. It moves nothing.")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
        }
    }

    private var title: String {
        switch ask {
        case .connect(_, let host): String(localized: "Connect \(host)?")
        case .emoji: String(localized: "Check the site shows")
        case .send(_, let host, _, _): String(localized: "\(host) wants to send")
        case .ethConnect(_, let host): leadsWithCoSigner && reconnecting ? String(localized: "\(host) doesn't accept Aztec accounts or Safes")
                                     : leadsWithCoSigner ? String(localized: "Connect \(host) with your co-signer?")
                                     : String(localized: "Connect \(host) to your account?")
        case .ethSign(_, let host, _): asCoSigner ? String(localized: "\(host) asks your co-signer to sign")
                                                  : String(localized: "\(host) asks your account to sign")
        case .ethSend(_, let host, _, _, _): asCoSigner ? String(localized: "\(host) wants your co-signer to send")
                                                        : String(localized: "\(host) wants to send")
        case .ethTopUp: String(localized: "Your co-signer needs ETH")
        }
    }

    private var height: CGFloat {
        switch ask { case .connect: 400; case .ethConnect: leadsWithCoSigner ? 600 : (coSigner == nil ? 400 : 460); case .emoji: 360; case .ethSign: 720; case .send, .ethSend, .ethTopUp: 520 }
    }

    private var acceptWord: String {
        switch ask {
        case .connect, .ethConnect: String(localized: "Connect")
        case .emoji: String(localized: "They match")
        case .send, .ethSend: String(localized: "Approve")
        case .ethTopUp(_, _, _, let amount, _, _): String(localized: "Move \(YourAccountOp.spoken(amount, decimals: 18)) ETH")
        case .ethSign: String(localized: "Sign")
        }
    }
    private var acceptGlyph: String {
        switch ask {
        case .connect, .ethConnect: "link"
        case .emoji: "checkmark"
        case .ethSign where asCoSigner, .ethSend where asCoSigner: "signature"
        case .send, .ethSign, .ethSend, .ethTopUp: "faceid"
        }
    }
    private var declineWord: String {
        switch ask { case .emoji: String(localized: "They don't"); default: String(localized: "Decline") }
    }
}
