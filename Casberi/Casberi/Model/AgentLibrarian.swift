import Foundation
import SwiftData

/// The librarian pass, run on the person's own key (2026-08-06).
///
/// prd §282 built five on-device passes that organize the corpus AT REST
/// rather than answering a question — the semantic index, the related shelf,
/// screenshot facts, thread digests, screenshot naming. Every one of them is
/// gated on `OnDeviceModel.isAvailable`, so on a device without Apple
/// Intelligence the whole half of the product is a silent no-op: screenshots
/// stay named "Screenshot" forever, and a two-hour imported transcript stays
/// indexed by its opening pleasantries.
///
/// That is the sharpest thing a key could buy and never did. Until now BYOK
/// bought a better ANSWER — one path, reachable from one screen, worth
/// something only at the moment you asked a question. This makes it buy a
/// better LIBRARY, which is worth something every time you open the app.
///
/// **Three rules, and they are what keep this from being a bill.**
///
/// 1. **Opt-in, off by default.** Everything else a key does happens on an
///    explicit tap ("Try with your key"). This is the first path where the app
///    would spend somebody's money on its own schedule, so it does not exist
///    until they say so.
/// 2. **The on-device model wins whenever it is there.** This is a FALLBACK,
///    never a preference — free and local beats paid and remote, and a device
///    with Apple Intelligence should never spend a cent on work it can do
///    itself.
/// 3. **Bounded twice.** The background sweeps keep their own small per-
///    foreground limits, and `catchUp` — the deliberate "do the backlog now"
///    verb — is capped and reports exactly what it did. The spend receipt sits
///    directly above the toggle that turns this on.
///
/// **The honesty rails are the on-device ones, unchanged.** A keyed title is
/// still rejected unless `ScreenshotNaming.grounded` says the words really
/// appear in the screenshot; a keyed digest still lands in `enrichedText`,
/// which is retrieval-only by the 2026-07-15 ruling and displayed nowhere. A
/// bigger model is a better guesser, which makes the grounding check MORE
/// load-bearing here, not less — fluency is what makes a wrong title
/// unnoticeable.
enum AgentLibrarian {

    private static let enabledKey = "agent.librarian"

    /// Whether the person has asked their key to help organize. Off until
    /// they say so, and meaningless without a key — the two are checked
    /// together in `canRun` so no caller can forget one.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Whether a keyed librarian call may actually be made. Bankr is excluded
    /// for the same reason `AgentAnswer.complete` refuses it: it answers from
    /// a wallet, not from text somebody handed it.
    static var canRun: Bool {
        guard isEnabled, let provider = AgentKey.active else { return false }
        return provider != .bankr
    }

    /// True when the local model can do this work for free. The one condition
    /// under which the key should stay in its pocket.
    @MainActor
    static var deviceCanDoIt: Bool { OnDeviceModel.isAvailable }

    /// Whether a sweep should run at all — either engine will do.
    @MainActor
    static var available: Bool { deviceCanDoIt || canRun }

    // MARK: - The two jobs

