import Foundation

/// The credential tripwire (prd §277, 2026-08-02).
///
/// Vision OCRs whatever is in a screenshot, and `ScreenshotIngest.heal` writes
/// that text straight onto `Thing.content` — so a screenshot of a recovery
/// phrase, an API key or a password becomes searchable text that then rides
/// out of the app on two surfaces the person never chose: the Spotlight/Siri
/// donation (`SpotlightIndex.attributeSet`, which is system-wide and sits
/// OUTSIDE any app lock) and the keyed agent's prompt (`AgentAnswer
/// .synthesize`, which posts corpus text to a third-party API).
///
/// This finds those spans deterministically — no model, the `Find` bar — so
/// the two paths above can hide them. Three rules it keeps:
///
/// 1. **It redacts SPANS, not documents.** A screenshot with one password
///    line stays findable by every other word on it. Blanking whole items
///    would be a search index that silently forgets things.
/// 2. **It never touches the stored `Thing`.** The corpus keeps the real
///    text and `Retriever`/Find still match on it, so "where's that
///    password screenshot" still works INSIDE the app. This hides secrets
///    from the surfaces that leave; it does not delete the person's data.
/// 3. **A miss is cheaper than a false alarm, except once.** Every detector
///    here is deliberately narrow, because a false positive means Spotlight
///    quietly stops finding an ordinary note — the "silently broken" failure
///    this codebase hates. The recovery-phrase detector is the exception the
///    thresholds were tuned around: a seed phrase sitting in a
///    CloudKit-synced, Spotlight-indexed corpus is the worst object this app
///    can hold, so it gets two rules that cover each other's blind spot.
///
/// The pure logic here is harness-checked by `scripts/secret-scan-selftest.py`,
/// which reads the patterns, thresholds and wordlist OUT OF THIS FILE rather
/// than copying them — so re-tuning a number fails the fixtures instead of
/// silently changing what the app hides. The harness mirrors the ALGORITHM
/// (Luhn, the run scan) in Python; it cannot execute this Swift, and says so.
enum SecretScan {

    // MARK: - What was found

    enum Kind: String, CaseIterable {
        case recoveryPhrase
        case apiKey
        case password
        case cardNumber
        case oneTimeCode

        /// What stands in for the hidden span. It names the KIND on purpose:
        /// a bare "[hidden]" reads like the app lost something, while
        /// "[recovery phrase hidden]" explains itself where it appears.
        var marker: String {
            switch self {
            case .recoveryPhrase: "[recovery phrase hidden]"
            case .apiKey:         "[key hidden]"
            case .password:       "[password hidden]"
            case .cardNumber:     "[card number hidden]"
            case .oneTimeCode:    "[code hidden]"
            }
        }
    }

    struct Finding {
        let kind: Kind
        let range: NSRange
    }

    // MARK: - Thresholds
    //
    // Named constants because `scripts/secret-scan-selftest.py` reads them
    // out of this file and re-runs the fixtures against them — moving a
    // number here fails the harness rather than silently re-tuning the
    // detector.

    /// A run of consecutive wordlist words long enough to be a phrase whose
    /// OCR dropped a word. Below this, nothing is ever flagged.
    static let phraseRunFloor = 11

    /// How much of the text the run has to BE. Measured 2026-08-02: ordinary
    /// prose tops out at a 2–3 word run, but a screenshot of a shopping list
    /// reached 12 consecutive wordlist words and a list of common verbs
    /// reached 19 — so run length alone would redact people's lists. A real
    /// phrase, pasted bare, is ~100% of its text; the shopping list was 44%.
    static let phraseDensityFloor = 0.6

    /// The standard phrase lengths. The verb list that reached a 19-run is
    /// rejected here; a 12-word shopping list is not, which is what the
    /// density floor is for.
    static let phraseLengths: Set<Int> = [12, 15, 18, 21, 24]

    // MARK: - Patterns

    /// Vendor key prefixes with a fixed, distinctive shape. An allowlist by
    /// design — "long random-looking string" as a rule would flag every
    /// transaction hash in a wallet-shaped corpus.
    static let apiKeyPattern =
        "(?:sk-ant-|sk-|sk_live_|sk_test_|rk_live_|pk_live_|ghp_|gho_|ghu_|ghs_"
        + "|github_pat_|xai-|xoxb-|xoxp-|xoxa-|xoxs-|ocv_|glpat-|dop_v1_|AKIA|AIza)"
        + "[A-Za-z0-9_\\-]{16,}"

