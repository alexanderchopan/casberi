import Darwin
import SwiftUI
import WebKit

/// A throwaway app that asks one question: can this iPhone, alone, run a
/// private Aztec account? Aztec's PXE runs in the web view; its proofs run in
/// Aztec's native iOS prover here; its key is in the Secure Enclave. Testnet
/// only, never shipped. Launch with `-prover wasm` to compare bb.js's own
/// WebAssembly prover, and `-autorun YES` to run every step at launch (`-autorun open`: only
/// open the wallet).
@main
struct AztecSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeWebView()
                .ignoresSafeArea()
                .background(Color.black)
                .preferredColorScheme(.dark)
        }
    }
}

struct SpikeWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.isInspectable = true
        do {
            let server = try LocalServer()
            Spike.server = server
            server.start {
                var query: [String] = []
                #if targetEnvironment(simulator)
                query.append("device=simulator")
                #endif
                if UserDefaults.standard.string(forKey: "prover") == "wasm" { query.append("prover=wasm") }
                if let run = UserDefaults.standard.string(forKey: "autorun") { query.append("autorun=" + (run == "open" ? "open" : "all")) }
                let url = URL(string: "http://127.0.0.1:\(LocalServer.port)/index.html" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))!
                Spike.log("loading \(url.absoluteString) · key in Secure Enclave: \(EnclaveKey.inEnclave)")
                web.load(URLRequest(url: url))
            }
        } catch {
            Spike.log("could not start the local server: \(error)")
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Console lines (read them with `devicectl … --console`) and the result file.
enum Spike {
    nonisolated(unsafe) static var server: LocalServer?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var proverTotals: [String: (count: Int, seconds: Double)] = [:]

    static func log(_ line: String) {
        print("[spike] \(line)")
        fflush(stdout)
    }

    static func recordProver(name: String, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        let t = proverTotals[name] ?? (0, 0)
        proverTotals[name] = (t.count + 1, t.seconds + seconds)
    }

    static func result(_ json: String) {
        lock.lock()
        let totals = proverTotals.sorted { $0.value.seconds > $1.value.seconds }.prefix(8)
            .map { "\($0.key) ×\($0.value.count) \(String(format: "%.1f", $0.value.seconds)) s" }.joined(separator: " · ")
        lock.unlock()
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? Memory.model()
        log("result \(device) \(json)")
        log("prover time by command: \(totals)")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? Data("{\"device\":\"\(device)\",\"run\":\(json)}\n".utf8).write(to: documents.appendingPathComponent("results.json"))
    }
}

enum Memory {
    /// The app's footprint as iOS counts it against its limit, and what is left.
    static func now() -> (footprint: UInt64, available: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return (kr == KERN_SUCCESS ? info.phys_footprint : 0, UInt64(os_proc_available_memory()))
    }

    static func model() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
