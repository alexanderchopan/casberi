import Foundation

/// MAIL SUBSCRIPTIONS (prd §1111) — Day's Subscriptions tile: every mailing
/// list that writes to you, the way the Wallet's tile lists what charges you.
///
/// **What counts is a header, never a guess.** A mail is a subscription's
/// when it carries `List-Id` (RFC 2919) or `List-Unsubscribe` (RFC 2369);
/// Gmail and Yahoo require the second from every bulk sender since 2024. A
/// person who writes every Tuesday is not a list, and nothing here infers one
/// from a cadence. `MailIngest` keeps the two headers as rowless facts
/// (`ThingFact.Action.list`, `.unsubscribe`); this reads them back.
///
/// **One list, one row.** Mails group by the list's key: the id inside the
/// `List-Id`'s angle brackets, else the sender's address. A list that renamed
/// itself keeps its id, so it stays one row; its newest mail names it.
///
/// **The order is volume, the cleanup question** ("what writes to me most"),
/// as Gmail's Manage subscriptions sorts. How many you opened is NOT read:
/// the read flag at ingest is the flag at arrival, so a count from it would
/// be a number the app cannot honestly know (§83).
///
/// **Or the person says so (prd §1115).** A sender with no list header, or
/// mail that landed before §1111 kept the headers, joins the tile when the
/// person adds it from a mail's sheet ("Track a subscription"). That is their
/// word, never an inference: the reading files every mail from an address
/// they added (`file(_:added:)`), and nothing else without a header.
///
/// Foundation-only, so `scripts/mail-subscriptions-selftest.sh` compiles it
/// whole.
enum MailSubscriptions {

    /// One landed mail, as far as this reading needs it.
    struct Mail: Equatable {
        var id: UUID
        /// The list's key (`key(listID:address:)`).
        var key: String
        /// Who the inbox says sent it.
        var sender: String
        var address: String?
        /// The `List-Unsubscribe` link this mail carried, if any.
        var unsubscribe: String?
        var at: Date
        /// The mail seat it landed in (Gmail, iCloud Mail).
        var source: String
        /// Filed because the person added its sender, not by a header.
        var byYou = false
    }

    /// One landed mail as the store holds it, before it is filed: the key its
    /// `List` fact carries (nil when it carried no list header).
    struct Landed: Equatable {
        var id: UUID
        var listKey: String?
        var sender: String?
        var address: String?
        var unsubscribe: String?
        var at: Date
        var source: String
    }

    struct Item: Identifiable, Equatable {
        var id: String
        /// The sender's name off the newest mail.
        var name: String
        var address: String?
        var count: Int
        /// How many arrived in the last thirty days — the statement's figure.
        var lastMonth: Int
        /// The median gap between mails, in days; nil under three mails,
        /// where a gap is an accident, not a cadence.
        var cadenceDays: Double?
        var last: Date
        var since: Date
        /// The newest link to leave by: https before mailto.
        var unsubscribe: URL?
        /// The mail seats it lands in.
        var sources: [String]
        /// Its mails, newest first — the sheet's Recent.
        var mailIDs: [UUID]
        /// Some of its mail is here only because the person added the
        /// sender, so Stop tracking has something to take away.
        var byYou = false
        /// When each of its mails arrived, newest first: the days Day's
        /// calendar puts its face on (prd §1117).
        var arrivals: [Date] = []
    }

    /// A sender the person could track (prd §1117): mail with no list header
    /// from an address not on the tile, in the last thirty days.
    struct Candidate: Identifiable, Equatable {
        /// The lowercased address.
        var id: String
        var name: String
        var address: String
        /// How many arrived in the last thirty days.
        var count: Int
        var last: Date
    }

    /// The window the box counts ("N mails in 30 days").
    static let windowDays = 30.0

    /// The list's identity. `List-Id: The Weekly Fold <weekly.fold.example>`
    /// keys on `weekly.fold.example`; a header with no brackets keys on its
    /// whole value; a mail with only `List-Unsubscribe` keys on its sender's
    /// address. Lowercased, because a list id and a mailbox are not case
    /// sensitive in practice. nil when there is nothing to key on.
    static func key(listID: String?, address: String?) -> String? {
        if let raw = listID?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            if let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close {
                let inner = raw[raw.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty { return inner.lowercased() }
            }
            return raw.lowercased()
        }
        guard let address = address?.trimmingCharacters(in: .whitespaces), address.contains("@")
        else { return nil }
        return address.lowercased()
    }

