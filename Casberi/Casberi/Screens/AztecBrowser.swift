import SwiftUI
import WebKit

/// **AN AZTEC APP IN CASBERI'S BROWSER (prd §1700 item 5).** The app's page in
/// a web view, with Aztec's content-script relay (`AztecEngine/relay.js`)
/// added at document start in an isolated script world the page cannot reach;
/// the relay's messages go to `AztecEngine`, which holds the session keys and
/// the wallet, and this view names the page's origin itself — the page cannot
/// claim one. Every connect, the emoji check and every transaction ask here,
/// one sheet at a time (item 6). Proved first in `tools/aztec-dapp-spike`.
@MainActor
final class AztecBrowserModel: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {

    enum Ask: Identifiable, Equatable {
        case connect(requestId: String, host: String)
        case emoji(sessionId: String, host: String, emoji: String)
        case send(id: Int, host: String, calls: [Call], fee: String)

        struct Call: Equatable { let name: String; let to: String; let isPublic: Bool }

        var id: String {
            switch self {
            case .connect(let r, _): "connect-\(r)"
            case .emoji(let s, _, _): "emoji-\(s)"
            case .send(let i, _, _, _): "send-\(i)"
            }
        }
    }

    static let relayWorld = WKContentWorld.world(name: "casberi")
    static let tabID = 1

    let start: URL
    let page: WKWebView
    @Published var ask: Ask?
    @Published var host: String
    @Published var failed: String?
    private var queue: [Ask] = []

    init(url: URL) {
        start = url
        host = url.host(percentEncoded: false) ?? ""
        let relay = (Bundle.main.url(forResource: "AztecEngine", withExtension: nil)?
            .appendingPathComponent("relay.js")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: relay, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.relayWorld))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // The app's site keeps its own storage, apart from the engine's origin.
        config.websiteDataStore = .default()
        page = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        page.isInspectable = true
        #endif
        super.init()
        controller.add(self, contentWorld: Self.relayWorld, name: "casberiRelay")
        page.navigationDelegate = self
    }

    /// Starts the engine first, so the relay's first message has somewhere to go.
    func open() async {
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

    func enqueue(_ next: Ask) {
        if ask == nil { ask = next } else { queue.append(next) }
    }

    /// The sheet has gone; the next ask, if any.
    func sheetGone() {
        guard ask == nil, !queue.isEmpty else { return }
        ask = queue.removeFirst()
    }

    func answer(_ ask: Ask, yes: Bool) async {
        if case .send = ask, yes {
            do { try await PrivateRootKey.unlock(reason: String(localized: "Approve this Aztec transaction")) } catch { return }
        }
        queue.removeAll { $0.id == ask.id }
        AztecEngine.shared.answer(ask, yes: yes)
        if self.ask?.id == ask.id { self.ask = nil }
    }
}

struct AztecBrowserView: View {
    @StateObject private var model: AztecBrowserModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL) { _model = StateObject(wrappedValue: AztecBrowserModel(url: url)) }

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
    let ask: AztecBrowserModel.Ask
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
                Text(verbatim: emoji).font(.system(size: 34)).frame(maxWidth: .infinity)
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
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private var acceptWord: LocalizedStringKey {
        switch ask { case .connect: "Connect"; case .emoji: "They match"; case .send: "Approve" }
    }
    private var declineWord: LocalizedStringKey {
        switch ask { case .connect: "Decline"; case .emoji: "They don't"; case .send: "Decline" }
    }
}
