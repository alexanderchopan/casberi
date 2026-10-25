import Foundation

/// **A WARNING IS ONE LINE YOU CAN SIGN PAST (prd §1509 item 2, Phase 2 of
/// `docs/signing-safety-spec.md`).** What Move finds wrong with a sentence
/// takes the grey line's place, in amber (check it) or red (reported), and
/// the verb becomes "Send anyway" / "Swap anyway": the first tap arms it, the
/// second signs. Walletbeat's rule, warn rather than block; it amends
/// §1438b's block on a lookalike. A first send to an address is only a note
/// and the verb stays; a send the simulation refuses dims its verb.
///
/// Pure (Foundation): the findings, their order, their words, the guard on a
/// downloaded list and the readers of the two services' answers, held by
/// `move-warnings-selftest.sh`. The reads are `MoveChecks`'.
enum MoveWarnings {

    /// A contract younger than this is "new" (prd §1510's Phase 2 entry).
    static let newContractDays = 30

    enum Finding: Equatable, Sendable {
        /// The simulation refuses it (Phase 1): its red line, the verb dimmed.
        case fails(String)
        /// A reporting service flags the address: GoPlus, naming its sources.
        case scam(address: String, sources: String)
        /// On OFAC's list, matched on the phone; `listed` is the list's date.
        case sanctioned(address: String, listed: Date?)
        /// Looks like an address you know (the same "…9cD0"): one you paid,
        /// with the newest day you paid it, or one you named in the book.
        case lookalike(of: String, name: String?, paid: Date?)
        /// A swap's token or a send's recipient that is a contract: not on
        /// Relay's list, younger than `newContractDays`, never used by you.
        case contract(token: Bool, unverified: Bool, ageDays: Int?, neverUsed: Bool)
        /// You have never sent to this address. A note: the verb stays.
        case firstSend

        var red: Bool {
            switch self {
            case .fails, .scam, .sanctioned: true
            case .lookalike, .contract, .firstSend: false
            }
        }

        /// Turns the verb into "Send anyway": every warning but a note, and
        /// but a refusal, which dims the verb instead.
        var arms: Bool {
            switch self {
            case .fails, .firstSend: false
            default: true
            }
        }
    }

