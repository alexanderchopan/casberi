import Foundation

/// Token-symbol spoofing (2026-07-21, prd §160) — the address-poisoning
/// attack aimed at a different field.
///
/// FOUND on a real watched wallet (poap.eth): transfers landing titled
/// "Sent 100,000 USDC" where the symbol is not USDC. The bytes actually
/// stored were `55 CC81 D085 44 D0A1` — `U` + a COMBINING ACUTE, then
/// Cyrillic `Ѕ` (U+0405), `D`, and Cyrillic `С` (U+0421). It renders as
/// "ÚЅDС": at a feed row's size, in the feed's normal weight, that is USDC.
/// Nothing in the pipeline objected — the symbol is just a string the chain
/// handed us, and it flowed into titles, `transferAmount`, the money column,
/// the holdings treemap and answers unchallenged.
///
/// The rule has two clauses, and they catch different attacks:
///
/// 1. ANY non-ASCII scalar in a symbol is suspicious on its own. A real
///    ticker is ASCII; a symbol reaching for Cyrillic, Greek, Cherokee,
///    fullwidth forms or combining marks is reaching for a resemblance. This
///    clause needs no table and cannot be evaded by picking a lookalike we
///    forgot to list — it is the backstop that makes an incomplete table
///    safe.
/// 2. The symbol's confusable SKELETON matches a well-known symbol while its
///    literal text does not. This is what catches the pure-ASCII attacks
///    clause 1 can't see: `DAl` (lowercase L), `U5DT`, `S0L`, `3TH`.
///
/// Deliberately a tight known-symbol set rather than a guess at "does this
/// look like any token anywhere" — the same choice TokenHue/TokenIcon make.
/// A short list of the symbols actually worth impersonating produces a
/// warning we can stand behind; a general resemblance engine produces noise.
enum SymbolConfusables {

    // MARK: - The known set

    /// The symbols worth impersonating: what someone would have to believe
    /// they were receiving for the lie to pay. Majors, the stablecoins, the
    /// big LSTs, and the liquid memecoins. Uppercase, ASCII.
    static let known: Set<String> = [
        "ETH", "WETH", "BTC", "WBTC", "CBBTC", "SOL", "BNB", "XRP", "ADA",
        "AVAX", "TRX", "TON", "DOT", "LTC", "BCH", "NEAR", "APT", "SUI",
        "USDC", "USDT", "DAI", "USDS", "PYUSD", "FDUSD", "TUSD", "BUSD",
        "USDE", "SUSDE", "EURC", "GUSD", "USDD",
        // USDT0 (the omnichain USDT) earns its place from measurement, not a
        // hunch: the corpus held "ꓴꓢꓓꓔ0" — USDT0 spelled in Lisu — and
        // without the real symbol on this list the warning could only say
        // "look-alike characters" about a copy of a token that exists.
        "USDT0",
        "STETH", "WSTETH", "WEETH", "RETH", "CBETH", "EZETH", "JITOSOL", "MSOL",
        "LINK", "UNI", "AAVE", "MKR", "CRV", "LDO", "COMP", "SNX", "GRT",
        "ARB", "OP", "MATIC", "POL", "INJ", "FIL", "ATOM", "RNDR", "ENA",
        "PEPE", "SHIB", "DOGE", "WIF", "BONK", "HYPE", "JUP", "RAY",
    ]

    /// skeleton → the known symbol that owns it, folded once at first use.
    /// This is why `skeleton` must be a pure function of its input: both
    /// sides of the comparison run through it.
    ///
    /// A dictionary rather than a Set of skeletons plus a lookup: naming what
    /// a spoof imitates is the whole output, and re-deriving it meant sorting
    /// the set and recomputing up to ~70 skeletons — each one two ICU passes —
    /// on every verdict. Sorting HERE also bakes the tie-break in at build
    /// time, so a collision resolves the same way forever instead of relying
    /// on a comment to keep it stable.
    private static let bySkeleton: [String: String] = {
        var out: [String: String] = [:]
        for symbol in known.sorted() where out[skeleton(symbol)] == nil {
            out[skeleton(symbol)] = symbol
        }
        return out
    }()

    // MARK: - The confusable table

