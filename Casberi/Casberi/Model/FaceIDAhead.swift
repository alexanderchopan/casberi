import Foundation

/// **FACE ID AT THE TAP (prd §1687, user: "the preparing stage is where it
/// lags").** Face ID used to wait until preparing was done; now it is asked
/// the moment Send or Swap is tapped, beside the reads, and the context it
/// passed is handed to the signature, which then needs no second prompt.
/// What is signed is unchanged: the bytes are still worked out and checked
/// before the key signs them.
///
/// Generic over the context so `faceid-ahead-selftest.sh` compiles it whole
/// with a stand-in; the app's is `LAContext` (`YourAccountKey.ahead`).
final class FaceIDAhead<Context>: @unchecked Sendable {
    /// Face ID was turned down at the tap, so nothing is signed.
    struct Refused: Error {}

    let context: Context
    private let asked: Task<Bool, Never>
    private let lock = NSLock()
    private var taken = false
    private var answer: Bool?

    /// Starts asking at once.
    init(context: Context, ask: @escaping @Sendable () async -> Bool) {
        self.context = context
        asked = Task { await ask() }
    }

    /// Whether Face ID passed, waiting for the answer. The answer is kept,
    /// so `refused` can be read without waiting afterwards.
    func passed() async -> Bool {
        let ok = await asked.value
        lock.withLock { answer = ok }
        return ok
    }

    /// Turned down, as far as `passed()` has heard (never waits).
    var refused: Bool { lock.withLock { answer == false } }

    /// The context, for the FIRST signature only, once Face ID has passed:
    /// it waits for the answer, and throws `Refused` if Face ID was turned
    /// down. Every later signature of the same operation gets nil and asks
    /// Face ID itself, as before.
    func take() async throws -> Context? {
        let first: Bool = lock.withLock {
            defer { taken = true }
            return !taken
        }
        guard first else { return nil }
        guard await passed() else { throw Refused() }
        return context
    }
}
