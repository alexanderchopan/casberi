import Foundation
import Network
import Observation

/// Live network state — the Connection tile states it, the detail watches it
/// change. NWPathMonitor is the system's own answer; nothing is polled.
@Observable
final class NetMonitor {
    static let shared = NetMonitor()

    private let monitor = NWPathMonitor()
    private(set) var status = "Checking"
    private(set) var isExpensive = false
    private(set) var isConstrained = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status: String
            if path.status != .satisfied { status = "Offline" }
            else if path.usesInterfaceType(.wifi) { status = "Wi-Fi" }
            else if path.usesInterfaceType(.cellular) { status = "Cellular" }
            else if path.usesInterfaceType(.wiredEthernet) { status = "Wired" }
            else { status = "Connected" }
            Task { @MainActor [weak self] in
                self?.status = status
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.casberi.netmonitor"))
    }
}
