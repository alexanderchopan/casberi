import Foundation
#if targetEnvironment(macCatalyst)
import Network
import SwiftData

/// An MCP server, hosted by the Mac app, on loopback (2026-08-06).
///
/// `MCPTools` has held the three real tools since prd §34 and `MCPPairing`
/// has minted a real token — and none of it has ever been reachable, because
/// `transportReady` is false and the payload names a placeholder endpoint. The
/// blocker was always the same: the design called for a SERVER, and this
/// product's entire claim is that it doesn't have one ("no server, nothing
/// routes through us" — the sentence `NetworkReach` exists to make checkable).
/// So the feature sat waiting on the one thing it must never get.
///
/// The way out is that it was never a server this app needed — it was a
/// LISTENER. The Mac build is a real macOS process with a real corpus already
/// synced to it, and an external agent that wants to read a person's things
/// (Claude Desktop, Claude Code, Raycast, an editor) is running on that same
/// Mac. It doesn't need a rendezvous in the cloud; it needs a port on
/// localhost. Nothing is hosted, nothing is routed, nothing leaves the
/// machine, and the privacy claim is untouched — this is the app answering a
/// question asked from the same computer.
///
/// **Four rails, all load-bearing.**
///
/// 1. **Loopback only.** The listener is pinned to `127.0.0.1`, and a
///    connection whose peer is not loopback is dropped before a byte is read.
///    Two independent checks, because one of them is API behaviour and the
///    other is ours.
/// 2. **The pairing token is required.** Every request must carry
///    `Authorization: Bearer <token>`; `MCPPairing.reset()` invalidates it.
///    Loopback is not by itself an authorization — anything else on the Mac
///    can reach it, including a browser page.
/// 3. **Off by default, and started only by an explicit switch.** No listener
///    exists until somebody turns it on.
/// 4. **The WRITE still routes through consent.** `save_thing` lands an
///    approval-thing exactly as `MCPTools` always specified — an outside agent
///    cannot put anything in the corpus without a tap in the app. That was the
///    rail the 2026-07-06 strategy pivot explicitly kept, and it survives
///    unchanged here.
///
/// **UNMEASURED, and the honest state is stated rather than assumed.** This
/// has never been run against a real MCP client: it is written against the
/// spec's JSON-RPC shape, and nothing in a simulator can exercise it (the
/// whole thing compiles out anywhere but Catalyst). `MCPPairing.transportReady`
/// is therefore still FALSE — no pairing UI claims a wire exists — and the
/// only door is the Mac settings switch, which says plainly that it is
/// unproven. It also needs `com.apple.security.network.server` in the Catalyst
/// entitlements: that is a SANDBOX entitlement the app declares for itself,
/// not a portal capability, so it needs no profile change — but a sandboxed
/// app without it gets a listener that fails to start, which `lastError`
/// reports rather than swallowing.
@MainActor
final class MCPServer {

    static let shared = MCPServer()

    /// The default port. Above the registered range, unlikely to collide, and
    /// fixed rather than random so a client's config file stays valid across
    /// restarts.
    static let defaultPort: UInt16 = 8787

