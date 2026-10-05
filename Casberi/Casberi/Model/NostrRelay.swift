import Foundation

/// A minimal NIP-01 client over `URLSessionWebSocketTask` — every other bridge
/// in this app rides plain HTTPS (`IngestSupport.getJSON`), but Nostr relays
/// speak the WebSocket subprotocol: send `["REQ", subId, filter]`, collect
/// `["EVENT", subId, event]` frames until `["EOSE", subId]`, then close. Its
/// one reader is Lightning (prd §1098), whose Nostr Wallet Connect string
/// names the relays; the Nostr social seat that first used it is deleted.
enum NostrRelay {
    /// One filter's answer. `reached` is TRUE when a relay completed the
    /// protocol round trip (EOSE/NOTICE/CLOSED), so zero events is a real
    /// fact; FALSE means every relay timed out or errored, and an empty
    /// `events` must never be read as "nothing exists".
    struct Result {
        let events: [[String: Any]]
        let reached: Bool
    }

    /// One relay's answer to one filter, capped at `timeout` seconds total.
    /// Returns whatever arrived before EOSE/CLOSED/NOTICE/timeout — a relay
    /// that answers partially still contributes those events.
    static func request(_ relay: String, filter: [String: Any],
                        timeout: TimeInterval = 8) async -> Result {
        guard let url = URL(string: relay) else { return Result(events: [], reached: false) }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let subID = UUID().uuidString.prefix(12).lowercased()
        guard let reqData = try? JSONSerialization.data(
            withJSONObject: ["REQ", String(subID), filter]),
              let reqString = String(data: reqData, encoding: .utf8)
        else { return Result(events: [], reached: false) }
        do { try await task.send(.string(reqString)) } catch { return Result(events: [], reached: false) }

        var events: [[String: Any]] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero,
                  let message = await receive(task, timeout: remaining) else { break }
            guard case .string(let text) = message,
                  let data = text.data(using: .utf8),
                  let frame = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let kind = frame.first as? String else { continue }
            switch kind {
            case "EVENT":
                if frame.count >= 3, let event = frame[2] as? [String: Any] { events.append(event) }
            case "EOSE", "NOTICE", "CLOSED":
                return Result(events: events, reached: true)
            default:
                continue   // AUTH and anything else: not relevant to a public read
            }
        }
        return Result(events: events, reached: false)   // timed out — never claim "nothing"
    }

    /// One filter, asked of the given relays in turn until one completes the
    /// round trip — for a relay set the PERSON supplied (a Nostr Wallet
    /// Connect string, prd §1098), whose hosts are recorded under the
    /// service that named them, since no registry could list them.
    static func requestAny(_ relays: [String], filter: [String: Any],
                           service: String = "Lightning",
                           timeout: TimeInterval = 8) async -> Result {
        for relay in relays {
            if let host = URL(string: relay)?.host { NetworkLedger.shared.record(host: host, as: service) }
            let page = await request(relay, filter: filter, timeout: timeout)
            if page.reached || !page.events.isEmpty { return page }
        }
        return Result(events: [], reached: false)
    }

    /// Publishes one signed event and waits for the first event matching
    /// `filter` — a request and its answer on one socket (NIP-47). The
    /// subscription opens BEFORE the publish, so an answer that comes back
    /// faster than a second round trip is never missed. nil on timeout, on a
    /// relay that refuses the event (`OK` false), or on any socket error.
    static func publishAndAwait(_ relay: String, event: [String: Any],
                                filter: [String: Any], service: String = "Lightning",
                                timeout: TimeInterval = 12) async -> [String: Any]? {
        guard let url = URL(string: relay) else { return nil }
        if let host = url.host { NetworkLedger.shared.record(host: host, as: service) }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let subID = String(UUID().uuidString.prefix(12).lowercased())
        guard let req = try? JSONSerialization.data(withJSONObject: ["REQ", subID, filter],
                                                    options: [.withoutEscapingSlashes]),
              let pub = try? JSONSerialization.data(withJSONObject: ["EVENT", event],
                                                    options: [.withoutEscapingSlashes]),
              let reqString = String(data: req, encoding: .utf8),
              let pubString = String(data: pub, encoding: .utf8)
        else { return nil }
        do {
            try await task.send(.string(reqString))
            try await task.send(.string(pubString))
        } catch { return nil }

        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero,
                  let message = await receive(task, timeout: remaining) else { return nil }
            guard case .string(let text) = message,
                  let data = text.data(using: .utf8),
                  let frame = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let kind = frame.first as? String else { continue }
            switch kind {
            case "EVENT":
                if frame.count >= 3, let answer = frame[2] as? [String: Any] { return answer }
            case "OK":
                // ["OK", id, accepted, reason] — a refused publish has no answer coming.
                if frame.count >= 3, (frame[2] as? Bool) == false { return nil }
            case "CLOSED":
                return nil
            default:
                continue   // EOSE before the answer arrives, NOTICE, AUTH
            }
        }
    }

    /// `URLSessionWebSocketTask.receive()` has no timeout of its own — it
    /// awaits indefinitely until a frame arrives or the socket errors. Races
    /// it against a sleep so one silent relay can never hang past its share
    /// of the read's own deadline.
    private static func receive(_ task: URLSessionWebSocketTask,
                                timeout: Duration) async -> URLSessionWebSocketTask.Message? {
        await withTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask { try? await task.receive() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
