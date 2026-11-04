import Foundation
import Network

/// The Aztec engine page's one origin (prd §1700): http://127.0.0.1:48713,
/// served from inside the app. Loopback is a secure context to WebKit, so the
/// PXE gets the OPFS storage it keeps the account's notes in, and the isolation
/// headers give WebAssembly its threads. The port is fixed because the storage
/// belongs to the origin: another port would be another, empty, account store.
/// No app page ever loads from here.
///
/// Besides the page's files (`AztecEngine`, built by `scripts/aztec-engine.sh`):
///   POST /bb    a prover command → Aztec's native prover → its reply
///   POST /net   a request for another host (the page's `fetch`, rewritten by
///               net-shim.js) → sent only to a host Casberi declares for the
///               engine (NetworkReach), through the app's one funnel
final class AztecEngineServer: @unchecked Sendable {
    static let port: UInt16 = 48713
    static var origin: String { "http://127.0.0.1:\(port)" }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "aztec-engine-server", attributes: .concurrent)
    private let root: URL

    init() throws {
        guard let root = Bundle.main.url(forResource: "AztecEngine", withExtension: nil) else {
            throw NSError(domain: "AztecEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "the engine page is not in this build"])
        }
        self.root = root
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start(ready: @escaping @Sendable (Bool) -> Void) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready(true)
            case .failed(let error):
                NSLog("aztecEngine| server | failed %@", "\(error)")
                ready(false)
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    // MARK: - Requests

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil { connection.cancel() } else { self.read(connection, buffer: buffer) }
                return
            }
            let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
            var lines = head.components(separatedBy: "\r\n")
            let first = lines.removeFirst().split(separator: " ")
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            guard buffer.distance(from: end.upperBound, to: buffer.endIndex) >= length else {
                return self.read(connection, buffer: buffer) // the body is still arriving
            }
            let request = Request(
                method: first.first.map(String.init) ?? "GET",
                path: first.count > 1 ? String(first[1].split(separator: "?").first ?? "/") : "/",
                headers: headers,
                body: Data(buffer[end.upperBound..<buffer.index(end.upperBound, offsetBy: length)]))
            self.handle(request) { response in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func handle(_ request: Request, reply: @escaping @Sendable (Data) -> Void) {
        switch (request.method, request.path) {
        case ("POST", "/bb"):
            AztecProver.shared.call(request.body) { output in
                guard let output else { return reply(Self.response(501, Data("no prover in this build".utf8), type: "text/plain")) }
                reply(Self.response(200, output, type: "application/octet-stream"))
            }
        case ("POST", "/net"):
            #if DEBUG
            NSLog("aztecEngine| net | asked %@", URL(string: request.headers["x-casberi-target"] ?? "")?.host ?? "?")
            #endif
            relay(request, reply: reply)
        case ("GET", _):
            reply(file(request.path))
        default:
            reply(Self.response(404, Data(), type: "text/plain"))
        }
    }

    /// The page's request for another host, sent only where the engine is
    /// declared to go, through `IngestSupport`'s funnel (Tor and receipts by
    /// the endpoint's policy).
    private func relay(_ request: Request, reply: @escaping @Sendable (Data) -> Void) {
        guard let raw = request.headers["x-casberi-target"], let url = URL(string: raw),
              let service = AztecEngine.service(for: url) else {
            NSLog("aztecEngine| net | refused %@", URL(string: request.headers["x-casberi-target"] ?? "")?.host ?? "?")
            return reply(Self.response(403, Data("host not declared".utf8), type: "text/plain"))
        }
        var forward = URLRequest(url: url)
        forward.httpMethod = request.headers["x-casberi-method"] ?? "GET"
        forward.timeoutInterval = 60
        let skipped: Set<String> = ["host", "connection", "content-length", "origin", "referer", "user-agent",
                                    "accept-encoding", "x-casberi-target", "x-casberi-method"]
        for (field, value) in request.headers where !skipped.contains(field) && !field.hasPrefix("sec-") {
            forward.setValue(value, forHTTPHeaderField: field)
        }
        if !request.body.isEmpty { forward.httpBody = request.body }
        let started = Date()
        Task {
            guard let (data, http) = await IngestSupport.sendRequest(forward, service: service) else {
                NSLog("aztecEngine| net | %@ | no answer | %d ms", url.host ?? "?", Int(Date().timeIntervalSince(started) * 1000))
                return reply(Self.response(502, Data("no answer from \(url.host ?? "?")".utf8), type: "text/plain"))
            }
            #if DEBUG
            NSLog("aztecEngine| net | %@ | %d | %d bytes | %d ms", url.host ?? "?", http.statusCode, data.count, Int(Date().timeIntervalSince(started) * 1000))
            #endif
            let type = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            reply(Self.response(http.statusCode, data, type: type))
        }
    }

    private func file(_ path: String) -> Data {
        let relative = path.hasSuffix("/") ? String(path.dropFirst()) + "index.html" : String(path.dropFirst()).removingPercentEncoding ?? ""
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: url) else {
            return Self.response(404, Data(), type: "text/plain")
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "mjs": "text/javascript",
                     "wasm": "application/wasm", "json": "application/json", "gz": "application/gzip"]
        return Self.response(200, data, type: types[url.pathExtension] ?? "application/octet-stream")
    }

    private static func response(_ status: Int, _ body: Data, type: String) -> Data {
        let reasons = [200: "OK", 206: "Partial Content", 403: "Forbidden", 404: "Not Found", 501: "Not Implemented", 502: "Bad Gateway"]
        let head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\n"
            + "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n"
            + "Cross-Origin-Resource-Policy: same-origin\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
