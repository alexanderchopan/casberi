// Casberi's in-app browser as an Aztec wallet: a THROWAWAY spike (never shipped).
//
// Two web views, the way a browser extension is two halves:
//   - the APP's page, with Aztec's content-script relay (relay.js) added at
//     document start in an isolated script world, "casberi", that the app's
//     JavaScript cannot reach;
//   - Casberi's own hidden ENGINE view (engine.html + engine.js): the key
//     exchange, the session keys and the wallet. No app page ever loads it.
// This shell passes relay messages between them and is the one that says which
// page (tab) and origin a message came from — the page cannot claim one.
// Logs: NSLog `aztecDapp|` and Documents/aztec-dapp.log.
//
//   -url <address>   the app to open (default: the local handshake page)
import SwiftUI
import WebKit

let relayWorld = WKContentWorld.world(name: "casberi")
let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("aztec-dapp.log")

func log(_ line: String) {
    NSLog("aztecDapp| %@", line)
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    else { try? data.write(to: logURL) }
}

/// Where the spike's web files are: the app's resources, or their `Bundle`
/// folder in the Xcode-built device app.
let resourceRoot: URL = {
    let base = Bundle.main.resourceURL!
    let folder = base.appendingPathComponent("Bundle")
    return FileManager.default.fileExists(atPath: folder.path) ? folder : base
}()

func resource(_ name: String, _ ext: String) -> String {
    (try? String(contentsOf: resourceRoot.appendingPathComponent("\(name).\(ext)"), encoding: .utf8)) ?? ""
}

/// The test app's page: bundled and served by the app on a device (no Mac
/// needed), or the Mac's dev server for the simulator.
let bundledDapp = FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent("Dapp/ios.html").path)
let defaultURL = bundledDapp ? "http://127.0.0.1:\(EngineServer.dappPort)/ios.html?auto=send" : "http://localhost:8779/ios.html?auto=send"
var dappServer: EngineServer?

/// What the person is asked: to connect a site, or to approve a transaction.
struct Ask: Identifiable {
    enum Kind { case connect, send }
    let id: String
    let kind: Kind
    let host: String
    let calls: [(name: String, to: String, type: String)]
    let fee: String
}

/// Owns both web views and every message between them, and what the person is asked.
final class Shell: NSObject, WKScriptMessageHandler, ObservableObject {
    /// The sheet on screen; the rest wait in `queue`, one at a time, in order.
    @Published var ask: Ask?
    @Published var emoji: String?
    private var queue: [Ask] = []
    /// `-autoApprove YES`: say yes after a moment, so a test run needs no hand.
    let autoApprove = UserDefaults.standard.bool(forKey: "autoApprove")
    let engine: WKWebView
    let page: WKWebView
    let tabID = 1
    var server: EngineServer?

    init(url: URL) {
        try? FileManager.default.removeItem(at: logURL)
        let engineController = WKUserContentController()
        let engineConfig = WKWebViewConfiguration()
        engineConfig.userContentController = engineController
        engine = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: engineConfig)
        engine.isInspectable = true

        let pageController = WKUserContentController()
        pageController.addUserScript(WKUserScript(source: resource("relay", "js"), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: relayWorld))
        let pageConfig = WKWebViewConfiguration()
        pageConfig.userContentController = pageController
        page = WKWebView(frame: .zero, configuration: pageConfig)
        page.isInspectable = true
        super.init()

        for name in ["engineLog", "engineToTab", "engineEmoji", "engineApprove", "engineConnect", "engineNeedsRoot"] { engineController.add(self, name: name) }
        pageController.add(self, contentWorld: relayWorld, name: "casberiRelay")
        pageController.add(self, contentWorld: .page, name: "casberi") // the test page's own result line

