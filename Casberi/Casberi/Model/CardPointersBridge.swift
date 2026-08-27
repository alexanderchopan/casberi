import Foundation

/// CardPointers — the offers sitting unused on your cards (prd §420).
///
/// **Read-only by CONDUCT, and the promise is easy to keep here for once:**
/// every tool this service exposes is a read. There is no write endpoint to
/// abstain from, so unlike Cursor (§303) or Privacy.com there is no verb we
/// are choosing not to send. This file issues `tools/call` against the five
/// listed tools and nothing else.
///
/// **The seat requires CardPointers+ and says so before the tap.** Measured
/// 2026-08-20 against a free account: all five tools answer `-32001`, so a
/// free account can sign in and read nothing at all. That is stated on the
/// tile rather than discovered after a sign-in hop, or it is the §83 dead
/// control — a button that completes successfully and then produces a room
/// which can never fill.
///
/// The wire itself — SSE framing, the JSON-RPC envelope, the device-flow
/// responses — is `CardPointersWire`, which is Foundation-only and compiled
/// whole by `scripts/cardpointers-selftest.sh`.
enum CardPointersAuth {

    static let seatKey = "cardpointers"
    private static let tokenKey = "cardpointers.token"
    private static let proKey = "cardpointers.isPro"

    /// Our client identity. They key on `X-MCP-Client`, so this string is ours
    /// to declare — and it is declared honestly rather than borrowed from
    /// their CLI, which would be us claiming to be their software. An
    /// undeclared client was accepted when measured; that is not a promise it
    /// always will be, which is another reason to send a real name.
    static var clientHeader: String {
        let build = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "Casberi/\(build)"
    }

    static var token: String? { TokenVault.get(tokenKey) }
    static var isConnected: Bool { token != nil }

    /// Whether THIS account can actually read anything. Known from the
    /// sign-in response, so it never costs a request and is never inferred
    /// from a failure.
    static var isPro: Bool { UserDefaults.standard.bool(forKey: proKey) }

    static func store(_ token: CardPointersWire.Token) {
        TokenVault.set(token.accessToken, for: tokenKey)
        UserDefaults.standard.set(token.isPro, forKey: proKey)
    }

    static func disconnect() {
        TokenVault.delete(tokenKey)
        UserDefaults.standard.removeObject(forKey: proKey)
    }

    // MARK: - Device flow

    static func startDeviceFlow() async -> CardPointersWire.DeviceCode? {
        let (json, _) = await post("\(CardPointersWire.apiBase)/api/device/code", body: [:])
        return CardPointersWire.deviceCode(from: json)
    }

    /// One poll. The caller owns the loop and the interval, so a screen that
    /// goes away stops polling — a self-driving loop here would outlive the
    /// screen that started it and keep asking their host about a code nobody
    /// is waiting on.
    static func pollOnce(deviceCode: String) async -> CardPointersWire.Poll {
        let (json, status) = await post("\(CardPointersWire.apiBase)/api/device/token",
                                        body: ["device_code": deviceCode])
        // A pending poll is HTTP 400 with the reason in the body (see
        // `CardPointersWire.Poll`), so status is deliberately NOT gated on
        // here — only a body we could not read at all is unreadable.
        guard json != nil else {
            return status == 0 ? .unreadable : .pending
        }
        return CardPointersWire.poll(from: json)
    }

    // MARK: - Transport

    /// A POST that keeps the body whatever the status says. Every shared
    /// helper in `IngestSupport` drops the body on non-200, which this flow
    /// cannot survive.
    private static func post(_ url: String, body: [String: Any],
                             auth: String? = nil,
                             accept: String = "application/json") async -> (Any?, Int) {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return (nil, 0) }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(clientHeader, forHTTPHeaderField: "X-MCP-Client")
        if let auth { request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }

        NetworkLedger.shared.record(request, as: "CardPointers")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, 0) }
        return (try? JSONSerialization.jsonObject(with: data), http.statusCode)
    }

    /// The MCP call. Its response is SSE, so it is read as TEXT and unframed
    /// before any JSON is attempted.
    static func call(tool: String, arguments: [String: Any] = [:]) async -> CardPointersWire.Answer {
        guard let token else { return .failed(code: 0, message: "not connected") }
        guard let u = URL(string: CardPointersWire.apiBase + CardPointersWire.mcpPath),
              let payload = try? JSONSerialization.data(
                withJSONObject: CardPointersWire.callBody(tool: tool, arguments: arguments))
        else { return .unreadable }

        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientHeader, forHTTPHeaderField: "X-MCP-Client")

        NetworkLedger.shared.record(request, as: "CardPointers")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let body = String(data: data, encoding: .utf8) else { return .unreadable }
        return CardPointersWire.answer(from: body)
    }
}

