import Foundation
import Network

/// The web view's only origin: http://127.0.0.1, served from inside the app.
///
/// Loopback is a secure context to WebKit, so the page gets the storage Aztec's
/// PXE keeps its notes in, and the isolation headers below. Besides the page's
/// files it answers:
///   POST /bb      a prover command → the native prover's reply (binary both ways)
///   GET  /key     the account key's public half, hex
///   POST /sign    a 32-byte message hash → a 64-byte low-S signature
///   GET  /mem     this app's memory, JSON
///   POST /log     a line for the console; POST /result the timings so far
final class LocalServer: @unchecked Sendable {
    static let port: UInt16 = 8487
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local-server", attributes: .concurrent)
    private let root: URL

    init() throws {
        root = Bundle.main.url(forResource: "Web", withExtension: nil)!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { DispatchQueue.main.async(execute: ready) }
            if case .failed(let error) = state { Spike.log("server failed: \(error)") }
        }
        listener.start(queue: queue)
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
            if let request = Request(buffer) {
                self.handle(request) { response in
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let body: Data

        /// Nil until the head and the whole body have arrived.
        init?(_ data: Data) {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let first = lines.first?.split(separator: " ") ?? []
            guard first.count >= 2 else { return nil }
            var length = 0
            for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
                length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
            guard data.distance(from: end.upperBound, to: data.endIndex) >= length else { return nil }
            method = String(first[0])
            path = String(first[1].split(separator: "?").first ?? "/")
            body = data[end.upperBound..<data.index(end.upperBound, offsetBy: length)]
        }
    }

    private func handle(_ request: Request, reply: @escaping (Data) -> Void) {
        switch (request.method, request.path) {
        case ("POST", "/bb"):
            Prover.shared.call(Data(request.body)) { reply(Self.response(200, $0, type: "application/octet-stream")) }
        case ("GET", "/key"):
            do { reply(Self.response(200, Data(try EnclaveKey.publicKeyHex().utf8), type: "text/plain")) }
            catch { reply(Self.response(500, Data("\(error)".utf8), type: "text/plain")) }
        case ("POST", "/sign"):
            guard request.body.count == 32 else { return reply(Self.response(400, Data("a hash is 32 bytes".utf8), type: "text/plain")) }
            do { reply(Self.response(200, try EnclaveKey.sign(Data(request.body)), type: "application/octet-stream")) }
            catch { reply(Self.response(500, Data("\(error)".utf8), type: "text/plain")) }
        case ("GET", "/mem"):
            let m = Memory.now()
            reply(Self.response(200, Data("{\"footprint\":\(m.footprint),\"available\":\(m.available)}".utf8), type: "application/json"))
        case ("POST", "/log"):
            Spike.log("page: " + String(decoding: request.body, as: UTF8.self))
            reply(Self.response(204, Data(), type: "text/plain"))
        case ("POST", "/result"):
            Spike.result(String(decoding: request.body, as: UTF8.self))
            reply(Self.response(204, Data(), type: "text/plain"))
        case ("GET", _):
            reply(file(request.path))
        default:
            reply(Self.response(404, Data(), type: "text/plain"))
        }
    }

    private func file(_ path: String) -> Data {
        let relative = path == "/" ? "index.html" : String(path.dropFirst()).removingPercentEncoding ?? ""
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: url) else {
            return Self.response(404, Data(), type: "text/plain")
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "mjs": "text/javascript",
                     "wasm": "application/wasm", "json": "application/json", "css": "text/css"]
        return Self.response(200, data, type: types[url.pathExtension] ?? "application/octet-stream")
    }

    private static func response(_ status: Int, _ body: Data, type: String) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"][status] ?? "OK"
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n"
            + "Cross-Origin-Resource-Policy: same-origin\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
