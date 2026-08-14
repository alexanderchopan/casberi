import Foundation

/// The join link on a meeting, dug out of wherever the invite put it
/// (2026-08-14).
///
/// **EventKit publishes no conference URL.** `EKVirtualConferenceDescriptor`
/// looks like the answer and is the opposite of it: that is a PROVIDER API — a
/// hook for an app that supplies conference rooms through an extension — with
/// no read side at all. Nothing on `EKEvent` says "this meeting is at this
/// URL". So the link has to be found, and the three places it lives are the
/// three fields this reads:
///
///   · `event.url` — Apple's own FaceTime links, and some CalDAV servers.
///   · `location` — Google Calendar routinely files the Meet link here, which
///     is also why `ScheduleIngest` must not hand every location to Maps.
///   · `notes` — the common case by a wide margin. Zoom, Teams and Webex all
///     paste the join link into the invite body.
///
/// **The host allowlist is a security boundary, not a convenience.** `notes` is
/// text a stranger wrote — anyone who can send you an invite can put a URL in
/// it — and whatever comes out of here becomes `externalLink`, which the thing
/// sheet turns into a one-tap "Join" disc. An open extractor would hand that
/// disc to the first link in a phishing invite. So: http(s) only, and a fixed
/// list of hosts that are conference services, matched on the LABEL BOUNDARY
/// (`OEmbed.endpoints`' rule — `zoom.us.attacker.example` must not match).
///
/// Foundation-only on purpose: it takes three strings rather than an `EKEvent`,
/// so `scripts/calendar-selftest.sh` compiles it WHOLE and unmodified.
enum ConferenceLink {

    /// Conference services, by registrable host. An entry means "a link on this
    /// host is a way to join a call" — nothing weaker, since the payoff for
    /// being on this list is a tap target on text somebody else wrote.
    ///
    /// Suffixes, so `us02web.zoom.us` and `acme.webex.com` match their entry
    /// without one line per tenant.
    static let hosts: [String] = [
        "zoom.us", "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
        "whereby.com",
        "jit.si",
        "chime.aws",
        "gotomeeting.com", "gotomeet.me",
        "bluejeans.com",
        "facetime.apple.com",
        "join.skype.com",
        "around.co",
        "riverside.fm",
    ]

    /// Path fragments that mark a link as the JOIN link rather than some other
    /// page on the same service. They rank, they never gate — a Meet link is
    /// bare (`meet.google.com/abc-defg-hij`) and would be excluded by any
    /// requirement here.
    ///
    /// The case they earn their place on is a Teams invite, which carries the
    /// join link AND `…/meetingOptions/…` on the same host: without ranking,
    /// whichever the organizer's template printed first would win, and a "Join"
    /// disc that opens the settings page is the §83 fake status.
    private static let joinMarkers = ["/j/", "/meetup-join", "/join", "/my/",
                                      "/wbxmjs/", "/meet/"]

