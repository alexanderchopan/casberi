import Foundation

/// What the Wallet is told about Tor (`TorStatus.State`). At file scope so
/// `tor-health-selftest.sh` compiles the rule below without SwiftUI.
enum TorState: Equatable, Sendable {
    /// This build has no Tor (the Mac).
    case unavailable
    case idle
    /// Bootstrapping at this percent; `connecting(100)` is a connected tor
    /// with no working circuit, building one (prd §1546).
    case connecting(Int)
    case ready(seconds: Double)
    /// Could not connect within `TorHealth.connectWait`, lost its circuits
    /// for that long, or tor stopped.
    case failed
}

/// **TOR, WATCHED AFTER IT CONNECTS (prd §1546).** The pure half of
/// `TorClient`: what tor's answers mean, what the Wallet is told, and when
/// the client renews circuits, resets tor's connections or runs tor again.
///
/// Read off tor 0.4.9.11's source: `status/circuit-established` is 1 once tor
/// has built a circuit and goes 0 when tor decides its circuits no longer
/// work; `network-liveness` goes up on any cell received and down when a
/// circuit times out with no cell since it launched. Neither moves while the
/// app is suspended: tor drops its circuits on resume only when the wall clock
/// jumped against the monotonic one (the device slept), or after an hour, so
/// a suspension of minutes with the device awake leaves tor sure of circuits
/// that may be dead. The foreground renew is for that.
enum TorHealth {

    /// How long a request waits for Tor before it is an outage, and how long
    /// a connected tor may go without a circuit before the Wallet is told it
    /// can't connect.
    static let connectWait: TimeInterval = 45
    /// Once connected, tor is asked how it is this often (a local socket,
    /// answered from memory).
    static let pollEvery: TimeInterval = 5
    /// A connected tor this long without a working circuit has its
    /// connections closed and opened again, and again every `resetEvery`
    /// while the spell lasts: tor retries on its own, but not off a network
    /// it no longer has.
    static let resetAfter: TimeInterval = 20
    static let resetEvery: TimeInterval = 120
    /// Away this long, the app renews circuits on its return: shorter than
    /// any NAT's idle timeout we could rely on, longer than a glance at
    /// another app.
    static let awayBeforeRenew: TimeInterval = 30
    /// Runs of tor in one process. tor's embedding API warns that a second
    /// `tor_run_main` "may crash or behave strangely" (BUG 23847), so a tor
    /// that keeps exiting is an outage until the app is opened again, not a
    /// loop.
    static let maxRuns = 3

    /// The question the client asks every `pollEvery`.
    static let healthQuery = "GETINFO status/circuit-established network-liveness"

    /// What tor says of itself.
    struct Reading: Equatable, Sendable {
        var circuits: Bool
        var networkUp: Bool
        var live: Bool { circuits && networkUp }
    }

    /// The reading in a reply to `healthQuery`, or nil for any reply that is
    /// not both keys answered (`552 Unrecognized key`, a cut-off read).
    static func reading(in reply: String) -> Reading? {
        guard let circuits = value("status/circuit-established", in: reply),
              let network = value("network-liveness", in: reply),
              ["0", "1"].contains(circuits), ["up", "down"].contains(network) else { return nil }
        return Reading(circuits: circuits == "1", networkUp: network == "up")
    }

    /// `250-key=value` or `250 key=value`, measured from tor 0.4.9.11:
    /// `250-status/circuit-established=1\r\n250-network-liveness=up\r\n250 OK\r\n`.
    private static func value(_ key: String, in reply: String) -> String? {
        for line in reply.components(separatedBy: "\r\n") {
            guard line.hasPrefix("250-") || line.hasPrefix("250 ") else { continue }
            let pair = line.dropFirst(4)
            guard pair.hasPrefix(key + "=") else { continue }
            return String(pair.dropFirst(key.count + 1))
        }
        return nil
    }

    /// One connected run, watched: each reading gives the state to publish
    /// and whether to reset tor's connections.
    struct Watch: Sendable {
        enum Act: Equatable, Sendable { case none, resetNetwork }

        let connectedIn: Double
        private(set) var lostSince: Date?
        private var lastReset: Date?

        init(connectedIn: Double) { self.connectedIn = connectedIn }

        /// nil when the reading could not be read: an answer the client does
        /// not understand changes nothing.
        mutating func note(_ reading: Reading?, at now: Date) -> (state: TorState, act: Act)? {
            guard let reading else { return nil }
            if reading.live {
                lostSince = nil
                lastReset = nil
                return (.ready(seconds: connectedIn), .none)
            }
            let since = lostSince ?? now
            lostSince = since
            let lost = now.timeIntervalSince(since)
            var act = Act.none
            if lost >= TorHealth.resetAfter,
               lastReset.map({ now.timeIntervalSince($0) >= TorHealth.resetEvery }) ?? true {
                lastReset = now
                act = .resetNetwork
            }
            return (lost >= TorHealth.connectWait ? .failed : .connecting(100), act)
        }
    }

    /// What a return to the foreground does.
    enum Refresh: Equatable, Sendable { case none, renew }

    static func onForeground(away: TimeInterval?) -> Refresh {
        guard let away else { return .none }
        return away >= awayBeforeRenew ? .renew : .none
    }

    /// The network the phone is on, as a signature (`TorClient.signature`):
    /// the first one sets the baseline; a later different one, offline
    /// excepted, means tor's connections left by an interface that may be
    /// gone, and are reset.
    struct PathWatch: Sendable {
        private var seen = false
        private var last: String?

        /// `signature` is nil while offline.
        mutating func moved(to signature: String?) -> Bool {
            defer { seen = true; last = signature }
            guard seen, let signature else { return false }
            return signature != last
        }
    }

    /// Whether tor may run again after `runs` runs began in this process.
    static func mayStart(runs: Int) -> Bool { runs < maxRuns }
}
