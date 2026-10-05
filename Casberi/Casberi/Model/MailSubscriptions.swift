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
                        unsubscribe: link, sources: sources, mailIDs: sorted.map(\.id))
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

    /// The sheet's big figure: how many a week, or a month when fewer.
    static func rateWords(_ days: Double?) -> String? {
        guard let days, days > 0 else { return nil }
        let perWeek = 7 / days
        if perWeek >= 1 {
            return String(localized: "\(Int(perWeek.rounded())) a week")
        }
        return String(localized: "\(max(1, Int((30 / days).rounded()))) a month")
    }
}