    /// A labelled secret. Group 1 is the value — the label stays visible, so
    /// the row still reads "Password: [password hidden]" and remains findable
    /// by the word "password".
    static let passwordPattern =
        "(?i)\\b(?:password|passcode|passphrase|pin)\\b[ \\t]*[:=][ \\t]*(\\S{4,64})"

    /// A digit run that COULD be a card. Validated in `looksLikeCard` — the
    /// regex alone is far too broad for this corpus.
    static let cardCandidatePattern = "(?:\\d[ -]?){12,18}\\d"

    /// One-time codes, both shapes: "verification code … 123456" and
    /// "code is 123456". Group 1 is the digits.
    static let oneTimeCodePattern =
        "(?i)(?:\\b(?:one[- ]time|verification|security|login|sign[- ]?in"
        + "|authentication|confirmation)[ \\t]+code\\b|\\bcode\\b[ \\t]*(?:is|:))"
        + "[^0-9]{0,32}?(\\d{4,8})\\b"

    /// The words that accompany a real phrase. This is the second rule: a
    /// phrase wrapped in wallet UI ("Write down your secret recovery
    /// phrase … never share it") measured only 47% density and would slip
    /// past the density floor alone.
    static let phraseContextPattern =
        "(?i)(?:recovery phrase|seed phrase|secret phrase|backup phrase|mnemonic"
        + "|secret recovery|never share (?:this|these|it|them)"
        + "|write (?:these|them|this) down|\\b(?:12|15|18|21|24)[- ]word\\b)"

    /// Word tokens. Digits and punctuation are separators, so a numbered
    /// phrase ("1. abandon 2. ability") reads as one unbroken run.
    static let wordPattern = "[A-Za-z]+"

    // MARK: - Entry points

    /// Every secret-looking span in `text`, in document order.
    static func scan(_ text: String) -> [Finding] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [Finding] = []

        for (kind, regex, valueGroup) in labelledPatterns {
            guard let regex else { continue }
            // `matches(in:)` rather than `enumerateMatches` — the array form
            // needs no mutating capture, so nothing here depends on whether
            // the block is imported as escaping.
            for match in regex.matches(in: text, range: whole) {
                let range = valueGroup > 0 && match.numberOfRanges > valueGroup
                    ? match.range(at: valueGroup)
                    : match.range
                guard range.location != NSNotFound, range.length > 0 else { continue }
                if kind == .cardNumber, !looksLikeCard(ns, range) { continue }
                found.append(Finding(kind: kind, range: range))
            }
        }

        if let phrase = recoveryPhraseRange(in: text) {
            found.append(Finding(kind: .recoveryPhrase, range: phrase))
        }

