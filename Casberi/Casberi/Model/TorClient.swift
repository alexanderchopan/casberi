import Foundation
import Network
import Observation
#if canImport(TorShim)
import TorShim
#endif

/// **TOR, IN THE APP (prd §1495).** tor runs on a thread of its own for the life
/// of the process — tor's embedding API offers no clean restart — and answers
/// on a SOCKS port on 127.0.0.1. The app owns its control socket, so tor stops
/// when the app does and needs no password; this file asks it two things only,
/// how far it has connected and which port it listens on, by polling.
///
/// A wallet request asks `session(isolation:)` for the URLSession of its
/// circuit and waits for Tor to connect, up to `connectWait`; an answer of nil
/// is an outage to its caller — the wallet stands on its last reading, stamped
/// (prd §825) — and never a direct read. `allowFailover` is off on every proxy.
///
/// Measured 2026-10-24 from the Mac (tor 0.4.9.14): the bundlers, every public
/// node the account uses, Alchemy, Safe's transaction service, mempool.space,
/// web3.bio and Morpho answer over Tor in ~1–2s; Zerion in 6–45s for a heavy
/// wallet, so a Tor session waits 60s, not the funnel's 15. The hosts that
/// refused every exit are `NetworkReach`'s `refusesTor`.
final class TorClient: @unchecked Sendable {

    static let shared = TorClient()

    /// How long a request waits for Tor to connect before it is an outage.
    static let connectWait: TimeInterval = 45
    /// Zerion over Tor, measured (see above).
    static let requestTimeout: TimeInterval = 60

    private let lock = NSLock()
    private var started = false
    private var socksPort: UInt16?
    private var sessions: [String: URLSession] = [:]
    private var control: Int32 = -1
    private var startedAt = Date()

    /// Nothing starts here: the first wallet request does (`session`), so a
    /// person with no wallet never runs Tor.
    private init() {}

    /// Starts tor once; every later call is free.
    func start() {
        #if canImport(TorShim)
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        startedAt = Date()
        lock.unlock()
        TorStatus.publish(.connecting(0))

        guard let dir = Self.dataDirectory() else {
            TorStatus.publish(.failed); return
        }
        let config = tor_main_configuration_new()
        var args = ["tor",
                    "--DataDirectory", dir,
                    "--SocksPort", "127.0.0.1:auto IsolateSOCKSAuth",
                    "--ClientOnly", "1",
                    "--AvoidDiskWrites", "1",
                    "--CookieAuthentication", "0",
                    // tor denies debugger attachment by default, which kills
                    // the app under Xcode and helps nobody on a phone.
                    "--DisableDebuggerAttachment", "0",
                    "--GeoIPFile", "", "--GeoIPv6File", ""]
        #if DEBUG
        // stderr never reaches the unified log; tor's own timeline lands
        // beside its data (`Tor/notice.log`, read from the simulator's
        // container).
        args += ["--Log", "notice file \(dir)/notice.log"]
        #else
        args += ["--Log", "err stderr"]
        #endif
        // tor keeps the pointer it is handed, never a copy, so argv lives as
        // long as tor does.
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: args.count + 1)
        for (i, arg) in args.enumerated() { argv[i] = strdup(arg) }
        argv[args.count] = nil
        tor_main_configuration_set_command_line(config, Int32(args.count), argv)
        control = tor_main_configuration_setup_control_socket(config)

        let count = args.count
        let thread = Thread {
            let code = tor_run_main(config)
            NSLog("tor: exited %d", code)
            tor_main_configuration_free(config)
            for i in 0..<count { free(argv[i]) }
            argv.deallocate()
            TorStatus.publish(.failed)
        }
        thread.name = "tor"
        thread.stackSize = 1 << 20
        thread.start()

