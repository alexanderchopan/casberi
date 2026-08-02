import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a screenshot is ABOUT to make you do (prd §282, 2026-08-02) — the
/// appointment in the confirmation email you screenshotted, the date on the
/// ticket, the time somebody sent you. The text is already on the device
/// (`ScreenshotOCR` wrote it into `content`); nothing has ever read it for a
/// DEADLINE, so the most useful thing in a screenshot library has been sitting
/// in plain text, unlooked-at, since OCR shipped.
///
/// **The split is the whole design, and it is not negotiable: the DATE is
/// deterministic, the LABEL is the model's.** `NSDataDetector` finds the
/// moment — a real parser, the same one Mail and Messages use, which cannot
/// invent a Tuesday — and the on-device model is asked only to name what the
/// moment is FOR, in a few words, or to decline. A model that hallucinates a
/// date puts a person at the wrong place on the wrong day; a model that
/// hallucinates a label is merely unhelpful, and the deterministic fallback
/// (the thing's own title) is right there. So the risky half is never the
/// model's to answer.
///
/// Nothing here writes. A fact becomes a HAND-OFF — copy the words, open
/// Calendar on that day — which is the standing ruling for Calendar and
/// Reminders (`HandOff`, "We don't write"). The app does not put an event in
/// anyone's calendar because it read a picture.
enum ScreenshotFacts {

    struct Fact: Identifiable, Equatable {
        let date: Date
        /// What the moment is for. The model's few words when it had them,
        /// else the thing's own title — never empty.
        var label: String
        var id: Date { date }
    }

    // MARK: - Dates (deterministic)

    /// A bare clock — "9:41", "12.05 AM". Present in the status bar of very
    /// nearly every iOS screenshot, and never an appointment. `NSDataDetector`
    /// happily resolves one to today at that time, which is why this rejection
    /// has to happen on the MATCHED TEXT rather than on the resulting date:
    /// by the time it's a `Date` it looks exactly like a real 9:41 meeting.
    private static let bareClock = /^\d{1,2}[:.]\d{2}(\s?[APap]\.?[Mm]\.?)?$/

    /// The upcoming moments named in a piece of text, soonest first, capped.
    ///
    /// Only the FUTURE qualifies. A screenshot's text is thick with past dates
    /// — a receipt, a message timestamp, a copyright line — and none of them
    /// is something to put on a calendar. `reference` is injectable so the
    /// pure logic can be exercised without waiting for a real Tuesday.
    static func dates(in text: String, reference: Date = .now, limit: Int = 2) -> [Date] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return [] }
        let ns = text as NSString
        var found: [Date] = []
        detector.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            guard let match, let date = match.date else { return }
            let matched = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard matched.wholeMatch(of: bareClock) == nil else { return }
            guard date > reference else { return }
            // A moment more than a year out is nearly always a misparse (a
            // version number, an order id) rather than a plan.
            guard date < reference.addingTimeInterval(365 * 86_400) else { return }
            if !found.contains(date) { found.append(date) }
            if found.count >= limit { stop.pointee = true }
        }
        return found.sorted()
    }

    // MARK: - Facts

    /// The upcoming moments in a thing's own text, each named. The dates come
    /// back immediately; the naming is one model call for the whole set (not
    /// one per date), and the deterministic titles stand if it declines.
    static func facts(for thing: Thing) async -> [Fact] {
        guard thing.isLive else { return [] }
        let text = thing.content
        let dates = dates(in: text)
        guard !dates.isEmpty else { return [] }
        let fallback = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var facts = dates.map { Fact(date: $0, label: fallback.isEmpty ? "Saved moment" : fallback) }
        if let named = await label(for: text), !named.isEmpty {
            for i in facts.indices { facts[i].label = named }
        }
        return facts
    }

    /// The on-device model's few words for what this screenshot's upcoming
    /// moment is for. nil when the model is unavailable or declines — and it
    /// is told, in as many words, that declining is allowed, because "an
    /// appointment" is worse than the screenshot's own title.
    static func label(for text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await ScreenshotFactModel.label(for: text)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

/// The model's answer for what a screenshot's upcoming moment is called. One
/// field, file-scope (never nested — a nested `@Generable` emits broken
/// keypaths and corrupts the heap; CLAUDE.md).
@available(iOS 26.0, *)
@Generable
struct ScreenshotFactLayout {
    @Guide(description: "Three to six plain words naming what the upcoming appointment, booking, or event in this text is for — for example 'Dentist appointment' or 'Flight to Lisbon'. If the text does not clearly describe one, the single word NONE.")
    var label: String
}

@available(iOS 26.0, *)
enum ScreenshotFactModel {
    @MainActor
    static func label(for text: String) async -> String? {
        guard OnDeviceModel.isAvailable else { return nil }
        let excerpt = String(text.prefix(1200))
        // A throwaway session, never the composer's `ConversationModel`: this
        // is not a turn in anybody's conversation, and letting it into that
        // transcript would leak a screenshot's text into the next Ask.
        let session = LanguageModelSession(instructions: """
        You read text taken from a screenshot and name, in a few plain words, \
        what upcoming appointment or event it describes. Use only the words in \
        the text. Never invent a place, a person, or a purpose. Never write a \
        date or a time — those are read separately and yours would be ignored. \
        No preamble, no punctuation at the end. If the text does not clearly \
        describe an upcoming appointment or event, reply with exactly the \
        single word NONE — that is a better answer than a guess.
        """ + LanguageStore.shared.llmLanguageDirective)
        do {
            let response = try await session.respond(
                to: "Text from the screenshot:\n\(excerpt)\n\nName what the upcoming appointment or event is, in a few plain words, or NONE.",
                generating: ScreenshotFactLayout.self)
            let line = response.content.label
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' \n"))
            guard !line.isEmpty, line.uppercased() != "NONE", line.count <= 60 else { return nil }
            return line
        } catch {
            return nil
        }
    }
}
#endif