        return found.sorted { $0.range.location < $1.range.location }
    }

    static func carriesSecret(_ text: String) -> Bool {
        !scan(text).isEmpty
    }

    /// `text` with every found span replaced by its marker. Returns the input
    /// unchanged when nothing was found, so the clean path allocates nothing.
    static func redacted(_ text: String) -> String {
        let findings = scan(text)
        guard !findings.isEmpty else { return text }
        let out = NSMutableString(string: text)
        var lastStart = Int.max
        // Back to front, so each replacement leaves earlier offsets valid.
        for finding in findings.sorted(by: { $0.range.location > $1.range.location }) {
            let end = finding.range.location + finding.range.length
            guard end <= lastStart else { continue }   // drop overlaps
            out.replaceCharacters(in: finding.range, with: finding.kind.marker)
            lastStart = finding.range.location
        }
        return out as String
    }

    /// The tags a Spotlight donation may carry. Tags are short and
    /// bridge-authored, so this is cheap insurance rather than a hot path.
    static func safeTags(_ tags: [String]) -> [String] {
        tags.filter { !carriesSecret($0) }
    }

    // MARK: - Recovery phrases

    /// The character range of a run of wordlist words that reads as a real
    /// recovery phrase, or nil.
    ///
    /// Two rules, either sufficient, because each is blind where the other
    /// sees (both measured 2026-08-02 against the fixtures the harness
    /// re-runs):
    ///   A. the run is a standard phrase length AND is most of the text —
    ///      catches a phrase pasted bare, rejects a 12-word shopping list;
    ///   B. the run is long AND the text says what it is — catches a phrase
    ///      surrounded by wallet chrome, whose density was only 47%.
    static func recoveryPhraseRange(in text: String) -> NSRange? {
        guard let wordRegex = wordRegex else { return nil }
        let ns = text as NSString
        let words = wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard words.count >= phraseRunFloor else { return nil }

        var bestStart = 0, bestLength = 0
        var runStart = 0, runLength = 0
        for (i, word) in words.enumerated() {
            let token = ns.substring(with: word.range).lowercased()
            if SecretScanWordlist.english.contains(token) {
                if runLength == 0 { runStart = i }
                runLength += 1
                if runLength > bestLength { bestLength = runLength; bestStart = runStart }
            } else {
                runLength = 0
            }
        }
        guard bestLength >= phraseRunFloor else { return nil }

        let density = Double(bestLength) / Double(words.count)
        let ruleA = phraseLengths.contains(bestLength) && density >= phraseDensityFloor
        let ruleB = hasPhraseContext(text)
        guard ruleA || ruleB else { return nil }

        let first = words[bestStart].range
        let last = words[bestStart + bestLength - 1].range
        return NSRange(location: first.location,
                       length: last.location + last.length - first.location)
    }

    private static func hasPhraseContext(_ text: String) -> Bool {
        guard let regex = phraseContextRegex else { return false }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: whole) != nil
    }

    // MARK: - Cards

    /// Whether a digit run is really a card number.
    ///
    /// Luhn alone is not enough HERE: this corpus is full of long integers
    /// that are not cards (a millisecond timestamp is 13 digits, a wei
    /// amount 19), and one in ten of them passes Luhn by chance. So the run
    /// must also start with an issuer prefix that real cards use — which no
    /// timestamp (17…) or round wei amount (10…) does.
    static func looksLikeCard(_ ns: NSString, _ range: NSRange) -> Bool {
        // A run that continues into more digits is part of a longer number.
        if range.location > 0,
           isDigit(ns.character(at: range.location - 1)) { return false }
        let after = range.location + range.length
        if after < ns.length, isDigit(ns.character(at: after)) { return false }

        let digits = ns.substring(with: range).filter { $0.isNumber }
        guard (13...19).contains(digits.count) else { return false }
        guard hasIssuerPrefix(digits) else { return false }
        return passesLuhn(digits)
    }

    private static func isDigit(_ c: unichar) -> Bool {
        c >= 48 && c <= 57
    }

    static func hasIssuerPrefix(_ digits: String) -> Bool {
        guard digits.count >= 4 else { return false }
        let d = Array(digits)
        let one = String(d[0])
        let two = Int(String(d[0...1])) ?? -1
        let four = Int(String(d[0...3])) ?? -1
        if one == "4" { return true }                        // Visa
        if (51...55).contains(two) { return true }            // Mastercard
        if (22...27).contains(two) { return true }            // Mastercard 2-series
        if two == 34 || two == 37 { return true }             // Amex
        if two == 35 { return true }                          // JCB
        if two == 65 { return true }                          // Discover
        if four == 6011 { return true }                       // Discover
        return false
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        var double = false
        for char in digits.reversed() {
            guard let value = char.wholeNumberValue else { return false }
            if double {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
            double.toggle()
        }
        return sum % 10 == 0
    }

    // MARK: - Compiled patterns

    // Compiled once each, as immutable `static let`s. Deliberately NOT a
    // memo dictionary: this is scanned from whatever thread a bridge or the
    // Spotlight donation happens to be on, and a mutable static would be
    // shared mutable state to reason about (and to defend from strict
    // concurrency) for no gain — there are six patterns and they never
    // change. Swift's lazy `let` initialisation is itself thread-safe.
    private static let apiKeyRegex = try? NSRegularExpression(pattern: apiKeyPattern)
    private static let passwordRegex = try? NSRegularExpression(pattern: passwordPattern)
    private static let oneTimeCodeRegex = try? NSRegularExpression(pattern: oneTimeCodePattern)
    private static let cardRegex = try? NSRegularExpression(pattern: cardCandidatePattern)
    private static let phraseContextRegex = try? NSRegularExpression(pattern: phraseContextPattern)
    private static let wordRegex = try? NSRegularExpression(pattern: wordPattern)

    /// Each labelled pattern with the capture group that holds the SECRET —
    /// 0 meaning the whole match. Group 1 for the labelled kinds, so
    /// "Password:" stays readable and only its value is hidden.
    private static let labelledPatterns: [(Kind, NSRegularExpression?, Int)] = [
        (.apiKey,      apiKeyRegex,      0),
        (.password,    passwordRegex,    1),
        (.oneTimeCode, oneTimeCodeRegex, 1),
        (.cardNumber,  cardRegex,        0),
    ]
}
