import Foundation

/// A minimal NIP-01 client over `URLSessionWebSocketTask` — every other bridge
/// in this app rides plain HTTPS (`IngestSupport.getJSON`), but Nostr relays
/// speak the WebSocket subprotocol: send `["REQ", subId, filter]`, collect
/// `["EVENT", subId, event]` frames until `["EOSE", subId]`, then close. One
/// relay read is exactly that shape — open, ask, collect, close — so this is
/// the one place a socket ever opens in the app.
///
/// Keyless by measurement (2026-07-27, live against nos.lol/relay.damus.io/
/// relay.primal.net/purplepag.es): a plain REQ for notes/profile/contacts/
/// reactions/mentions never drew an `AUTH` challenge on any of them — NIP-42
/// auth is a private-relay/write concern, not a public-read one. No event
/// signature is verified here: Casberi trusts each relay's own data the same
/// way it trusts Farcaster's Snapchain node or Bluesky's AppView, neither of
/// which it re-verifies cryptographically either. A relay lying about a public
/// note is a lesser and differently-shaped risk than the ones those hosts
/// already carry, and full schnorr verification is a real dependency this
/// bridge doesn't reach for in v1.
enum NostrRelay {
    /// Measured 2026-07-27: nos.lol answered every filter shape tried (notes,
    /// profile, contacts, reactions, `#p` mentions) cleanly and fast. Damus is
    /// a second opinion for redundancy despite flaking on two of five filters
    /// FROM THIS MAC — worth re-checking from a device before trusting that as
    /// a real limit rather than datacenter-IP throttling. `relay.primal.net`
    /// answered every filter but returned nothing for a real, active account,
    /// meaning it doesn't mirror arbitrary public content — not a read
    /// source. `relay.nostr.band` never answered at all (timeout on every
    /// filter tried) and is excluded: a relay indistinguishable from down
    /// buys nothing. Re-measure before changing this list.
    static let relays = ["wss://nos.lol", "wss://relay.damus.io"]

    /// One filter's answer, merged across every relay asked. `reached` is the
    /// honesty signal a delete-sync heal needs: TRUE means at least one relay
    /// actually completed the protocol round trip (EOSE/NOTICE/CLOSED) for
    /// this filter — genuinely zero events is a real fact then. FALSE means
    /// every relay timed out or errored, so an empty `events` here must never
    /// be read as "nothing exists" — the multi-relay analog of Bluesky's own
    /// heal rule ("a failed chunk is `continue`d past, never counted as a
    /// deletion"), needed here because a merge across relays has no single
    /// HTTP status to check.
    struct Result {
        let events: [[String: Any]]
        let reached: Bool
    }

    /// One filter, fanned out to every relay in `relays` concurrently, merged
    /// and deduped by event id (`"id"`) — the shape every caller below wants:
    /// no relay is canonical, so a note only one of them carries must still
    /// land. `timeout` bounds EACH relay's own read; a relay that never sends
    /// EOSE can't hang the other one, and can't hang the whole refresh.
    static func requestAll(filter: [String: Any], timeout: TimeInterval = 8) async -> Result {
        let pages = await withTaskGroup(of: Result.self) { group in
            for relay in relays {
                group.addTask { await request(relay, filter: filter, timeout: timeout) }
            }
            var out: [Result] = []
            for await page in group { out.append(page) }
            return out
        }
        var seen = Set<String>()
        let events = pages.flatMap(\.events).filter { event in
            guard let id = event["id"] as? String else { return false }
            return seen.insert(id).inserted
        }
        return Result(events: events, reached: pages.contains { $0.reached })
    }

    /// One relay's answer to one filter, capped at `timeout` seconds total.
    /// Returns whatever arrived before EOSE/CLOSED/NOTICE/timeout — a relay
    /// that answers partially still contributes those events, since
    /// `requestAll` treats every relay as a partial, mergeable source anyway.
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
