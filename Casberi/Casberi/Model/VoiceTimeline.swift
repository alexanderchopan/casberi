import Foundation

/// WHEN EACH WORD OF A VOICE NOTE WAS SAID (prd §987) — the transcript read
/// back off the kept audio file, one entry per word, so the sheet can light
/// the words as they play and a tap on a word can seek to it.
///
/// A LOCAL, DERIVED CACHE, never a `Thing` field: the audio is the record and
/// syncs, and any device can read these times back off it, so a synced column
/// would be a second copy of a fact the bytes already hold — and a new
/// CloudKit field is a separate Production ship (docs/cloudkit-deploy.md).
/// One JSON file per note under Caches, keyed by the note's id; the system
/// may purge it, and the heal writes it again.
///
/// Foundation only, so `voice-timeline-selftest.sh` compiles this file whole.
struct VoiceTimeline: Codable, Equatable {
    struct Word: Codable, Equatable {
        /// The word as it reads, WITH the spaces and punctuation around it
        /// (the analyzer hands " to", " Thursday,"), so
        /// `words.map(\.text).joined()` is the transcript exactly.
        var text: String
        var start: Double
        var end: Double
    }

    var words: [Word]

    /// The transcript these times belong to.
    var text: String { words.map(\.text).joined() }

    /// Built from the recognizer's runs in order: a run with a time is a word,
    /// and a run without one (the space between words, a trailing full stop)
    /// joins the word before it, so no character of the transcript is lost
    /// and no word is invented. Leading untimed text joins the first word.
    static func build(runs: [(text: String, start: Double?, end: Double?)]) -> VoiceTimeline? {
        var words: [Word] = []
        var pending = ""
        for run in runs {
            if let start = run.start, let end = run.end, end >= start,
               !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                words.append(Word(text: pending + run.text, start: start, end: end))
                pending = ""
            } else if words.isEmpty {
                pending += run.text
            } else {
                words[words.count - 1].text += run.text
            }
        }
        guard !words.isEmpty else { return nil }
        // Leading space off the first word, trailing space off the last: the
        // transcript is `content`, and `content` is stored trimmed.
        words[0].text = String(words[0].text.drop(while: \.isWhitespace))
        while let last = words.last?.text.last, last.isWhitespace {
            words[words.count - 1].text.removeLast()
        }
        return words.contains { !$0.text.isEmpty } ? VoiceTimeline(words: words) : nil
    }

    /// The word being said at `time`: the last word that has STARTED by then,
    /// so the gap between two words keeps the earlier one lit rather than
    /// flickering to nothing. Nil before the first word starts.
    func wordIndex(at time: Double) -> Int? {
        var lo = 0, hi = words.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if words[mid].start <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    /// Do these times belong to `content`? Compared with whitespace collapsed,
    /// because a line break in stored words is not a different transcript.
    /// When the words were rewritten somewhere else (another device's heal),
    /// the sheet draws `content` plainly rather than times for other words.
    func matches(_ content: String) -> Bool {
        Self.normalized(text) == Self.normalized(content)
    }

    static func normalized(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// May the whole-file reading `new` replace the live words `old`
    /// (prd §987)? Only when it says something, says something different,
    /// and has at least half as many words: a reading in the wrong language,
    /// or of a file that decoded short, must never eat what was heard live.
    static func replaces(_ old: String, with new: String) -> Bool {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, normalized(new) != normalized(old) else { return false }
        let oldCount = old.split(whereSeparator: \.isWhitespace).count
        let newCount = new.split(whereSeparator: \.isWhitespace).count
        return newCount * 2 >= oldCount
    }

    // MARK: - The cache

    static var folder: URL {
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice-timeline", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cacheURL(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    /// Has this note been read on this device? A stat, not a decode — the
    /// launch pass asks it of every voice note.
    static func isCached(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: id).path)
    }

    static func cached(for id: UUID) -> VoiceTimeline? {
        guard let data = try? Data(contentsOf: cacheURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(VoiceTimeline.self, from: data)
    }

    static func store(_ timeline: VoiceTimeline, for id: UUID) {
        guard let data = try? JSONEncoder().encode(timeline) else { return }
        try? data.write(to: cacheURL(for: id), options: .atomic)
    }
}

/// A recording's LENGTH as the row and the player say it (prd §987): "0:07",
/// "4:32", "1:02:05". Whole seconds, rounded down while playing so the clock
/// never shows a second that has not happened, and rounded to nearest for a
/// length, so a 6.9s note does not read "0:06".
enum VoiceLength {
    static func label(_ seconds: Double, rounding: Rounding = .nearest) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let whole = rounding == .down ? Int(seconds.rounded(.down)) : Int(seconds.rounded())
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    enum Rounding { case nearest, down }

    /// A voice note's length off its stored span — `endAt − capturedAt` —
    /// or nil when the span was never stamped (a note the heal has not
    /// reached, or one with no audio to measure).
    static func seconds(from start: Date, to end: Date?) -> Double? {
        guard let end else { return nil }
        let length = end.timeIntervalSince(start)
        return length > 0 ? length : nil
    }

    /// The speeds the player steps through, in order. One tap moves to the
    /// next and the last wraps to the first.
    static let rates: [Double] = [1, 1.5, 2]

    static func next(after rate: Double) -> Double {
        guard let i = rates.firstIndex(of: rate) else { return rates[0] }
        return rates[(i + 1) % rates.count]
    }

    static func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }
}