    private static let enabledKey = "mcp.server.enabled"
    private static let portKey = "mcp.server.port"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var port: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: portKey)
            guard stored > 0, stored <= 65_535 else { return defaultPort }
            return UInt16(stored)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: portKey) }
    }

    /// What a client puts in its config. The token rides the header, so this
    /// is the URL alone.
    static var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    private(set) var running = false
    /// Why it isn't running, when it should be. Surfaced rather than logged:
    /// a listener that failed to bind (the missing sandbox entitlement, a port
    /// already taken) looks identical from the outside to one nobody turned
    /// on, and those need different fixes.
    private(set) var lastError: String?

    private var listener: NWListener?
    /// The port the live listener actually bound. Kept so `start()` can tell a
    /// redundant call (same port, already up) from a real move to a new one.
    private var boundPort: UInt16?
    /// Set when a rebind is waiting for an in-flight cancellation to land —
    /// see `start()`.
    private var restartPending = false
    private let queue = DispatchQueue(label: "com.casberi.mcp.listener")

    private init() {}

    // MARK: - Lifecycle

    func startIfEnabled() {
        guard Self.isEnabled, !running else { return }
        start()
    }

    /// Bring the listener up, idempotently.
    ///
    /// **This used to `stop()` and rebind unconditionally, and that left the
    /// listener dead** (measured 2026-08-08, prd §340). `NWListener.cancel()`
    /// is ASYNCHRONOUS: the port is still held when the new bind runs a moment
    /// later, so the rebind fails with `NWError 48 — Address already in use`,
    /// and the app is left with NO listener while the switch still reads on.
    ///
    /// It was not a rare interleaving. Two call sites reach this in one launch
    /// (`RootShell`'s `startIfEnabled` and, on Mac, the settings toggle's own
    /// `onChange`), and a person flipping the switch off and on does it by
    /// hand. The symptom is the worst kind: the error names the port as taken,
    /// which reads as some OTHER program holding it, when it is us holding it
    /// against ourselves.
    ///
    /// So: already up on the right port is a no-op, and a genuine move to a
    /// different port waits for the cancellation to actually land before
    /// binding again, rather than racing it.
    func start() {
        if listener != nil, running, boundPort == Self.port { return }
        if listener != nil {
            restartPending = true
            stop()
            return
        }
        bind()
    }

    private func bind() {
        lastError = nil
        let parameters = NWParameters.tcp
        // Rail 1, first half: bind the listener itself to loopback, so the
        // port is never offered on any other interface even for the moment it
        // would take us to reject a peer.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: .init(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.running = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.running = false
                        // The sandbox refusal lands here. Named plainly
                        // because it is the one failure a person can't guess.
                        self?.lastError = error.localizedDescription
                    case .cancelled:
                        self?.running = false
                        // The other half of `start()`'s fix: a rebind waiting
                        // on this cancellation can now proceed, because the
                        // port is genuinely free only at this point.
                        if self?.restartPending == true {
                            self?.restartPending = false
                            self?.bind()
                        }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            self.boundPort = Self.port
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        boundPort = nil
        running = false
    }

    // MARK: - One connection

    private nonisolated func accept(_ connection: NWConnection) {
        // Rail 1, second half: refuse anything that isn't loopback. The bind
        // above should make this unreachable — which is exactly why it is here,
        // since the cost of being wrong is the corpus on the local network.
        if case .hostPort(let host, _) = connection.endpoint, !Self.isLoopback(host) {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private nonisolated static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }

    /// Accumulates until the headers and the whole declared body have arrived.
    /// HTTP is read by hand rather than with a framework because the surface
    /// is one method on one path — a dependency would be more code than this.
    private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if error != nil { connection.cancel(); return }

            // A body bigger than this is not a tool call, it's a mistake or an
            // attack — dropped rather than buffered.
            guard buffer.count <= 1_000_000 else {
                self.respond(connection, status: "413 Payload Too Large", json: nil)
                return
            }
            guard let request = HTTPRequest(buffer) else {
                if isComplete { connection.cancel() } else {
                    self.receive(connection, buffer: buffer)
                }
                return
            }
            Task { @MainActor in
                self.handle(request, on: connection)
            }
        }
    }

    @MainActor
    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        // Rail 2. Compared with a constant-time-ish equality on the raw string;
        // the token is 32 hex characters from `SecRandomCopyBytes`, so guessing
        // it over loopback is not the threat model — leaking it is, and it is
        // never logged.
        let expected = "Bearer " + MCPPairing.token()
        guard request.authorization == expected else {
            respond(connection, status: "401 Unauthorized", json: nil)
            return
        }
        guard request.method == "POST", request.path.hasPrefix("/mcp") else {
            respond(connection, status: "404 Not Found", json: nil)
            return
        }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            respond(connection, status: "400 Bad Request",
                    json: Self.error(id: nil, code: -32_700, message: "Parse error"))
            return
        }
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        // A NOTIFICATION carries no id and takes no response — answering one
        // with a JSON-RPC result is a protocol error, not a harmless extra.
        guard id != nil else {
            respond(connection, status: "202 Accepted", json: nil)
            return
        }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            respond(connection, status: "200 OK", json: Self.result(id: id, [
                // Echoed from the client when it names one, so a newer client
                // isn't told to downgrade to a version this happens to pin.
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "casberi", "version": Self.appVersion],
            ]))
        case "ping":
            respond(connection, status: "200 OK", json: Self.result(id: id, [:]))
        case "tools/list":
            respond(connection, status: "200 OK",
                    json: Self.result(id: id, ["tools": Self.toolDeclarations]))
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let text = call(name, arguments: arguments)
            respond(connection, status: "200 OK", json: Self.result(id: id, [
                "content": [["type": "text", "text": text.body]],
                "isError": text.isError,
            ]))
        default:
            respond(connection, status: "200 OK",
                    json: Self.error(id: id, code: -32_601, message: "Method not found"))
        }
    }

    // MARK: - The tools

    private static let toolDeclarations: [[String: Any]] = [
        ["name": "search_things",
         "description": "Search the things this person has saved in Casberi — links, notes, screenshots, chats, events and more. Returns real saved items.",
         "inputSchema": ["type": "object",
                         "properties": ["query": ["type": "string",
                                                  "description": "Words to search for."],
                                        "limit": ["type": "integer",
                                                  "description": "How many to return, up to 25."]],
                         "required": ["query"]]],
        ["name": "week_synthesis",
         "description": "A plain summary of what this person saved over the last seven days. Deterministic — counted, never written by a model.",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
        ["name": "save_thing",
         "description": "Propose something to save into Casberi. This does NOT save it: it appears in the app as an item awaiting the person's approval, and only their tap commits it.",
         "inputSchema": ["type": "object",
                         "properties": ["text": ["type": "string",
                                                 "description": "The text to save."],
                                        "tags": ["type": "array", "items": ["type": "string"],
                                                 "description": "Optional tags."]],
                         "required": ["text"]]],
    ]

    @MainActor
    private func call(_ name: String, arguments: [String: Any]) -> (body: String, isError: Bool) {
        guard let container = SharedStore.live else {
            return ("Casberi's store isn't open yet — try again in a moment.", true)
        }
        let context = ModelContext(container)
        switch name {
        case "search_things":
            let query = arguments["query"] as? String ?? ""
            let limit = min(max(arguments["limit"] as? Int ?? 10, 1), 25)
            let hits = MCPTools.searchThings(query, limit: limit, context: context)
            guard !hits.isEmpty else { return ("Nothing saved matches \"\(query)\".", false) }
            // Redacted on the way out — this leaves the app's process for
            // another program's context window, the same boundary
            // `AgentContext` and `AgentAnswer` scrub at (prd §277).
            let lines = hits.filter(\.isLive).map { thing in
                "- \(SecretScan.redacted(thing.title)) — \(thing.kind.typeTag), from \(thing.source)"
            }
            return (lines.joined(separator: "\n"), false)
        case "week_synthesis":
            return (MCPTools.weekSynthesis(context: context), false)
        case "save_thing":
            let text = (arguments["text"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return ("Nothing to save — `text` was empty.", true) }
            let tags = (arguments["tags"] as? [String]) ?? []
            MCPTools.saveThing(text: text, from: "MCP", tags: tags, context: context)
            // Worded so the calling agent cannot report this as done. It is
            // the consent rail's whole point, and an agent that says "saved"
            // when nothing was saved has told the person something false.
            return ("Proposed. It's waiting in Casberi for approval — nothing has been saved yet.", false)
        default:
            return ("There is no tool called \"\(name)\".", true)
        }
    }

    // MARK: - JSON-RPC + HTTP plumbing

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static func result(id: Any?, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value]
    }

    private static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(),
         "error": ["code": code, "message": message]]
    }

    private nonisolated func respond(_ connection: NWConnection, status: String,
                                     json: [String: Any]?) {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        // One request per connection: the tool surface is tiny and a
        // keep-alive loop is state this doesn't need.
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// The smallest HTTP request reader that can serve one JSON-RPC endpoint:
/// nil until both the header block and the whole declared body have arrived,
/// so the caller knows to keep reading.
private struct HTTPRequest {
    let method: String
    let path: String
    let authorization: String?
    let body: Data

    init?(_ buffer: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let request = lines.first?.components(separatedBy: " ") ?? []
        guard request.count >= 2 else { return nil }
        method = request[0]
        path = request[1]

        var authorization: String?
        var length = 0
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "authorization" { authorization = value }
            if name == "content-length" { length = Int(value) ?? 0 }
        }
        self.authorization = authorization

        let bodyStart = headerEnd.upperBound
        let available = buffer.count - bodyStart
        guard available >= length else { return nil }   // keep reading
        body = buffer.subdata(in: bodyStart..<(bodyStart + length))
    }
}
#endif
