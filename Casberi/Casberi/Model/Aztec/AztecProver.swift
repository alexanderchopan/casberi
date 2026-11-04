import Foundation

/// Your Aztec account's prover (prd §1700): Aztec's own native iOS library
/// (barretenberg v6, `libbb-external.a`, fetched by `scripts/aztec-engine.sh`),
/// one command at a time on a thread with a deep stack. The engine page's
/// bb.js sends exactly what it would hand its WebAssembly `bbapi`; this hands
/// the same bytes to the native `bbapi` and returns its reply, in order, as
/// bb.js's single worker would. Measured on an iPhone 17 Pro Max: a proof in
/// 3–6 s. Mac Catalyst has no prover (Aztec ships no Catalyst slice).
final class AztecProver: @unchecked Sendable {
    static let shared = AztecProver()

    /// Whether this build links Aztec's prover.
    static var isAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    private struct Job { let input: Data; let done: (Data?) -> Void }
    private let condition = NSCondition()
    private var jobs: [Job] = []
    private var started = false

    func call(_ input: Data, done: @escaping (Data?) -> Void) {
        guard Self.isAvailable else { return done(nil) }
        condition.lock()
        if !started {
            started = true
            let thread = Thread { [unowned self] in self.loop() }
            thread.name = "aztec-prover"
            thread.stackSize = 64 << 20 // the prover recurses deeply
            thread.qualityOfService = .userInitiated
            thread.start()
        }
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
            job.done(Self.run(job.input))
        }
    }

    private static func run(_ input: Data) -> Data? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        input.withUnsafeBytes { raw in
            aztecBBAPI(raw.bindMemory(to: UInt8.self).baseAddress, input.count, &output, &outputLength)
        }
        defer { free(output) }
        return output.map { Data(bytes: $0, count: outputLength) } ?? Data()
        #endif
    }
}

#if !targetEnvironment(macCatalyst)
/// Aztec's one C entry: a msgpack command in, a freshly allocated msgpack reply
/// out, which the caller frees.
@_silgen_name("bbapi")
private func aztecBBAPI(_ input: UnsafePointer<UInt8>?, _ inputLength: Int,
                        _ output: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                        _ outputLength: UnsafeMutablePointer<Int>)
#endif
