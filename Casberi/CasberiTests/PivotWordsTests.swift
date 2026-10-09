import Foundation
import Testing
@testable import Casberi

/// **Generative search's words, resolved with no model** (prd §1209,
/// `Model/PivotWords.swift`). A time phrase must come out of the words
/// whole and on word boundaries, and what is left is what the page is about.
struct PivotWordsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()
    /// Friday, 9 October 2026, noon UTC.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))! }

    @Test func lastWeekLeavesTheSubject() throws {
        let found = try #require(PivotWords.timeSpan(in: "Spotify last week", now: now, calendar: cal))
        #expect(found.rest == "spotify")
        #expect(found.label == "Last week")
        #expect(found.span.contains(cal.date(from: DateComponents(year: 2026, month: 9, day: 30))!))
        #expect(!found.span.contains(now))
    }

    @Test func aPhraseAloneIsTheWholePage() throws {
        let found = try #require(PivotWords.timeSpan(in: "yesterday", now: now, calendar: cal))
        #expect(found.rest.isEmpty)
        #expect(found.span.contains(cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9))!))
    }

    @Test func aJoinerBeforeThePhraseGoes() throws {
        let found = try #require(PivotWords.timeSpan(in: "uma in last month", now: now, calendar: cal))
        #expect(found.rest == "uma")
        #expect(found.label == "Last month")
    }

    @Test func aMonthNotYetComeIsLastYears() throws {
        let found = try #require(PivotWords.timeSpan(in: "december", now: now, calendar: cal))
        #expect(cal.component(.year, from: found.span.start) == 2025)
        let march = try #require(PivotWords.timeSpan(in: "march", now: now, calendar: cal))
        #expect(cal.component(.year, from: march.span.start) == 2026)
    }

    @Test func wordsInsideWordsAreNotTime() {
        // "may" inside "maybe", "today" inside "todayish": no span.
        #expect(PivotWords.timeSpan(in: "maybe later", now: now, calendar: cal) == nil)
        #expect(PivotWords.timeSpan(in: "todayish", now: now, calendar: cal) == nil)
        #expect(PivotWords.timeSpan(in: "budget", now: now, calendar: cal) == nil)
    }

    @Test func theLongerPhraseWins() throws {
        // "last week" is a phrase of its own, never "week" with "last" left over.
        let found = try #require(PivotWords.timeSpan(in: "last week", now: now, calendar: cal))
        #expect(found.rest.isEmpty)
    }

    @Test func anEventCountsByWhenItIs() {
        let span = DateInterval(start: now, duration: 86_400)
        let before = now.addingTimeInterval(-86_400 * 3)
        #expect(PivotWords.inSpan(span, captured: before, due: now.addingTimeInterval(3_600)))
        #expect(!PivotWords.inSpan(span, captured: before, due: nil))
        #expect(PivotWords.inSpan(nil, captured: before, due: nil))
    }

    @Test func aQueryNamesItsOwnPage() {
        let q = PivotQuery(subject: .app("Spotify"), span: nil, spanLabel: "Last week")
        #expect(q.title == "Spotify")
        #expect(q.pick == "Last week")
        #expect(PivotQuery(subject: .span, spanLabel: "Today").title == "Today")
        #expect(PivotQuery(subject: .span, spanLabel: "Today").pick == nil)
    }
}