    /// One line only, red over amber, then the order they are listed in
    /// (prd §1509 item 2, the spec's item 7): a refusal first, then a
    /// reported or sanctioned address, a lookalike, a new contract, and the
    /// first-send note last. Details lists every one.
    static func ordered(_ findings: [Finding]) -> [Finding] {
        func rank(_ f: Finding) -> Int {
            switch f {
            case .fails: 0
            case .sanctioned: 1
            case .scam: 2
            case .lookalike: 3
            case .contract: 4
            case .firstSend: 5
            }
        }
        return findings.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// The finding that speaks, and whether the verb reads "anyway".
    static func lead(_ findings: [Finding]) -> Finding? { ordered(findings).first }
    static func arms(_ findings: [Finding]) -> Bool { findings.contains(where: \.arms) && !findings.contains { if case .fails = $0 { true } else { false } } }

    // MARK: - The words

    /// The line a finding draws. `short` writes an address the way a line of
    /// words does ("0x71C7…49A2"), `day` a date ("Oct 3").
    static func line(_ f: Finding, short: (String) -> String, day: (Date) -> String) -> String {
        switch f {
        case .fails(let words):
            return words
        case .scam:
            return String(localized: "Reported as a scam address.")
        case .sanctioned:
            return String(localized: "On the US sanctions list.")
        case .lookalike(let real, let name, let paid):
            if let name { return String(localized: "Looks like \(name)'s — check it") }
            if let paid {
                return String(localized: "Looks like \(short(real)), which you paid on \(day(paid)). They differ in the middle. Check it.")
            }
            return String(localized: "Looks like \(short(real)), one of yours. They differ in the middle. Check it.")
        case .contract(let token, let unverified, let ageDays, let neverUsed):
            return contractLine(token: token, unverified: unverified, ageDays: ageDays, neverUsed: neverUsed) ?? ""
        case .firstSend:
            return String(localized: "First send to this address.")
        }
    }

    /// A contract worth a second look: not on Relay's list, or younger than
    /// thirty days. "Never used" alone warns about nothing (every first
    /// swap into a well-known token is one); it rides a young contract.
    static func contractLine(token: Bool, unverified: Bool, ageDays: Int?, neverUsed: Bool) -> String? {
        let young = ageDays.map { $0 < newContractDays } ?? false
        guard unverified || young else { return nil }
        var parts: [String] = []
        if unverified { parts.append(String(localized: "Not verified by Relay.")) }
        if young, let days = ageDays {
            let age = days < 1 ? String(localized: "less than a day old")
                : days == 1 ? String(localized: "a day old") : String(localized: "\(days) days old")
            switch (token, neverUsed) {
            case (true, true): parts.append(String(localized: "Its contract is \(age), and you've never used it."))
            case (true, false): parts.append(String(localized: "Its contract is \(age)."))
            case (false, true): parts.append(String(localized: "This address is a contract \(age), and you've never sent to it."))
            case (false, false): parts.append(String(localized: "This address is a contract \(age)."))
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - What you know

    /// Known: an address this account has sent to, a name you gave in the
    /// book, one of your own accounts. Never one you only RECEIVED from:
    /// that is exactly what a poisoner controls (`WalletSafety`'s rule).
    static func isKnown(_ address: String, sentTo: [String: Date], named: Set<String>, own: Set<String>) -> Bool {
        let a = address.lowercased()
        return sentTo[a] != nil || named.contains(a) || own.contains(a)
    }

    /// The known address `typed` imitates: the same display form, a
    /// different address (`AddressSafety.isLookalike`, passed in as
    /// `looksLike`). A paid one wins over a named one when both match, and
    /// among paid ones the newest.
    static func imitated(_ typed: String, sentTo: [String: Date], named: [String: String], own: Set<String>,
                         looksLike: (String, String) -> Bool) -> Finding? {
        let paid = sentTo.filter { looksLike(typed, $0.key) }.max { $0.value < $1.value }
        if let paid { return .lookalike(of: paid.key, name: nil, paid: paid.value) }
        if let name = named.first(where: { looksLike(typed, $0.key) }) { return .lookalike(of: name.key, name: name.value, paid: nil) }
        if let mine = own.first(where: { looksLike(typed, $0) }) { return .lookalike(of: mine, name: nil, paid: nil) }
        return nil
    }

    // MARK: - OFAC's list (0xB10C/ofac-sanctioned-digital-currency-addresses)

    /// The list as published: a JSON array of Ethereum addresses. nil for
    /// anything else, or for any entry that is not one.
    static func ofacList(_ data: Data) -> [String]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [String], !list.isEmpty else { return nil }
        let out = list.map { $0.lowercased() }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard out.allSatisfy({ $0.count == 42 && $0.hasPrefix("0x") && $0.dropFirst(2).unicodeScalars.allSatisfy(hex.contains) })
        else { return nil }
        return out
    }

    /// A fresh copy replaces the kept one only when it parsed and is not
    /// sharply smaller: a list that loses more than a quarter of its
    /// addresses in a day is a broken fetch, not a pardon.
    static func accepts(_ fresh: [String]?, over kept: Int) -> Bool {
        guard let fresh, !fresh.isEmpty else { return false }
        return kept == 0 || fresh.count * 4 >= kept * 3
    }

    // MARK: - GoPlus (api.gopluslabs.io, address_security)

    /// What GoPlus said about an address: reported, and whose report.
    struct Report: Equatable, Sendable {
        let reported: Bool
        let sources: String
    }

    /// The flags that mean a report of theft or fraud. `blacklist_doubt`
    /// (a suspicion), `mixer`, `gas_abuse` and `reinit` are not reports.
    static let reportFlags = ["phishing_activities", "stealing_attack", "cybercrime", "money_laundering",
                              "financial_crime", "blackmail_activities", "fake_kyc", "honeypot_related_address",
                              "darkweb_transactions", "fake_token", "malicious_mining_activities"]

    /// GoPlus's answer read strictly: `code` 1 and a result object, else nil
    /// (not checked, never clean).
    static func report(_ data: Data) -> Report? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int) == 1, let r = root["result"] as? [String: Any] else { return nil }
        let reported = reportFlags.contains { (r[$0] as? String) == "1" }
            || ((r["number_of_malicious_contracts_created"] as? String).flatMap(Int.init) ?? 0) > 0
        let sources = (r["data_source"] as? String) ?? ""
        return Report(reported: reported, sources: sources.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))
    }

    // MARK: - Blockscout (getcontractcreation)

    /// When a contract was made, off Blockscout's legacy `getcontractcreation`
    /// (measured 2026-10-24: answers through Tor on Base, Ethereum and
    /// Robinhood where its v2 API sits behind a Cloudflare wall): the
    /// creation's time, or `.notContract` for an empty result. nil when the
    /// answer cannot be read.
    enum Creation: Equatable, Sendable {
        case at(Date)
        case notContract
    }

    static func creation(_ data: Data) -> Creation? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? String) == "1" || (root["message"] as? String) == "OK",
              let result = root["result"] as? [[String: Any]] else { return nil }
        guard let first = result.first else { return .notContract }
        guard let stamp = (first["timestamp"] as? String).flatMap(TimeInterval.init) else { return nil }
        return .at(Date(timeIntervalSince1970: stamp))
    }

    /// Whole days from `created` to `now`.
    static func ageDays(_ created: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(created) / 86_400))
    }
}