        // The engine page: Casberi's, served from the app bundle on loopback, never an app's.
        // The app's page opens once the engine has loaded.
        log("{\"event\":\"open\",\"detail\":\"\(url.absoluteString)\"}")
        do {
            server = try EngineServer()
            if bundledDapp {
                dappServer = try EngineServer(root: resourceRoot.appendingPathComponent("Dapp"), port: EngineServer.dappPort)
                dappServer?.start {}
            }
            server?.start { [weak self] in
                self?.engine.load(URLRequest(url: URL(string: "http://127.0.0.1:\(EngineServer.port)/")!))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.page.load(URLRequest(url: url)) }
            }
        } catch {
            log("{\"event\":\"serverFailed\",\"detail\":\"\(error)\"}")
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = "\(message.body)"
        switch message.name {
        case "casberiRelay":
            // Relay → engine. The origin is the shell's reading of the page, not the page's word.
            guard message.world == relayWorld, message.frameInfo.isMainFrame else { return }
            let url = page.url?.absoluteString ?? ""
            engine.evaluateJavaScript("casberiEngine.fromContent(\(jsString(body)), \(tabID), \(jsString(url)))")
        case "engineToTab":
            // Engine → relay, into the isolated world only.
            guard let data = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let inner = obj["message"],
                  let innerData = try? JSONSerialization.data(withJSONObject: inner),
                  let innerJSON = String(data: innerData, encoding: .utf8) else { return }
            page.evaluateJavaScript("window.__casberiDeliver(\(jsString(innerJSON)))", in: nil, in: relayWorld) { _ in }
        case "engineConnect", "engineApprove":
            log("{\"event\":\"\(message.name)\",\"detail\":\(body)}")
            guard let data = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let host = URL(string: obj["origin"] as? String ?? "")?.host(percentEncoded: false) ?? "This site"
            let next: Ask
            if message.name == "engineConnect" {
                next = Ask(id: obj["requestId"] as? String ?? "", kind: .connect, host: host, calls: [], fee: "")
            } else {
                let calls = (obj["calls"] as? [[String: Any]] ?? []).map {
                    (name: $0["name"] as? String ?? "?", to: $0["to"] as? String ?? "", type: $0["type"] as? String ?? "")
                }
                next = Ask(id: "\(obj["id"] as? Int ?? 0)", kind: .send, host: host, calls: calls, fee: obj["fee"] as? String ?? "")
            }
            enqueue(next)
        case "engineNeedsRoot":
            // The engine derives the account from the root; only the engine view sees it.
            guard let root = AztecRoot.ensure() else { return }
            log("{\"event\":\"root\",\"detail\":{\"made\":\(root.made)}}")
            engine.evaluateJavaScript("casberiEngine.setRoot(\(jsString(root.hex)))")
        case "engineEmoji":
            log("{\"event\":\"nativeEmoji\",\"detail\":\(body)}")
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                emoji = obj["emoji"] as? String
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.emoji = nil }
            }
        default:
            log(body)
        }
    }

    private func enqueue(_ next: Ask) {
        if ask == nil { ask = next } else { queue.append(next) }
    }

    /// The sheet has gone; show the next ask, if any.
    func sheetDismissed() {
        guard ask == nil, !queue.isEmpty else { return }
        ask = queue.removeFirst()
    }

    func answer(_ ask: Ask, yes: Bool) {
        queue.removeAll { $0.id == ask.id }
        log("{\"event\":\"answer\",\"detail\":{\"kind\":\"\(ask.kind)\",\"yes\":\(yes)}}")
        switch ask.kind {
        case .connect: engine.evaluateJavaScript("casberiEngine.answerConnect(\(jsString(ask.id)), \(yes))")
        case .send: engine.evaluateJavaScript("casberiEngine.answerApproval(\(ask.id), \(yes))")
        }
        if self.ask?.id == ask.id { self.ask = nil }
    }

    private func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let arr = String(data: data, encoding: .utf8)!
        return String(arr.dropFirst().dropLast())
    }
}

struct Browser: UIViewRepresentable {
    let shell: Shell
    func makeUIView(context: Context) -> UIView {
        let root = UIView()
        shell.engine.isHidden = true
        root.addSubview(shell.engine) // in the hierarchy so its JavaScript keeps running
        shell.page.frame = root.bounds
        shell.page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(shell.page)
        return root
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// The sheet: who asks, what it does, what stays private, who pays. Two buttons.
struct AskSheet: View {
    let ask: Ask
    let answer: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(ask.kind == .connect ? "Connect \(ask.host)?" : "\(ask.host) wants to send")
                .font(.title2.weight(.semibold))
            if ask.kind == .connect {
                Text("It will see your Aztec account's address. It can ask to send; Casberi asks you each time.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ask.calls.enumerated()), id: \.offset) { _, call in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: call.type == "public" ? "eye" : "lock.fill")
                                .foregroundStyle(call.type == "public" ? Color.orange : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(call.name.replacingOccurrences(of: "_", with: " ")).font(.body.weight(.medium))
                                Text("\(call.type == "public" ? "Public" : "Private") · \(call.to)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text(ask.fee).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Decline") { answer(false) }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                Button(ask.kind == .connect ? "Connect" : "Approve") { answer(true) }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

struct Root: View {
    @ObservedObject var shell: Shell
    var body: some View {
        Browser(shell: shell)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                if let emoji = shell.emoji {
                    VStack(spacing: 4) {
                        Text("Check the site shows").font(.footnote).foregroundStyle(.secondary)
                        Text(emoji).font(.title2)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .onAppear { log("{\"event\":\"emojiShown\"}") }
                }
            }
            .sheet(item: $shell.ask, onDismiss: { shell.sheetDismissed() }) { ask in
                AskSheet(ask: ask) { shell.answer(ask, yes: $0) }
                    .task {
                        log("{\"event\":\"sheetShown\",\"detail\":\"\(ask.kind)\"}")
                        // -autoApprove: say yes once the sheet has been on screen a moment.
                        guard shell.autoApprove else { return }
                        try? await Task.sleep(for: .seconds(2.5))
                        if shell.ask?.id == ask.id { shell.answer(ask, yes: true) }
                    }
            }
    }
}

@main
struct AztecDappSpike: App {
    @StateObject var shell = Shell(url: URL(string: UserDefaults.standard.string(forKey: "url") ?? defaultURL)!)
    var body: some Scene {
        WindowGroup { Root(shell: shell) }
    }
}