extension CardPointersAuth {
    /// `-cardPointersProbe YES` — the read PHASE BY PHASE, one NSLog per line
    /// (the `-todayProbe` truncation lesson).
    ///
    /// It exists because an empty CardPointers room has five causes that all
    /// render as the same nothing, and only the last is a bug: not signed in;
    /// signed in on an account without CardPointers+ (the common one, and the
    /// reason `pro=` is printed before anything is called); a subscriber with
    /// genuinely no active offers; their host unreachable; or shape drift.
    /// `tools/list` is asked separately from `tools/call` on purpose —
    /// measured 2026-08-20, the list answers for a free account while every
    /// call is refused, so a working list beside a refused call is the
    /// SUBSCRIPTION state rather than a broken connection.
    @MainActor
    static func diagnose() async {
        func say(_ line: String) { NSLog("[Casberi] cardPointers| %@", line) }

        say("connected=\(isConnected) pro=\(isPro) client=\(clientHeader)")
        guard isConnected else {
            say("no token — connect first on the CardPointers screen")
            return
        }

        for tool in ["list_my_cards", "list_my_offers", "list_profiles",
                     "search_my_offers", "recommend_card"] {
            let arguments: [String: Any]
            switch tool {
            case "search_my_offers": arguments = ["query": "a"]
            case "recommend_card":   arguments = ["category": "supermarket"]
            default:                 arguments = [:]
            }
            switch await call(tool: tool, arguments: arguments) {
            case .payload(let text):
                // Length, never content — this is somebody's card book.
                say("\(tool): OK \(text.count) chars")
            case .subscriptionRequired(let url):
                say("\(tool): needs CardPointers+ (upgrade_url=\(url != nil))")
            case .failed(let code, let message):
                say("\(tool): FAILED code=\(code) \(message)")
            case .unreadable:
                say("\(tool): UNREADABLE — host down, or the wire shape moved")
            }
        }
    }
}

import SwiftData

/// Landing offers as things (prd §420).
///
/// **§216 decides what lands.** A CARD is state — twelve cards landing as
/// twelve rows is the §223 count-as-a-thing failure — so cards never land;
/// they are read only to name the card an offer sits on. An OFFER is a thing,
/// and it is the one with a clock: its expiry becomes `dueAt`, which is what
/// makes `NotifySweep`'s generic `deadlineNear`, the "Needs you" widget runway
/// and `KeptAskComposers.overdue` all work with no new code in any of them —
/// the App Store Connect route (§323).
enum CardPointersIngest {

    static let source = "CardPointers"
    @MainActor private static var running = false

    /// The read. Returns the number of NEW offers landed, or nil if it could
    /// not read at all — the two are different answers and the screen says so
    /// differently: nil is trouble, 0 is a quiet book.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard CardPointersAuth.isConnected, CardPointersAuth.isPro else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        // `status: "all"` on purpose: a redeemed or expired offer already in
        // the corpus must be able to LEARN that it is finished, and asking only
        // for active ones would leave every landed row frozen at the state it
        // had when it arrived.
        guard case .payload(let text) = await CardPointersAuth.call(
            tool: "list_my_offers", arguments: ["status": "all"]) else { return nil }

        let offers = CardPointers.decodeList(text)
        guard !offers.isEmpty else { return 0 }

        let existing = IngestSupport.thingsByRef(context, source: source)
        var landed = 0
        for offer in offers {
            if let already = existing[offer.ref] {
                heal(already, with: offer)
                continue
            }
            // A finished offer that we have never seen does NOT land. It is
            // not news — it is somebody's history of a coupon — and landing it
            // would fill the room on first connect with things already over.
            guard offer.status.needsYou else { continue }
            let thing = Thing(
                kind: .reminder,
                title: title(for: offer),
                content: "",
                source: source,
                capturedAt: .now,
                sourceRef: offer.ref)
            thing.dueAt = offer.expires
            thing.summary = offer.terms
            thing.authorHandle = offer.card
            context.insert(thing)
            landed += 1
        }
        try? context.save()
        return landed
    }

    /// The card LEADS the title, the Trello/Linear rule: it is the context that
    /// makes the rest of the line legible, and — the §303 clamp ruling —
    /// `titleLine` cuts at 80, so anything that trails can be eaten.
    static func title(for offer: CardPointers.Offer) -> String {
        guard let card = offer.card, !card.isEmpty else { return offer.merchant }
        return "\(card) · \(offer.merchant)"
    }

    /// An offer is not finished when it lands, unlike almost everything else in
    /// this app — it gets redeemed, snoozed or runs out. So a landed row is
    /// re-read every pass and updated in place rather than duplicated.
    ///
    /// **A finished offer keeps its `dueAt` cleared**, or a redeemed coupon
    /// goes on claiming a deadline and reaches the lock screen through
    /// machinery that has no idea it is over.
    ///
    /// **And it is MARKED, since §487.** Clearing the date alone left three
    /// different things wearing one appearance: an offer with genuinely no end
    /// date, one somebody snoozed, and one already redeemed all landed as a
    /// dateless row, so the room listed spent coupons among the live ones and
    /// the head counted them in "N offers waiting" forever. `mark` is an
    /// existing stored property — no new field, so **no CloudKit deploy** —
    /// and `.done` here means "not in play", which is exactly the set
    /// `Status.needsYou` already answers false for. It is CLEARED again when
    /// an offer comes back, because an un-snoozed offer is live again and a
    /// row that can never return to the list is a row that quietly disappears.
    @MainActor
    private static func heal(_ thing: Thing, with offer: CardPointers.Offer) {
        guard thing.isLive else { return }
        if offer.status.needsYou {
            if thing.dueAt != offer.expires { thing.dueAt = offer.expires }
            if thing.mark == .done { thing.mark = .none }
        } else {
            if thing.dueAt != nil { thing.dueAt = nil }
            if thing.mark != .done { thing.mark = .done }
        }
        if let terms = offer.terms, thing.summary != terms { thing.summary = terms }
        let wanted = title(for: offer)
        if thing.title != wanted { thing.title = wanted }
    }
}
