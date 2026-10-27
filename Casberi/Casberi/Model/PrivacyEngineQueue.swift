import Foundation

/// **ONE FLOW AT A TIME THROUGH THE ENGINE (the review of 2026-10-26,
/// finding 8).** The engine's page holds ONE open account: `open` replaces
/// it, its sessions and its notes. A flow is `open` → prepare (a proof) →
/// relay or sign, with awaits between, and other flows run in those awaits —
/// the fresh watch every 15 s, the background pass, a round-up riding a send,
/// a send from another root. One of them re-opening between another's
/// prepare and its relay swapped the account under it: a fresh address's
/// deposit could be proved for one root and kept under the other.
///
/// So every flow that opens the engine runs inside `run`: one at a time, in
/// the order asked (a release hands the engine straight to the next waiter),
/// and REENTRANT — a flow already inside (a task-local says so) runs a nested
/// one in place, so a deposit that moves round-ups through the same open
/// account does not wait on itself. `PrivacyEngine.call` refuses an
/// account-bound method outside it (`NotExclusive`), so a door that forgets
/// the queue fails loudly instead of racing. An unstructured `Task` started
/// inside inherits the task-local: never start one that uses the engine.
///
/// Pure (Foundation only): `private-money-selftest.sh` runs two flows through
/// it with their awaits interleaved and proves neither sees the other's open.
@MainActor
final class PrivacyEngineQueue {
    /// True inside `run`, for the task running it and its child tasks.
    @TaskLocal static var holding = false

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` alone: after every flow asked before it has finished.
    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        if Self.holding { return try await body() }
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer { release() }
        return try await Self.$holding.withValue(true) { try await body() }
    }

    /// Hands the engine to the next waiter (still busy), or frees it.
    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Flows waiting, for a log line.
    var waiting: Int { waiters.count }
}
