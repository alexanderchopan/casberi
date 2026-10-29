import Foundation

/// **WHERE A SEND'S TIME WENT (prd §1602, user: "it takes way too long to
/// swap … it took me ten minutes to send").** Move's stages, timed from the
/// tap: preparing, Face ID, the Signer, sending, landing. §1601 made the reads
/// parallel on the code's own measures; this is the phone's number, so the
/// next pass aims at the stage that is actually slow.
///
/// Said on the receipt in a pre-release build only (`BuildChannel`): the
/// person testing it reads it where the send ended, and nobody else is
/// shown a stopwatch.
struct MoveClock: Equatable, Sendable {
    enum Mark: String, Equatable, Sendable {
        case preparing, faceID, signer, sending, landing

        var words: String {
            switch self {
            case .preparing: String(localized: "preparing")
            case .faceID: String(localized: "Face ID")
            case .signer: String(localized: "your Signer")
            case .sending: String(localized: "sending")
            case .landing: String(localized: "landing")
            }
        }
    }

    struct Entry: Equatable, Sendable {
        let mark: Mark
        let at: Date
    }

    private(set) var entries: [Entry]

    init(at start: Date = .now) { entries = [Entry(mark: .preparing, at: start)] }

    /// A stage begins; the same stage again is no new stage.
    mutating func enter(_ mark: Mark, at: Date = .now) {
        guard entries.last?.mark != mark else { return }
        entries.append(Entry(mark: mark, at: at))
    }

    /// Each stage and how long it held, in order, until `end`. A stage
    /// entered twice (the spend limit's fallback prepares again) adds up.
    func spans(until end: Date) -> [(mark: Mark, seconds: TimeInterval)] {
        var out: [(mark: Mark, seconds: TimeInterval)] = []
        for (i, e) in entries.enumerated() {
            let next = i + 1 < entries.count ? entries[i + 1].at : end
            let seconds = max(0, next.timeIntervalSince(e.at))
            if let j = out.firstIndex(where: { $0.mark == e.mark }) { out[j].seconds += seconds } else { out.append((e.mark, seconds)) }
        }
        return out
    }

    func total(until end: Date) -> TimeInterval { max(0, end.timeIntervalSince(entries[0].at)) }

    /// "12s: preparing 2.1s, Face ID 1.4s, your Signer 6s, sending 0.8s, landing 1.9s".
    func words(until end: Date) -> String {
        let parts = spans(until: end).map { "\($0.mark.words) \(Self.seconds($0.seconds))" }
        return Self.seconds(total(until: end)) + ": " + parts.joined(separator: ", ")
    }

    /// Under ten seconds to a tenth, then whole seconds.
    static func seconds(_ s: TimeInterval) -> String {
        s < 10 ? String(format: "%.1fs", s) : "\(Int(s.rounded()))s"
    }
}