    /// A short title for a screenshot from its OCR text, on the key. The
    /// instructions are deliberately the same shape as
    /// `ScreenshotNameModel`'s: one contract, two engines, so a tuning fix to
    /// one doesn't quietly leave the other answering differently.
    ///
    /// The caller still runs `ScreenshotNaming.grounded` over whatever comes
    /// back — that check is not repeated here, because a rail enforced in two
    /// places is a rail that can be relaxed in one of them.
    static func name(text: String) async -> String? {
        guard canRun else { return nil }
        let excerpt = String(text.prefix(1_500))
        let system = """
        You name a screenshot from the text read out of it, so its owner can \
        pick it out of a list months later. Write three to eight plain words. \
        Build the name out of words that actually appear in the text — a \
        person, a place, an app, a subject it names. Never invent a subject the \
        text does not contain, and never describe the picture ("a screenshot \
        of…"); just name the thing. No punctuation at the end, no quotes, no \
        preamble — reply with the name alone. If the text is only interface \
        chrome — buttons, times, battery, menu labels — and says nothing about \
        a subject, reply with exactly the single word NONE. NONE is the right \
        answer more often than not.
        """ + LanguageStore.shared.llmLanguageDirective
        let prompt = "Text read out of the screenshot:\n\(excerpt)\n\nName it in a few plain words, or NONE."
        guard case .success(let raw) = await AgentAnswer.complete(
            system: system, prompt: prompt, maxTokens: 32) else { return nil }
        // A chat model answers in a sentence when a title was asked for, so
        // the first line is taken and the usual decorations stripped. The
        // length bounds are `ScreenshotNameModel`'s, for the same reason: a
        // one-word answer names nothing, and an 80-character one is a summary
        // wearing a title's slot.
        let title = (raw.components(separatedBy: "\n").first ?? raw)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!\"' \n"))
        guard !title.isEmpty, title.uppercased() != "NONE",
              title.count >= 4, title.count <= 80 else { return nil }
        return title
    }

    /// Two or three sentences saying what a transcript was about, on the key.
    /// Lands in `enrichedText` — retrieval-only, never displayed.
    static func summarize(title: String, transcript: String) async -> String? {
        guard canRun else { return nil }
        let excerpt = String(transcript.prefix(ThreadDigest.readWindow))
        let system = """
        You summarize a saved conversation so its owner can FIND it again \
        later. Write two or three plain sentences naming what it was actually \
        about — the subject, what was being worked out, and how it came out if \
        the text says. Use the words the conversation itself uses. Never invent \
        a detail, a number or an outcome the text does not contain. No \
        preamble, no "this conversation is about", no markdown, no bullets.
        """ + LanguageStore.shared.llmLanguageDirective
        let prompt = """
        Saved conversation titled "\(title)":

        \(excerpt)

        What was it about?
        """
        guard case .success(let raw) = await AgentAnswer.complete(
            system: system, prompt: prompt, maxTokens: 220) else { return nil }
        let summary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // `ThreadDigest.minimumLength` is about the INPUT; this bounds the
        // output. A one-line answer adds nothing the title didn't, and a very
        // long one is the transcript again.
        guard summary.count >= 40, summary.count <= 1_200 else { return nil }
        return summary
    }

    // MARK: - The deliberate backlog pass

    /// What one `catchUp` did, so the button that started it can say so.
    /// Counted separately because they fail differently: nothing to name is
    /// the healthy steady state, while nothing DIGESTED on a corpus full of
    /// imported chats means the pass isn't reaching them.
    struct Caught: Sendable {
        var named = 0
        var digested = 0
        /// Set when the provider refused or the network failed — the
        /// difference between "there was nothing to do" and "we couldn't".
        var failure: AgentAnswerFailure?

        var line: String {
            if let failure { return failure.line }
            if named == 0 && digested == 0 {
                return String(localized: "Nothing left to organize.")
            }
            var parts: [String] = []
            if named == 1 { parts.append(String(localized: "named 1 screenshot")) }
            else if named > 1 { parts.append(String(localized: "named \(named) screenshots")) }
            if digested == 1 { parts.append(String(localized: "read 1 conversation")) }
            else if digested > 1 { parts.append(String(localized: "read \(digested) conversations")) }
            return parts.joined(separator: ", ").capitalizedFirst + "."
        }
    }

    /// How much one deliberate pass will do. Bounded because this is the one
    /// verb here that spends without a further tap: forty titles and ten
    /// digests is a few cents on any provider in the catalog, and a person who
    /// wants more can press it again — which is a decision they get to make
    /// each time, rather than one this app makes once on their behalf.
    static let catchUpNames = 40
    static let catchUpDigests = 10

    /// Runs the backlog now, on the key. Reports what it did.
    ///
    /// Runs the two sweeps in their own chunks rather than one long loop so a
    /// cancelled or failed pass still keeps whatever it finished — the same
    /// commit-as-you-go shape `ImportCommit` uses, and for the same reason:
    /// work already paid for should survive.
    @MainActor
    static func catchUp(context: ModelContext) async -> Caught {
        var caught = Caught()
        guard canRun else {
            caught.failure = .noKey
            return caught
        }
        caught.named = await ScreenshotNaming.sweep(context: context, limit: catchUpNames)
        caught.digested = await ThreadDigest.sweep(context: context, limit: catchUpDigests)
        return caught
    }
}

private extension String {
    /// "named 3 screenshots" → "Named 3 screenshots". Only the first
    /// character, so a proper noun later in the sentence keeps its own case.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
