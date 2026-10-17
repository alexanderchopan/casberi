import Foundation

/// Aztec's native prover, one command at a time, on a thread with a deep stack.
///
/// bb.js sends exactly what it would hand its WebAssembly `bbapi` export; this
/// hands the same bytes to the native `bbapi` and returns its reply. Commands
/// run in order, as they do on bb.js's single worker.
final class Prover: @unchecked Sendable {
    static let shared = Prover()

    private struct Job { let input: Data; let done: (Data) -> Void }
    private let condition = NSCondition()
    private var jobs: [Job] = []

    private init() {
        let thread = Thread { [unowned self] in self.loop() }
        thread.name = "aztec-prover"
        thread.stackSize = 64 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func call(_ input: Data, done: @escaping (Data) -> Void) {
        condition.lock()
        jobs.append(Job(input: input, done: done))
        condition.signal()
        condition.unlock()
    }

    private func loop() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()

            let name = Self.commandName(job.input)
            let start = Date()
            var output: UnsafeMutablePointer<UInt8>?
            var outputLength = 0
            job.input.withUnsafeBytes { raw in
                bbapi(raw.bindMemory(to: UInt8.self).baseAddress, job.input.count, &output, &outputLength)
            }
            let reply = output.map { Data(bytes: $0, count: outputLength) } ?? Data()
            free(output)
            let seconds = Date().timeIntervalSince(start)
            if seconds > 0.05 || name.hasPrefix("Chonk") || name.hasPrefix("Srs") {
                Spike.log(String(format: "bb %@ %.2f s · in %@ · out %@", name, seconds, Self.size(job.input.count), Self.size(reply.count)))
            }
            Spike.recordProver(name: name, seconds: seconds)
            job.done(reply)
        }
    }

    /// The command's name: the first string in the msgpack, under its arrays.
    static func commandName(_ data: Data) -> String {
        var i = data.startIndex
        while i < data.endIndex {
            let b = data[i]
            switch b {
            case 0x90...0x9f: i += 1
            case 0xdc: i += 3
            case 0xdd: i += 5
            case 0xa0...0xbf:
                let n = Int(b & 0x1f)
                return String(decoding: data[(i + 1)..<min(i + 1 + n, data.endIndex)], as: UTF8.self)
            case 0xd9 where i + 1 < data.endIndex:
                let n = Int(data[i + 1])
                return String(decoding: data[(i + 2)..<min(i + 2 + n, data.endIndex)], as: UTF8.self)
            default: return "?"
            }
        }
        return "?"
    }

    static func size(_ bytes: Int) -> String {
        bytes >= 1 << 20 ? String(format: "%.1f MB", Double(bytes) / 1048576) : String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