    /// Whether a URL is a way to join a call. The one gate every caller shares
    /// — the sheet re-asks it before drawing the disc, so a link stored by an
    /// older build under looser rules can never become a tap target now.
    static func isConference(_ url: URL) -> Bool {
        guard url.scheme == "https" || url.scheme == "http",
              let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The best join link across an event's three fields, or nil.
    ///
    /// Ordered by how much the field means it: a URL somebody put in the URL
    /// field beats one in the location field, which beats one buried in the
    /// body. Within a field, a link wearing a join marker beats one that isn't.
    static func best(url: String?, location: String?, notes: String?) -> String? {
        var best: (tier: Int, value: String)?
        for (field, text) in [(0, url), (1, location), (2, notes)] {
            guard let text, !text.isEmpty else { continue }
            for candidate in urls(in: text) where isConference(candidate) {
                let marked = joinMarkers.contains {
                    candidate.path.lowercased().contains($0)
                } ? 0 : 1
                // Field first, marker second — a bare Meet link in the location
                // field is still a better answer than a marked one three
                // paragraphs into somebody's footer.
                let tier = field * 2 + marked
                if best == nil || tier < best!.tier {
                    best = (tier, candidate.absoluteString)
                }
            }
        }
        return best?.value
    }

    /// Every http(s) URL in a piece of text, in reading order.
    ///
    /// `NSDataDetector` rather than a hand-rolled scan: it already knows where
    /// a URL ends, which is the part that goes wrong by hand — a link followed
    /// by a full stop, wrapped in angle brackets, or broken across lines by the
    /// sender's mail client.
    ///
    /// The scan is CAPPED. An invite body is arbitrary third-party text and
    /// this runs for every event on every foreground; 20k characters is far
    /// past any real invite and bounds a pathological one.
    static func urls(in text: String) -> [URL] {
        let scanned = text.count > scanCap ? String(text.prefix(scanCap)) : text
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(scanned.startIndex..., in: scanned)
        return detector.matches(in: scanned, range: range).compactMap { match in
            guard let url = match.url,
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            return url
        }
    }

    static let scanCap = 20_000

    /// Whether a location field is really a link rather than a place — the
    /// reason `ScheduleIngest` can't hand every location to Maps. A Meet URL
    /// filed as the location used to render as a "Where" row whose tap ran a
    /// Maps SEARCH for `https://meet.google.com/…`.
    ///
    /// Deliberately narrow: it asks whether the WHOLE trimmed value is a URL,
    /// so "Room 4 (backup: meet.google.com/abc)" stays a place, which is what
    /// it is. A bare `meet.google.com/abc` with no scheme counts — that is how
    /// people paste them — which is why this asks the detector rather than
    /// `URL(string:)`, which accepts almost any string.
    static func isLink(_ location: String) -> Bool {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        return urls(in: trimmed).first?.absoluteString.isEmpty == false
    }

    /// A location that is a link, as a URL — nil when it is a place.
    static func locationURL(_ location: String) -> URL? {
        guard isLink(location) else { return nil }
        return urls(in: location.trimmingCharacters(in: .whitespacesAndNewlines)).first
    }
}

/// "Every Tuesday" — a repeating event's cadence in words (2026-08-14).
///
/// `ScheduleIngest` collapses a whole series to ONE row (see its own doc), so
/// the row's date says when the next one is and nothing said that there were
/// going to be more. The rule was in hand the whole time —
/// `EKCalendarItem.recurrenceRules` rides the same fetch.
///
/// Foundation-only: `ScheduleIngest` maps EventKit's enum onto `Cadence` with a
/// compiler-checked switch and hands over this value, so the phrasing can be
/// compiled and asserted by the harness with no EventKit at all.
struct RecurrenceShape: Equatable {
    enum Cadence: Equatable { case daily, weekly, monthly, yearly }

    var cadence: Cadence
    /// 1 = every, 2 = every other, n = every n. EventKit's own floor is 1.
    var interval: Int = 1
    /// 1 = Sunday … 7 = Saturday, matching both `EKWeekday` and `Calendar`'s
    /// `weekday` component, which is what lets the symbol lookup below be a
    /// plain index rather than a mapping table.
    var weekdays: [Int] = []
}

enum RecurrencePhrase {

    /// The cadence as a sentence-case phrase, or nil when there is nothing
    /// worth saying.
    ///
    /// A weekly rule naming ONE day says the day ("Every Tuesday"), because
    /// that is how people describe it. A weekly rule naming several is left at
    /// "Every week" rather than listing them — the honest short form; a row
    /// reading "Every Monday, Tuesday, Wednesday, Thursday and Friday" is a
    /// sentence you have to parse to learn something you already knew from the
    /// dates. An interval above 1 always suppresses the day name, since
    /// "Every other Tuesday" and "Every 3 weeks on Tuesday" are different
    /// claims and only one of them is derivable here.
    static func text(_ shape: RecurrenceShape) -> String? {
        let interval = max(1, shape.interval)
        // Never `String(localized: "… \(interval) …")` with a bare Int: an
        // interpolated integer is GROUPED, which is how "2019 was your loudest
        // year" shipped as "2,019" (prd §375). Small numbers do not group
        // today; the formatter makes that true by construction rather than by
        // luck.
        let n = interval.formatted(.number.grouping(.never))
        switch (shape.cadence, interval) {
        case (.daily, 1):   return String(localized: "Every day")
        case (.daily, 2):   return String(localized: "Every other day")
        case (.daily, _):   return String(localized: "Every \(n) days")
        case (.weekly, 1):
            if let day = weekdayName(shape.weekdays) {
                return String(localized: "Every \(day)")
            }
            return String(localized: "Every week")
        case (.weekly, 2):  return String(localized: "Every other week")
        case (.weekly, _):  return String(localized: "Every \(n) weeks")
        case (.monthly, 1): return String(localized: "Every month")
        case (.monthly, 2): return String(localized: "Every other month")
        case (.monthly, _): return String(localized: "Every \(n) months")
        case (.yearly, 1):  return String(localized: "Every year")
        case (.yearly, 2):  return String(localized: "Every other year")
        case (.yearly, _):  return String(localized: "Every \(n) years")
        }
    }

    /// The one named day, or nil when the rule names none or several.
    /// `weekdaySymbols` is the CURRENT locale's, so this is the reader's own
    /// word for the day and never a translated English one.
    private static func weekdayName(_ weekdays: [Int]) -> String? {
        guard weekdays.count == 1, let day = weekdays.first,
              (1...7).contains(day) else { return nil }
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.count == 7 else { return nil }
        return symbols[day - 1]
    }
}
