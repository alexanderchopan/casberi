import Foundation

/// A calendar file read off the network (prd §1137): the subscribed
/// calendar's name and its events, parsed from iCalendar text (RFC 5545).
///
/// Pure Foundation, so `calendar-ics-selftest.sh` compiles it alone. It reads
/// what a published calendar actually carries — holidays, a team's fixtures,
/// a shared work calendar — and nothing it cannot honestly expand: a simple
/// repeat (daily, weekly, monthly, yearly, with an interval, a count, an end
/// and weekdays for a weekly rule) is expanded inside the window; a rule it
/// does not understand yields its first occurrence only, never a guess.
enum CalendarICS {
    struct Event: Equatable {
        /// The event's UID, plus the occurrence's start for a repeat, so each
        /// occurrence is its own row and a re-read finds the same one.
        let id: String
        let title: String
        let start: Date
        let end: Date?
        let allDay: Bool
        let location: String?
        let notes: String?
        let url: URL?
    }

    struct Calendar: Equatable {
        let name: String?
        let events: [Event]
    }

    /// Parse `text`, keeping occurrences that END on or after `from` and
    /// START before `until`, soonest first, at most `limit`.
    static func parse(_ text: String, from: Date, until: Date, limit: Int = 500) -> Calendar {
        let lines = unfold(text)
        var name: String?
        var events: [Event] = []
        var block: [(key: String, params: [String: String], value: String)]?
        for line in lines {
            if line == "BEGIN:VEVENT" { block = []; continue }
            if line == "END:VEVENT" {
                if let props = block { events += occurrences(props, from: from, until: until) }
                block = nil
                continue
            }
            guard let prop = property(line) else { continue }
            if block != nil {
                block?.append(prop)
            } else if prop.key == "X-WR-CALNAME", name == nil {
                let n = unescape(prop.value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { name = n }
            }
        }
        events.sort { $0.start < $1.start }
        return Calendar(name: name, events: Array(events.prefix(limit)))
    }

    // MARK: - Lines

    /// RFC 5545 §3.1: a line starting with a space or a tab continues the one
    /// before it.
    static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in raw.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !out.isEmpty {
                out[out.count - 1] += String(line.dropFirst())
            } else if !line.isEmpty {
                out.append(line)
            }
        }
        return out
    }

    /// `NAME;PARAM=V;PARAM2="V":value` → key, params, value. The value is
    /// everything after the first colon outside quotes.
    static func property(_ line: String) -> (key: String, params: [String: String], value: String)? {
        var inQuote = false
        var split: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuote.toggle() }
            if c == ":" && !inQuote { split = i; break }
        }
        guard let colon = split else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: false)
        guard let key = parts.first, !key.isEmpty else { return nil }
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (key.uppercased(), params, value)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Dates

    /// `20261006` (a day), `20261006T120000Z` (UTC), `20261006T120000` with
    /// a TZID (that zone) or without one (floating: the phone's zone).
    static func date(_ value: String, params: [String: String]) -> (date: Date, allDay: Bool)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let digits = v.filter(\.isNumber)
        if params["VALUE"] == "DATE" || (v.count == 8 && digits.count == 8) {
            guard digits.count >= 8,
                  let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
                  let d = Int(digits.dropFirst(6).prefix(2)),
                  let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
            return (date, true)
        }
        guard digits.count >= 14,
              let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)), let h = Int(digits.dropFirst(8).prefix(2)),
              let mi = Int(digits.dropFirst(10).prefix(2)), let s = Int(digits.dropFirst(12).prefix(2))
        else { return nil }
        if v.hasSuffix("Z") {
            cal.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid) {
            cal.timeZone = zone
        }
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))
        else { return nil }
        return (date, false)
    }

    // MARK: - Events

    private static func occurrences(_ props: [(key: String, params: [String: String], value: String)],
                                    from: Date, until: Date) -> [Event] {
        func first(_ key: String) -> (params: [String: String], value: String)? {
            props.first { $0.key == key }.map { ($0.params, $0.value) }
        }
        if first("STATUS")?.value.uppercased() == "CANCELLED" { return [] }
        guard let startProp = first("DTSTART"),
              let (start, allDay) = date(startProp.value, params: startProp.params) else { return [] }
        let end = first("DTEND").flatMap { date($0.value, params: $0.params)?.date }
        let length = end.map { $0.timeIntervalSince(start) } ?? (allDay ? 86_400 : 0)
        let uid = first("UID")?.value ?? "\(start.timeIntervalSince1970)-\(first("SUMMARY")?.value ?? "")"
        let title = unescape(first("SUMMARY")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        let notes = first("DESCRIPTION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        let url = first("URL").flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) }
        var excluded = Set<Date>()
        for p in props where p.key == "EXDATE" {
            for v in p.value.split(separator: ",") {
                if let d = date(String(v), params: p.params)?.date { excluded.insert(d) }
            }
        }

        let starts: [Date]
        if let rule = first("RRULE")?.value {
            starts = expand(rule: rule, start: start, length: length, from: from, until: until)
        } else {
            starts = [start]
        }
        let repeats = first("RRULE") != nil
        return starts.compactMap { s in
            guard !excluded.contains(s) else { return nil }
            let e = s.addingTimeInterval(length)
            guard max(e, s) >= from, s < until else { return nil }
            let id = repeats ? "\(uid)@\(Int(s.timeIntervalSince1970))" : uid
            return Event(id: id, title: title.isEmpty ? "Event" : title, start: s,
                         end: end == nil ? nil : e, allDay: allDay,
                         location: location, notes: notes, url: url)
        }
    }

    /// The starts a repeat rule yields inside the window. FREQ of DAILY,
    /// WEEKLY, MONTHLY or YEARLY with INTERVAL, COUNT, UNTIL, and BYDAY on a
    /// weekly rule; any other BY* part means "not understood": the first
    /// occurrence only.
    static func expand(rule: String, start: Date, length: TimeInterval, from: Date, until: Date) -> [Date] {
        var parts: [String: String] = [:]
        for p in rule.split(separator: ";") {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]) }
        }
        let understood: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        guard let freq = parts["FREQ"]?.uppercased(),
              Set(parts.keys).isSubset(of: understood),
              parts["BYDAY"] == nil || freq == "WEEKLY" else { return [start] }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let count = parts["COUNT"].flatMap(Int.init)
        let end = parts["UNTIL"].flatMap { date($0, params: [:])?.date }
        let cal = Foundation.Calendar(identifier: .gregorian)
        let component: Foundation.Calendar.Component
        switch freq {
        case "DAILY": component = .day
        case "WEEKLY": component = .weekOfYear
        case "MONTHLY": component = .month
        case "YEARLY": component = .year
        default: return [start]
        }
        let weekdays: [Int]? = parts["BYDAY"].map { list in
            let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            return list.split(separator: ",").compactMap { map[String($0.suffix(2)).uppercased()] }.sorted()
        }
        var out: [Date] = []
        var made = 0
        var step = 0
        // A hard ceiling on steps, so a rule from 1970 cannot spin.
        while step < 5_000 {
            guard let base = cal.date(byAdding: component, value: step * interval, to: start) else { break }
            var candidates = [base]
            if let days = weekdays, !days.isEmpty {
                let weekStart = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: base) - 1), to: base) ?? base
                candidates = days.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: weekStart) }
                    .filter { $0 >= start }
            }
            for c in candidates {
                if let e = end, c > e { return out }
                if let n = count, made >= n { return out }
                made += 1
                if c >= until { return out }
                if c.addingTimeInterval(length) >= from { out.append(c) }
            }
            step += 1
        }
        return out
    }
}