    /// Visually-confusable non-ASCII scalars → the ASCII letter they wear.
    ///
    /// Cyrillic, Greek, Cherokee and the Roman-numeral forms — the alphabets
    /// whose letters are drawn identically to Latin ones in the system font.
    /// This is a VISUAL table, not a transliteration: ICU's `.toLatin`
    /// transform is phonetic and gets exactly the case that started this
    /// wrong (it renders Cyrillic `Ѕ` as "Dz", turning our real spoof into
    /// "UDzDC" and matching nothing).
    ///
    /// Fullwidth forms, mathematical alphanumerics and precomposed accents
    /// are NOT listed — `skeleton`'s NFKC + diacritic-stripping passes fold
    /// those already, in far less code than enumerating a few thousand
    /// scalars would take.
    private static let visual: [Character: Character] = [
        // Cyrillic, uppercase
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O",
        "Р": "P", "С": "C", "Т": "T", "У": "Y", "Х": "X", "Ѕ": "S", "І": "I",
        "Ј": "J", "Ԁ": "D", "Ԛ": "Q", "Ԝ": "W", "Ү": "Y", "Ӏ": "I", "Ғ": "F",
        // Cyrillic, lowercase
        "а": "A", "е": "E", "о": "O", "р": "P", "с": "C", "у": "Y", "х": "X",
        "ѕ": "S", "і": "I", "ј": "J", "ԁ": "D", "ԛ": "Q", "ԝ": "W", "ѵ": "V",
        // Greek, uppercase
        "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K",
        "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X",
        "Ϲ": "C", "Ϝ": "F",
        // Greek, lowercase
        "ο": "O", "ν": "V", "ρ": "P", "ι": "I", "κ": "K",
        // Cherokee
        "Ꭺ": "A", "Ᏼ": "B", "Ꮯ": "C", "Ꭰ": "D", "Ꭼ": "E", "Ꮐ": "G", "Ꮋ": "H",
        "Ꭻ": "J", "Ꮶ": "K", "Ꮮ": "L", "Ꮇ": "M", "Ꮎ": "O", "Ꮲ": "P", "Ꮪ": "S",
        "Ꭲ": "T", "Ꮙ": "V", "Ꮤ": "W", "Ꮓ": "Z",
        // Roman numeral forms
        "Ⅰ": "I", "Ⅴ": "V", "Ⅹ": "X", "Ⅼ": "L", "Ⅽ": "C", "Ⅾ": "D", "Ⅿ": "M",
        // Armenian / other stray lookalikes
        "Օ": "O", "Ѡ": "W", "ᒍ": "J", "ᗪ": "D",
        // Georgian and Lisu — NOT guessed, MEASURED: the first probe run over
        // the real corpus (2026-07-21, poap.eth) turned up "UႽDC" using
        // Georgian Ⴝ and "ꓴꓢꓓꓔ0" written entirely in Lisu. Both were caught
        // by the non-ASCII clause alone, so they landed flagged but unnamed
        // ("look-alike characters" rather than "a copy of USDC"). Listing
        // them upgrades the warning to the sentence that actually helps.
        "Ⴝ": "S", "Ⴇ": "T", "Ⴈ": "I", "Ⴊ": "L", "Ⴋ": "M", "Ⴍ": "O",
        "ꓐ": "B", "ꓚ": "C", "ꓓ": "D", "ꓰ": "E", "ꓝ": "F", "ꓖ": "G",
        "ꓧ": "H", "ꓲ": "I", "ꓙ": "J", "ꓗ": "K", "ꓡ": "L", "ꓟ": "M",
        "ꓠ": "N", "ꓳ": "O", "ꓑ": "P", "ꓤ": "R", "ꓢ": "S", "ꓔ": "T",
        "ꓴ": "U", "ꓦ": "V", "ꓪ": "W", "ꓫ": "X", "ꓬ": "Y", "ꓜ": "Z",
    ]

    /// Digits and letterforms that stand in for each other in ASCII. Folded
    /// digit → letter (never the reverse): a real ticker that legitimately
    /// contains a digit (`1INCH`) folds to something that isn't in the known
    /// set and stays unflagged, while `U5DT` folds onto `USDT` and doesn't.
    private static let asciiFolds: [Character: Character] = [
        "0": "O", "1": "I", "3": "E", "4": "A", "5": "S", "8": "B",
    ]

    // MARK: - The rule