        let fd = control
        let poll = Thread { [weak self] in self?.watch(fd: fd) }
        poll.name = "tor-control"
        poll.start()
        #else
        TorStatus.publish(.unavailable)
        #endif
    }

    /// The session for one circuit, once Tor has connected; nil when this
    /// build has no Tor, or it did not connect within `connectWait`.
    func session(isolation key: String) async -> URLSession? {
        guard TorRoute.available else { return nil }
        start()
        // Polled, not awaited on a continuation: a task group waits for every
        // child before it returns, so a race against a timer held each request
        // for the whole connect (275s, measured on the first build).
        let deadline = Date().addingTimeInterval(Self.connectWait)
        while true {
            if let s = ready(key) { return s }
            guard Date() < deadline, !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// A fresh circuit for a request an exit refused: same wallet, another key.
    func retrySession(isolation key: String) async -> URLSession? {
        await session(isolation: key + "#retry-\(Int.random(in: 1...1_000_000))")
    }

    // MARK: - Sessions

    private func ready(_ key: String) -> URLSession? {
        lock.lock(); defer { lock.unlock() }
        guard let port = socksPort else { return nil }
        if let s = sessions[key] { return s }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.waitsForConnectivity = false
        // The SOCKS username picks the circuit (`IsolateSOCKSAuth`); it is a
        // hash, so the wallet's address never reaches tor's own memory twice.
        var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1",
                                                               port: NWEndpoint.Port(rawValue: port)!))
        proxy.applyCredential(username: Self.circuitName(key), password: "casberi")
        proxy.allowFailover = false
        config.proxyConfigurations = [proxy]
        #if DEBUG
        config.protocolClasses = [ChainReadsOff.self] + (config.protocolClasses ?? [])
        #endif
        let s = URLSession(configuration: config)
        sessions[key] = s
        return s
    }

    private static func circuitName(_ key: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 36)
    }

    // MARK: - Control socket

    /// Polls tor's bootstrap every half second until it is done, then reads
    /// the SOCKS port. A `connectWait` with no progress is a failure the
    /// Wallet states; polling goes on, so a late connection still lands.
    private func watch(fd: Int32) {
        guard fd >= 0 else { TorStatus.publish(.failed); return }
        var failedOnce = false
        while true {
            guard let reply = command(fd, "GETINFO status/bootstrap-phase") else {
                TorStatus.publish(.failed); return
            }
            let progress = Self.progress(in: reply) ?? 0
            if progress >= 100 { break }
            if !failedOnce, Date().timeIntervalSince(startedAt) > Self.connectWait {
                failedOnce = true
                TorStatus.publish(.failed)
            } else if !failedOnce {
                TorStatus.publish(.connecting(progress))
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let reply = command(fd, "GETINFO net/listeners/socks"),
              let port = Self.socksPort(in: reply) else {
            TorStatus.publish(.failed); return
        }
        let seconds = Date().timeIntervalSince(startedAt)
        NSLog("tor: connected in %.1fs, socks %d, %@", seconds, port, Self.version)
        lock.lock()
        socksPort = port
        lock.unlock()
        TorStatus.publish(.ready(seconds: seconds))
    }

    /// One command, and its reply up to the closing `250 OK` (or an error line).
    private func command(_ fd: Int32, _ line: String) -> String? {
        let bytes = Array((line + "\r\n").utf8)
        guard bytes.withUnsafeBufferPointer({ write(fd, $0.baseAddress, $0.count) }) == bytes.count
        else { return nil }
        var reply = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { return nil }
            reply += String(decoding: buffer[0..<n], as: UTF8.self)
            // Done at a whole final line: "250 OK" (a space after the code,
            // where every line before it has a dash), CRLF and all.
            guard reply.hasSuffix("\r\n") else { continue }
            let lines = reply.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            if let last = lines.last, last.count >= 4,
               last.dropFirst(3).first == " " { return reply }
        }
    }

    static func progress(in reply: String) -> Int? {
        guard let r = reply.range(of: #"PROGRESS=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(reply[r].dropFirst("PROGRESS=".count))
    }

    static func socksPort(in reply: String) -> UInt16? {
        guard let r = reply.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) else { return nil }
        return UInt16(reply[r].split(separator: ":").last ?? "")
    }

    static var version: String {
        #if canImport(TorShim)
        "tor " + String(cString: torshim_version())
        #else
        "no tor"
        #endif
    }

    /// Application Support/Tor, 0700 as tor insists, out of the backup: the
    /// cached consensus is what makes the next connect take seconds.
    private static func dataDirectory() -> String? {
        let fm = FileManager.default
        guard var url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tor", isDirectory: true) else { return nil }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch { return nil }
        return url.path
    }
}

/// What the Wallet draws about Tor, observed on the main actor.
@MainActor @Observable
final class TorStatus {
    enum State: Equatable {
        /// This build has no Tor (the Mac).
        case unavailable
        case idle
        case connecting(Int)
        case ready(seconds: Double)
        /// Could not connect within `TorClient.connectWait`, or tor stopped.
        case failed
    }

    static let shared = TorStatus()
    private(set) var state: State = TorRoute.available ? .idle : .unavailable

    nonisolated static func publish(_ state: State) {
        Task { @MainActor in
            // A late connection after a failure clears it; nothing else moves
            // a failure back to connecting.
            if shared.state == .failed, case .connecting = state { return }
            shared.state = state
        }
    }
}
