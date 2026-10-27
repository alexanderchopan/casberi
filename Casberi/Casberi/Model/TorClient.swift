import Foundation
import Network
import Observation
#if canImport(TorShim)
import TorShim
import UIKit
#endif

/// **TOR, IN THE APP (prd §1495, §1546).** tor runs on a thread of its own and
/// answers on a SOCKS port on 127.0.0.1. The app owns its control socket, so
/// tor stops when the app does and needs no password. This file polls it: how
/// far it has connected and which port it listens on, then, for as long as it
/// runs, whether it has a working circuit (`TorHealth`). It renews circuits
/// when the app comes back after `TorHealth.awayBeforeRenew`, resets tor's
/// connections when the network changes or a circuit stays lost, and, if tor
/// exits, lets the next wallet request run it again (`TorHealth.maxRuns`).
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
    static let connectWait = TorHealth.connectWait
    /// Zerion over Tor, measured (see above).
    static let requestTimeout: TimeInterval = 60

    private let lock = NSLock()
    /// A run of tor is going: set by `start`, cleared when `tor_run_main`
    /// returns (`ended`), so the next request runs it again.
    private var started = false
    /// Runs begun in this process, and the current one's number; a watch
    /// thread from an ended run publishes nothing.
    private var runs = 0
    private var socksPort: UInt16?
    /// The current run reached 100% and read its port; a reset waits for it.
    private var connected = false
    private var sessions: [String: URLSession] = [:]
    private var control: Int32 = -1
    private var startedAt = Date()
    private var awayAt: Date?
    private var observing = false
    private var path = TorHealth.PathWatch()
    private var pathMonitor: NWPathMonitor?
    /// One command and its reply at a time on the control socket: the watch,
    /// a foreground renew and a network reset share it.
    private let controlLock = NSLock()

    /// Nothing starts here: the first wallet request does (`session`), so a
    /// person with no wallet never runs Tor.
    private init() {}

    /// Starts tor if no run is going; every later call is free. After a run
    /// ends it starts the next, up to `TorHealth.maxRuns` in one process.
    func start() {
        #if canImport(TorShim)
        lock.lock()
        guard !started, TorHealth.mayStart(runs: runs) else { lock.unlock(); return }
        started = true
        runs += 1
        let run = runs
        startedAt = Date()
        lock.unlock()
        TorStatus.publish(.connecting(0))
        observe()

        guard let dir = Self.dataDirectory() else {
            ended(run: run); return
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
        let fd = tor_main_configuration_setup_control_socket(config)
        if fd >= 0 {
            // A write after tor exits is EPIPE, never a SIGPIPE that kills the app.
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        lock.lock()
        control = fd
        lock.unlock()

        let count = args.count
        let thread = Thread { [weak self] in
            let code = tor_run_main(config)
            NSLog("tor: run %ld exited %d", run, code)
            // Closes tor's end of the control socket; the watch closes ours.
            tor_main_configuration_free(config)
            for i in 0..<count { free(argv[i]) }
            argv.deallocate()
            self?.ended(run: run)
        }
        thread.name = "tor"
        thread.stackSize = 1 << 20
        thread.start()

        let poll = Thread { [weak self] in self?.watch(fd: fd, run: run) }
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
        // No run going after `start`: tor used its runs in this process
        // (`TorHealth.maxRuns`), an outage until the app is opened again.
        guard running() else { return nil }
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

    /// A fresh circuit for a request an exit refused or a circuit dropped:
    /// same wallet, another key — one a minute, so a burst of failed reads
    /// shares one new circuit rather than building one each.
    func retrySession(isolation key: String) async -> URLSession? {
        await session(isolation: key + "#retry-\(Int(Date().timeIntervalSince1970 / 60))")
    }

    /// A run ended (`tor_run_main` returned): nothing points at its port any
    /// more, and the next request starts the next run (prd §1546).
    private func ended(run: Int) {
        lock.lock()
        let dropped = Array(sessions.values)
        sessions = [:]
        socksPort = nil
        connected = false
        control = -1
        started = false
        let again = TorHealth.mayStart(runs: runs)
        lock.unlock()
        Self.retire(dropped)
        NSLog("tor: run %ld ended · %@", run,
              again ? "the next wallet request runs it again" : "no more runs in this process")
        TorStatus.publish(.failed)
    }

    private func running() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    private func isCurrent(_ run: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return started && runs == run
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
    /// Then, for as long as the run lasts, asks every `TorHealth.pollEvery`
    /// whether tor has a working circuit and publishes what it says (prd
    /// §1546). Closing our end of the socket when the watch ends stops tor if
    /// it still runs (an owning controller), so a run is never left unwatched.
    private func watch(fd: Int32, run: Int) {
        defer { closeControl(fd) }
        guard fd >= 0 else { publish(.failed, run: run); return }
        var failedOnce = false
        while true {
            guard let reply = command(fd, "GETINFO status/bootstrap-phase") else {
                publish(.failed, run: run); return
            }
            let progress = Self.progress(in: reply) ?? 0
            if progress >= 100 { break }
            if !failedOnce, Date().timeIntervalSince(startedAt) > Self.connectWait {
                failedOnce = true
                publish(.failed, run: run)
            } else if !failedOnce {
                publish(.connecting(progress), run: run)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let reply = command(fd, "GETINFO net/listeners/socks"),
              let port = Self.socksPort(in: reply) else {
            publish(.failed, run: run); return
        }
        let seconds = Date().timeIntervalSince(startedAt)
        NSLog("tor: run %ld connected in %.1fs, socks %d, %@", run, seconds, port, Self.version)
        setPort(port, run: run)
        publish(.ready(seconds: seconds), run: run)

        var health = TorHealth.Watch(connectedIn: seconds)
        var last = TorState.ready(seconds: seconds)
        while isCurrent(run) {
            Thread.sleep(forTimeInterval: TorHealth.pollEvery)
            guard let reply = command(fd, TorHealth.healthQuery) else { return }
            let lostBefore = health.lostSince
            guard let noted = health.note(TorHealth.reading(in: reply), at: Date()) else { continue }
            let state = noted.state
            if state != last {
                if case .ready = state, let lostBefore {
                    NSLog("tor: run %ld has a circuit again after %.1fs", run, Date().timeIntervalSince(lostBefore))
                } else if case .ready = last {
                    NSLog("tor: run %ld lost its circuits (%@)", run, reply.replacingOccurrences(of: "\r\n", with: " "))
                }
                last = state
            }
            if noted.act == .resetNetwork { resetNetwork(why: "no circuit for \(Int(TorHealth.resetAfter))s") }
            // A reset that could not read the new port is read again here.
            lock.lock()
            let portless = socksPort == nil
            lock.unlock()
            if portless, let reply = command(fd, "GETINFO net/listeners/socks"),
               let port = Self.socksPort(in: reply) {
                setPort(port, run: run)
            }
            publish(state, run: run)
        }
    }

    /// The current run's port; a watch or a reset from an ended run writes
    /// nothing.
    private func setPort(_ port: UInt16, run: Int) {
        lock.lock(); defer { lock.unlock() }
        guard started, runs == run else { return }
        socksPort = port
        connected = true
    }

    private func publish(_ state: TorState, run: Int) {
        guard isCurrent(run) else { return }
        TorStatus.publish(state)
    }

    // MARK: - Away, back, and another network

    /// Registered with the first run, for the life of the process.
    private func observe() {
        #if canImport(TorShim)
        lock.lock()
        guard !observing else { lock.unlock(); return }
        observing = true
        lock.unlock()
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.wentAway() }
        _ = center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.cameBack() }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in self?.network(TorClient.signature(path)) }
        monitor.start(queue: DispatchQueue(label: "tor-path"))
        lock.lock()
        pathMonitor = monitor
        lock.unlock()
        #endif
    }

    private func wentAway() {
        lock.lock(); awayAt = Date(); lock.unlock()
    }

    /// iOS suspended the tor thread while the app was away, and tor keeps
    /// believing in circuits whose connections may be gone (see `TorHealth`).
    /// Back after `awayBeforeRenew`, the sessions go, so no request reuses a
    /// kept-alive stream on an old circuit, and tor is told to build new ones
    /// (`SIGNAL NEWNYM`) and that it is in use (`SIGNAL ACTIVE`). Runs on
    /// `willEnterForeground`, before the activation's reads.
    private func cameBack() {
        lock.lock()
        let away = awayAt.map { Date().timeIntervalSince($0) }
        awayAt = nil
        let running = started && socksPort != nil
        lock.unlock()
        guard running, TorHealth.onForeground(away: away) == .renew else { return }
        dropSessions()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let fd = self.controlSocket() else { return }
            _ = self.command(fd, "SIGNAL ACTIVE")
            _ = self.command(fd, "SIGNAL NEWNYM")
            let health = self.command(fd, TorHealth.healthQuery).flatMap(TorHealth.reading(in:))
            NSLog("tor: back after %.0fs · new circuits asked · %@", away ?? 0,
                  health.map { $0.live ? "tor says live" : "tor says no circuit" } ?? "no answer")
        }
    }

    /// Another network (Wi-Fi to cellular, back online): tor's connections
    /// left by an interface that may be gone.
    private func network(_ signature: String?) {
        lock.lock()
        let moved = path.moved(to: signature)
        lock.unlock()
        guard moved else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.resetNetwork(why: "the network changed")
        }
    }

    /// The interface a satisfied path prefers and its gateways; nil while
    /// offline. Another Wi-Fi keeps the name `en0` and, almost always,
    /// changes the gateway; cellular coming and going beside Wi-Fi changes
    /// neither.
    private static func signature(_ path: NWPath) -> String? {
        guard path.status == .satisfied, let first = path.availableInterfaces.first else { return nil }
        return ([first.name] + path.gateways.map { "\($0)" }.sorted()).joined(separator: " ")
    }

    /// Closes every connection tor holds and opens them again: `DisableNetwork`
    /// marks every non-control connection closed, guards and SOCKS listener
    /// included, and reopens the listener on a NEW port (measured, tor
    /// 0.4.9.11: 42369, then 38353), so the port is read again and requests
    /// wait in `session` until it is. `NEWNYM` alone keeps the connections to
    /// the guards, which are what a changed network kills.
    private func resetNetwork(why: String) {
        lock.lock()
        let run = runs
        // Not while bootstrapping: tor is already making its first
        // connections, and a reset would start them over.
        let fd = started && connected ? control : -1
        if fd >= 0 { socksPort = nil }
        lock.unlock()
        guard fd >= 0 else { return }
        dropSessions()
        let start = Date()
        _ = command(fd, "SETCONF DisableNetwork=1")
        _ = command(fd, "SETCONF DisableNetwork=0")
        _ = command(fd, "SIGNAL ACTIVE")
        guard let reply = command(fd, "GETINFO net/listeners/socks"),
              let port = Self.socksPort(in: reply) else {
            NSLog("tor: run %ld reset (%@) · no port yet", run, why)
            return
        }
        setPort(port, run: run)
        NSLog("tor: run %ld reset (%@) in %.1fs · socks %d", run, why, Date().timeIntervalSince(start), port)
    }

    private func dropSessions() {
        lock.lock()
        let dropped = Array(sessions.values)
        sessions = [:]
        lock.unlock()
        Self.retire(dropped)
    }

    /// Cancels what a dropped session is running, and invalidates it only
    /// once no caller can still hold it: `session` hands one to a caller that
    /// makes its task on the next line, and a task made on an invalidated
    /// session raises.
    private static func retire(_ dropped: [URLSession]) {
        guard !dropped.isEmpty else { return }
        for s in dropped { s.getAllTasks { $0.forEach { $0.cancel() } } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout * 2) {
            dropped.forEach { $0.finishTasksAndInvalidate() }
        }
    }

    private func controlSocket() -> Int32? {
        lock.lock(); defer { lock.unlock() }
        return started && control >= 0 ? control : nil
    }

    /// The watch's last act: no command reaches the socket once it is closed,
    /// so a number the system hands out again is never written to.
    private func closeControl(_ fd: Int32) {
        guard fd >= 0 else { return }
        controlLock.lock(); defer { controlLock.unlock() }
        lock.lock()
        if control == fd { control = -1 }
        lock.unlock()
        close(fd)
    }

    /// One command, and its reply up to the closing `250 OK` (or an error
    /// line); nil once `fd` is not the current run's open socket.
    private func command(_ fd: Int32, _ line: String) -> String? {
        controlLock.lock(); defer { controlLock.unlock() }
        lock.lock()
        let open = fd >= 0 && control == fd
        lock.unlock()
        guard open else { return nil }
        // A signal (EINTR) or a short write is not tor gone: a nil here ends
        // the watch, which closes the socket and so stops tor.
        let bytes = Array((line + "\r\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress! + sent, $0.count - sent) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return nil }
            sent += n
        }
        var reply = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
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

/// What the Wallet draws about Tor, observed on the main actor. It follows
/// tor for the life of the run (prd §1546), so "On" is tor's answer of the
/// last few seconds, not the first connect's.
@MainActor @Observable
final class TorStatus {
    typealias State = TorState

    static let shared = TorStatus()
    private(set) var state: State = TorRoute.available ? .idle : .unavailable
    @ObservationIgnored private var applied = 0

    /// Numbered where it is called: publishes come from the watch, a run's
    /// end and `start` on different threads, and the main actor need not run
    /// their tasks in that order, so an older state never lands over a newer
    /// one. The watch publishes every poll; only a change reaches the views.
    nonisolated static func publish(_ state: State) {
        let n = torPublishOrder.next()
        Task { @MainActor in
            guard n > shared.applied else { return }
            shared.applied = n
            guard shared.state != state else { return }
            shared.state = state
        }
    }
}

private let torPublishOrder = TorPublishOrder()

private final class TorPublishOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
}