    /// The confusable skeleton: what the symbol LOOKS like, in ASCII.
    ///
    /// Order matters. NFKC first (folds fullwidth `ＵＳＤＣ`, the mathematical
    /// alphanumeric blocks, and composes `U`+combining-acute into `Ú`), then
    /// diacritic stripping (`Ú` → `U` — this is the pass that undoes the
    /// U+0301 in the real capture), then the visual table, then the ASCII
    /// folds, and only then uppercasing.
    static func skeleton(_ symbol: String) -> String {
        // Invisible scalars go first. MEASURED, not theoretical: the real
        // corpus held "UႽD<U+202C>C" — a POP DIRECTIONAL FORMATTING character
        // wedged mid-symbol, which renders as nothing at all and exists only
        // to stop a string comparison from matching. Anything that draws no
        // ink cannot be part of what a symbol LOOKS like, so it is dropped
        // before any comparison happens.
        let visible = String(String.UnicodeScalarView(symbol.unicodeScalars.filter {
            let category = $0.properties.generalCategory
            return category != .format && category != .control
                && category != .privateUse && category != .surrogate
        }))
        let folded = visible.precomposedStringWithCompatibilityMapping
        let plain = folded.applyingTransform(.stripDiacritics, reverse: false) ?? folded
        var out = ""
        for ch in plain {
            // A lone lowercase `l` is the oldest ASCII spoof of `I` and has to
            // be handled BEFORE uppercasing, which would turn it into `L` and
            // hide the resemblance ("DAl" must reach "DAI", not "DAL").
            if ch == "l" { out.append("I"); continue }
            if let mapped = visual[ch] { out.append(mapped); continue }
            out.append(contentsOf: String(ch).uppercased())
        }
        out = String(out.map { asciiFolds[$0] ?? $0 })
        return String(out.filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// What's wrong with a symbol, when something is.
    struct Verdict: Equatable {
        /// The symbol exactly as it landed — never cleaned up. The warning
        /// names it only where showing it helps; the app never silently
        /// rewrites what the chain said.
        let symbol: String
        /// The well-known symbol it resembles, when the skeleton matched one.
        /// nil when the symbol is merely non-ASCII without impersonating
        /// anything we know — still worth the flag, less worth a name.
        let impersonating: String?

        /// The warning sentence, in the poisoning line's voice ("Looks like a
        /// copy of an address you've used — this is a different wallet.").
        /// Built here rather than in a view because two surfaces say it: the
        /// thing sheet's warning line and the Worth-a-look tray's row.
        var sentence: String {
            if let impersonating {
                return String(localized: "Looks like a copy of \(impersonating) — this is a different token.")
            }
            return String(localized: "This symbol uses look-alike characters — it isn't the token it resembles.")
        }
    }

    /// The verdict on one symbol, or nil when it's ordinary.
    static func verdict(for symbol: String) -> Verdict? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let literal = trimmed.uppercased()
        // A symbol that IS a known one, spelled in plain ASCII, is the thing
        // itself — never flagged, however many of its letters could have been
        // faked. This check has to come first or every real USDC transfer
        // wears a scam warning.
        let nonASCII = trimmed.unicodeScalars.contains { !$0.isASCII }
        if !nonASCII, known.contains(literal) { return nil }
        let impersonating = bySkeleton[skeleton(trimmed)]
        // Clause 2 alone can fire on an all-ASCII symbol; clause 1 alone can
        // fire on a non-ASCII symbol impersonating nothing. Either is enough.
        guard nonASCII || impersonating != nil else { return nil }
        return Verdict(symbol: trimmed, impersonating: impersonating)
    }

    /// Whether a symbol should be flagged — the ingest-time question.
    static func isSuspicious(_ symbol: String) -> Bool { verdict(for: symbol) != nil }

    /// The first suspicious symbol inside a sentence — how a SURFACE recovers
    /// the verdict for a thing that ingest already flagged, without a second
    /// stored field (the symbol is right there in `transferAmount` and the
    /// title, verbatim).
    ///
    /// Only word-shaped tokens are considered: a title's `→` and `·` are
    /// non-ASCII too, and clause 1 would happily flag an arrow.
    static func firstSuspicious(in text: String) -> Verdict? {
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let word = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.·()[]"))
            guard word.count >= 2, word.count <= 16,
                  word.contains(where: { $0.isLetter }) else { continue }
            if let v = verdict(for: word) { return v }
        }
        return nil
    }
}
