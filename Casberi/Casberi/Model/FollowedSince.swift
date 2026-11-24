import Foundation

/// **WHAT A WALLET YOU FOLLOW DID SINCE YOU LAST LOOKED (prd §1969).**
/// Following's rows and a followed wallet's page say one line of news, never
/// its balance first: "Swapped ETH for USDC · Deposited USDC into Morpho",
/// or "Nothing new since Tuesday".
///
/// Foundation-only: `scripts/followed-since-selftest.sh` compiles it whole
/// with `WalletRowWords` and `TitleSeam`.
enum FollowedSince {
    /// One landed row of a followed wallet, reduced to what the line reads.
    struct Move: Equatable {
        let title: String
        let at: Date
    }

    /// How many phrases the line names before "N more".
    static let phrases = 3

    /// The line, newest first; nil when nothing happened since.
    static func line(_ moves: [Move]) -> String? {
        var said: [String] = []
        var extra = 0
        for move in moves.sorted(by: { $0.at > $1.at }) {
            guard let phrase = phrase(move.title), !said.contains(phrase) else { continue }
            if said.count < phrases { said.append(phrase) } else { extra += 1 }
        }
        guard !said.isEmpty else { return nil }
        if extra > 0 { said.append(extra == 1 ? String(localized: "1 more") : String(localized: "\(extra) more")) }
        return said.joined(separator: " · ")
    }

    /// One move in a few words, its amount left to its row: "Swapped ETH for
    /// USDC", "Deposited USDC into Morpho", "Received ETH from Mom".
    static func phrase(_ title: String) -> String? {
        if let swap = WalletRowWords.swap(title) { return swap.name }
        let name = TitleSeam.split(title).name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        // "Moved 2 ETH · Main → Cold": two of their accounts, said as a move.
        if name.hasPrefix("Moved "), let dot = name.range(of: " · ") {
            return dropAmount(String(name[..<dot.lowerBound]))
        }
        return dropAmount(name)
    }

    /// "Deposited 480,000 USDC into Morpho" → "Deposited USDC into Morpho":
    /// the word after the verb goes when it is a number.
    static func dropAmount(_ sentence: String) -> String {
        var words = sentence.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 3 else { return sentence }
        // A money figure ("$246.31") is the sentence's object, never an
        // amount beside a token: "Settled $246.31 of card spending" keeps it.
        let amount = words[1].replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "~≈<>"))
        if !amount.isEmpty, amount.allSatisfy({ $0.isNumber || $0 == "." }),
           amount.contains(where: \.isNumber) {
            words.remove(at: 1)
        }
        return words.joined(separator: " ")
    }

    /// The tail of "Since …" and "Nothing new since …": "earlier today",
    /// "yesterday", a weekday within the week, else the date.
    static func since(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "earlier today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "yesterday") }
        let format = DateFormatter()
        format.calendar = calendar
        format.locale = Locale.current
        if now.timeIntervalSince(date) < 6 * 86_400 {
            format.setLocalizedDateFormatFromTemplate("EEEE")
        } else {
            format.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return format.string(from: date)
    }

    /// "Since Tuesday", capitalised for a line of its own.
    static func sinceHead(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        String(localized: "Since \(since(date, now: now, calendar: calendar))")
    }

    /// "Nothing new since Tuesday".
    static func nothingNew(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        String(localized: "Nothing new since \(since(date, now: now, calendar: calendar))")
    }

    /// What the wallet's money did since `date`, off its recorded samples:
    /// the newest less the last at or before `date`. Nil with no sample
    /// before, or none after.
    static func change(_ samples: [(at: Date, usd: Double)], since date: Date) -> Double? {
        let ordered = samples.sorted { $0.at < $1.at }
        guard let base = ordered.last(where: { $0.at <= date }),
              let latest = ordered.last, latest.at > base.at else { return nil }
        return latest.usd - base.usd
    }

    /// When a wallet never opened counts from: a week back.
    static let firstLook: TimeInterval = 7 * 86_400
}
