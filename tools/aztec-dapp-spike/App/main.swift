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

func resource(_ name: String, _ ext: String) -> String {
    Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
}

/// Owns both web views and every message between them.
final class Shell: NSObject, WKScriptMessageHandler {
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

        for name in ["engineLog", "engineToTab", "engineEmoji", "engineApprove"] { engineController.add(self, name: name) }
        pageController.add(self, contentWorld: relayWorld, name: "casberiRelay")
        pageController.add(self, contentWorld: .page, name: "casberi") // the test page's own result line

        // The engine page: Casberi's, served from the app bundle on loopback, never an app's.
        // The app's page opens once the engine has loaded.
        log("{\"event\":\"open\",\"detail\":\"\(url.absoluteString)\"}")
        do {
            server = try EngineServer()
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
        case "engineApprove":
            // The real app raises a sheet: who asks, what it does, what goes public.
            // The spike approves on the testnet and logs what it was asked.
            log("{\"event\":\"approve\",\"detail\":\(body)}")
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = obj["id"] as? Int {
                engine.evaluateJavaScript("casberiEngine.answerApproval(\(id), true)")
            }
        case "engineEmoji":
            log("{\"event\":\"nativeEmoji\",\"detail\":\(body)}")
        default:
            log(body)
        }
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

@main
struct AztecDappSpike: App {
    let shell = Shell(url: URL(string: UserDefaults.standard.string(forKey: "url") ?? "http://localhost:8779/ios.html?auto=send")!)
    var body: some Scene {
        WindowGroup { Browser(shell: shell).ignoresSafeArea() }
    }
}