    /// The link to leave by, out of a `List-Unsubscribe` value: a comma list
    /// of `<…>` URIs. https first (it opens in the browser, where the sender
    /// confirms), else mailto (Mail's composer, the address filled in).
    /// Anything else — http, a bare word — is no door (§83).
    static func unsubscribeURL(from header: String?) -> URL? {
        guard let header, !header.isEmpty else { return nil }
        var uris: [String] = []
        var rest = Substring(header)
        while let open = rest.firstIndex(of: "<"),
              let close = rest[open...].firstIndex(of: ">") {
            uris.append(String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespaces))
            rest = rest[rest.index(after: close)...]
        }
        let urls = uris.compactMap(URL.init(string:))
        if let https = urls.first(where: { $0.scheme?.lowercased() == "https" }) { return https }
        if let mailto = urls.first(where: { $0.scheme?.lowercased() == "mailto" }) { return mailto }
        return nil
    }

    /// The sender's mailbox: the address the envelope gave, else the one
    /// inside a "Name <box@host>" sender (mail landed before §916 kept the
    /// address beside the name only), else a sender that is a bare address.
    static func address(_ email: String?, sender: String?) -> String? {
        if let email = email?.trimmingCharacters(in: .whitespaces), email.contains("@") { return email }
        guard let sender = sender?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let open = sender.lastIndex(of: "<"), let close = sender.lastIndex(of: ">"), open < close {
            let inner = sender[sender.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            return inner.contains("@") ? inner : nil
        }
        return sender.contains("@") && !sender.contains(" ") ? sender : nil
    }

    /// The sender's name without its mailbox: "Receipts" out of
    /// "Receipts <receipts@shop.example>". nil when nothing is left.
    static func senderName(_ sender: String?) -> String? {
        guard var name = sender?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        if let open = name.lastIndex(of: "<"), name.hasSuffix(">") {
            name = name[..<open].trimmingCharacters(in: .whitespaces)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
        return name.isEmpty ? nil : name
    }

    /// Which landed mail is a subscription's, and under which key. A mail
    /// with a list header files under its own key. A mail without one files
    /// only when the person added its sender (`added`, keyed as
    /// `key(listID: nil, address:)` keys), and then under the key that
    /// sender's headed mail already uses, so a sender added before its list
    /// headers arrived stays ONE row; else under its address. Everything else
    /// is a mail, not a subscription.
    static func file(_ landed: [Landed], added: Set<String>) -> [Mail] {
        var headed: [String: (list: String, at: Date)] = [:]
        for mail in landed {
            guard let list = mail.listKey,
                  let address = Self.key(listID: nil, address: mail.address) else { continue }
            if let standing = headed[address], standing.at >= mail.at { continue }
            headed[address] = (list, mail.at)
        }
        return landed.compactMap { mail -> Mail? in
            if let list = mail.listKey {
                return Mail(id: mail.id, key: list, sender: mail.sender ?? list, address: mail.address,
                            unsubscribe: mail.unsubscribe, at: mail.at, source: mail.source)
            }
            guard let address = Self.key(listID: nil, address: mail.address), added.contains(address)
            else { return nil }
            return Mail(id: mail.id, key: headed[address]?.list ?? address,
                        sender: mail.sender ?? address, address: mail.address,
                        unsubscribe: mail.unsubscribe, at: mail.at, source: mail.source, byYou: true)
        }
    }

    /// The senders Track a subscription offers (prd §1117): every address
    /// whose mail in the last thirty days carried no list header, that is
    /// not added already and whose mail no header puts on the tile. Most mail
    /// first, then the newest, then by name. Nothing is guessed: the person
    /// picks.
    static func candidates(_ landed: [Landed], added: Set<String>, now: Date) -> [Candidate] {
        let windowStart = now.addingTimeInterval(-windowDays * 86_400)
        var listed: Set<String> = []
        for mail in landed where mail.listKey != nil {
            if let address = Self.key(listID: nil, address: mail.address) { listed.insert(address) }
        }
        var groups: [String: [Landed]] = [:]
        for mail in landed where mail.listKey == nil && mail.at >= windowStart && mail.at <= now {
            guard let address = Self.key(listID: nil, address: mail.address),
                  !added.contains(address), !listed.contains(address) else { continue }
            groups[address, default: []].append(mail)
        }
        let out: [Candidate] = groups.compactMap { address, mails in
            let sorted = mails.sorted { $0.at > $1.at }
            guard let newest = sorted.first else { return nil }
            let name = sorted.lazy.compactMap(\.sender).first ?? address
            return Candidate(id: address, name: name, address: newest.address ?? address,
                             count: sorted.count, last: newest.at)
        }
        return out.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.last != $1.last { return $0.last > $1.last }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Group, then order: most mail in the last thirty days first, then most
    /// overall, then by name.
    static func compose(_ mails: [Mail], now: Date) -> [Item] {
        let windowStart = now.addingTimeInterval(-windowDays * 86_400)
        let groups = Dictionary(grouping: mails, by: \.key)
        let items: [Item] = groups.compactMap { key, list in
            let sorted = list.sorted { $0.at > $1.at }
            guard let newest = sorted.first, let oldest = sorted.last else { return nil }
            let link = sorted.lazy.compactMap { unsubscribeURL(from: $0.unsubscribe) }.first
            var sources: [String] = []
            for mail in sorted where !sources.contains(mail.source) { sources.append(mail.source) }
            return Item(id: key, name: newest.sender, address: newest.address ?? sorted.compactMap(\.address).first,
                        count: sorted.count,
                        lastMonth: sorted.filter { $0.at >= windowStart }.count,
                        cadenceDays: cadenceDays(sorted.map(\.at)),
                        last: newest.at, since: oldest.at,
                        unsubscribe: link, sources: sources, mailIDs: sorted.map(\.id),
                        byYou: sorted.contains(where: \.byYou),
                        arrivals: sorted.map(\.at))
        }
        return items.sorted {
            if $0.lastMonth != $1.lastMonth { return $0.lastMonth > $1.lastMonth }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The median gap between consecutive mails, in days. Three mails at
    /// least: two make one gap, which says when, not how often.
    static func cadenceDays(_ dates: [Date]) -> Double? {
        guard dates.count >= 3 else { return nil }
        let sorted = dates.sorted()
        let gaps = zip(sorted.dropFirst(), sorted).map { $0.timeIntervalSince($1) / 86_400 }.sorted()
        let mid = gaps.count / 2
        return gaps.count % 2 == 0 ? (gaps[mid - 1] + gaps[mid]) / 2 : gaps[mid]
    }

    /// How often, in words a person uses. nil without a cadence.
    static func cadenceWords(_ days: Double?) -> String? {
        guard let days else { return nil }
        switch days {
        case ..<1.5:  return String(localized: "Every day")
        case ..<4.5:  return String(localized: "Several a week")
        case ..<10:   return String(localized: "About weekly")
        case ..<21:   return String(localized: "Every two weeks")
        case ..<45:   return String(localized: "About monthly")
        default:      return String(localized: "Now and then")
        }
    }

    /// The same cadence as a sentence about the sender, for a door to the
    /// list from another page ("Writes about weekly"). Whole sentences, never
    /// a verb glued to `cadenceWords`: a language orders them its own way.
    /// Under three mails there is no cadence, and the door says only that
    /// it writes.
    static func writesWords(_ days: Double?) -> String {
        guard let days else { return String(localized: "Writes to you") }
        switch days {
        case ..<1.5:  return String(localized: "Writes every day")
        case ..<4.5:  return String(localized: "Writes several a week")
        case ..<10:   return String(localized: "Writes about weekly")
        case ..<21:   return String(localized: "Writes every two weeks")
        case ..<45:   return String(localized: "Writes about monthly")
        default:      return String(localized: "Writes now and then")
        }
    }

    /// The sheet's big figure: how many a week, or a month when fewer.
    static func rateWords(_ days: Double?) -> String? {
        rate(days).map { "\($0.count) \($0.word)" }
    }

    /// The sheet's statement in two parts, the figure and the word on its
    /// baseline, as the Wallet's "$10.00 a month": "2" · "mails a month".
    static func rate(_ days: Double?) -> (count: Int, word: String)? {
        guard let days, days > 0 else { return nil }
        let perWeek = 7 / days
        if perWeek >= 1 {
            let n = Int(perWeek.rounded())
            return (n, n == 1 ? String(localized: "mail a week") : String(localized: "mails a week"))
        }
        let n = max(1, Int((30 / days).rounded()))
        return (n, n == 1 ? String(localized: "mail a month") : String(localized: "mails a month"))
    }
}
