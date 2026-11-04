import Foundation
import Network

/// The engine view's origin: http://127.0.0.1:8488, served from inside the app
/// (the phone spike's LocalServer, files only). Loopback is a secure context to
/// WebKit, so the PXE gets its OPFS storage, and the isolation headers give
/// WebAssembly its threads. No app page ever loads from here.
final class EngineServer: @unchecked Sendable {
    static let port: UInt16 = 8488
    /// The test app's page on a device: a second origin (another port), so it is
    /// never the engine's.
    static let dappPort: UInt16 = 8489
    private let listener: NWListener
    private let queue = DispatchQueue(label: "engine-server", attributes: .concurrent)
    private let root: URL

    init(root: URL = resourceRoot.appendingPathComponent("Engine"), port: UInt16 = EngineServer.port) throws {
        self.root = root
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { DispatchQueue.main.async(execute: ready) }
            if case .failed(let error) = state { log("{\"event\":\"serverFailed\",\"detail\":\"\(error)\"}") }
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
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let first = lines.first?.split(separator: " ") ?? []
                let method = first.first.map(String.init) ?? "GET"
                let path = first.count >= 2 ? String(first[1].split(separator: "?").first ?? "/") : "/"
                var length = 0
                for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
                    length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
                guard buffer.distance(from: end.upperBound, to: buffer.endIndex) >= length else {
                    return self.read(connection, buffer: buffer) // the body is still arriving
                }
                if method == "POST", path == "/bb" {
                    // A prover command from the engine page → Aztec's native prover → its reply.
                    let body = Data(buffer[end.upperBound..<buffer.index(end.upperBound, offsetBy: length)])
                    Prover.shared.call(body) { reply in
                        connection.send(content: Self.response(200, reply, type: "application/octet-stream"),
                                        completion: .contentProcessed { _ in connection.cancel() })
                    }
                    return
                }
                connection.send(content: self.file(path), completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func file(_ path: String) -> Data {
        let relative = path.hasSuffix("/") ? String(path.dropFirst()) + "index.html" : String(path.dropFirst()).removingPercentEncoding ?? ""
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: url) else {
            return Self.response(404, Data(), type: "text/plain")
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "mjs": "text/javascript",
                     "wasm": "application/wasm", "json": "application/json", "css": "text/css", "gz": "application/gzip"]
        return Self.response(200, data, type: types[url.pathExtension] ?? "application/octet-stream")
    }

    private static func response(_ status: Int, _ body: Data, type: String) -> Data {
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\n"
            + "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n"
            + "Cross-Origin-Resource-Policy: same-origin\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
