import Foundation

/// WHERE TWO LOOK-ALIKE ADDRESSES ACTUALLY PART (2026-08-22, prd §444).
///
/// `AddressSafety.isLookalike` finds the pair; `AddressCard.lookalikeBand`
/// prints both in full and tells you to "compare every character before you
/// copy". This is the app doing that comparison instead of asking you to.
///
/// **Why the FIRST difference and not every difference.** `WalletStore.
/// shortAddress` truncates to `…` plus the last four characters, so two
/// look-alikes agree on four characters and disagree on almost all the rest —
/// highlighting every differing character paints ~94% of a 42-character hex
/// string and says nothing. The one fact that settles it in a glance is the
/// EARLIEST position at which they part: for the poisoning shape (a vanity
/// address matching the tail) that is character 3, right after `0x`, so two
/// characters of reading tells them apart. The shared head and the shared tail
/// dim because they are precisely the parts that cannot help.
///
/// **The case rule, and it is not cosmetic.** EIP-55 encodes a checksum in the
/// CASE of a hex address's letters, so the same address is legitimately written
/// `0xAbC…` on one screen and `0xabc…` on another — comparing those raw reports
/// a difference at character 3 for two spellings of ONE address, which on a
/// security notice is a false alarm pointing at the wrong character. Base58
/// (Solana, Bitcoin) is the opposite: case IS the value there, and folding it
/// would hide a real difference. So the caller passes the answer, because the
/// caller is where the app's single hex test lives (`ENS.isHexAddress`).
///
/// Foundation-only by design, so `scripts/address-diff-selftest.sh` can compile
/// it whole and unmodified. Every failure here renders as a perfectly ordinary
/// highlighted character — an off-by-one marks the wrong one, a folded compare
/// marks a difference that isn't there, a bad multi-twin fold dims a character
/// two addresses do not actually share — and nothing in a build, a screen sweep
/// or any static audit can see any of it. The harness is the only proof.
enum AddressDiff {

    /// How far two addresses agree from each end.
    ///
    /// Counts are in CHARACTERS (`Character`, not UTF-16 or bytes): the band
    /// renders per character, and an address that reached this app carrying a
    /// combining mark must not shift the marker off the glyph it names.
    struct Comparison: Equatable {
        /// Leading characters identical in both.
        var sharedPrefix: Int
        /// Trailing characters identical in both. For a real look-alike this
        /// is at least the four the short form shows.
        var sharedSuffix: Int
        /// The subject's own length, so a run can be built without re-measuring.
        var length: Int

        /// The index of the first character that differs, or nil when there is
        /// none — which for two entries the book calls look-alikes cannot
        /// happen, and is still answered rather than assumed, because the
        /// alternative is a crash on the one screen that exists for safety.
        var pivot: Int? {
            sharedPrefix < length - sharedSuffix ? sharedPrefix : nil
        }

        /// 1-based, for copy. Nil when there is nothing to point at.
        var pivotPosition: Int? { pivot.map { $0 + 1 } }
    }

    /// What one character of the subject is, for rendering.
    enum Run: Equatable {
        /// Shared with every twin — the part that cannot tell them apart.
        case shared
        /// The first character that differs. Exactly one per address.
        case pivot
        /// Differs, but later — full ink, no marker.
        case differing
    }

    /// A maximal run of same-kind characters, so the band draws a handful of
    /// `Text`s rather than forty-two.
    struct Segment: Equatable {
        var text: String
        var run: Run
    }

    // MARK: - Comparing

    /// How far `subject` and `other` agree from each end.
    ///
    /// `foldCase` folds ASCII letters only, which is what a hex address is made
    /// of — a Unicode-aware lowercasing would be wrong here for a reason worth
    /// stating: `AddressSafety` has a whole confusables table because non-ASCII
    /// characters reach this app in address-shaped strings, and case-folding
    /// those could map two distinct code points onto one and hide a real
    /// difference. The fold is deliberately the narrowest thing that fixes
    /// EIP-55.
    static func compare(_ subject: String, with other: String,
                        foldCase: Bool) -> Comparison {
        let a = Array(subject)
        let b = Array(other)
        let limit = min(a.count, b.count)

        var prefix = 0
        while prefix < limit, same(a[prefix], b[prefix], foldCase: foldCase) { prefix += 1 }

        var suffix = 0
        // Stops at `limit - prefix` so the two runs can never overlap and
        // report more shared characters than either string has — the shape
        // that renders as an address with no differing region at all.
        while suffix < limit - prefix,
              same(a[a.count - 1 - suffix], b[b.count - 1 - suffix], foldCase: foldCase) {
            suffix += 1
        }

        return Comparison(sharedPrefix: prefix, sharedSuffix: suffix, length: a.count)
    }

    /// The subject against SEVERAL twins at once.
    ///
    /// Both counts are the MINIMUM across the twins, so a character is dimmed
    /// only when it is shared with every one of them. Taking the maximum, or
    /// the first twin's answer, would dim a character that distinguishes the
    /// subject from one of the addresses it is being warned about — which is
    /// the one thing this band must never do. With a single twin, which is the
    /// overwhelmingly common case, the two definitions coincide.
    ///
    /// No twins is not an error: it yields "nothing shared", so the subject
    /// draws as ordinary full-strength text and the band's own `isEmpty` gate
    /// upstream is the thing that decides whether it appears at all.
    static func combined(_ subject: String, against others: [String],
                         foldCase: Bool) -> Comparison {
        guard !others.isEmpty else {
            return Comparison(sharedPrefix: 0, sharedSuffix: 0, length: subject.count)
        }
        var prefix = Int.max
        var suffix = Int.max
        for other in others {
            let c = compare(subject, with: other, foldCase: foldCase)
            prefix = min(prefix, c.sharedPrefix)
            suffix = min(suffix, c.sharedSuffix)
        }
        return Comparison(sharedPrefix: prefix, sharedSuffix: suffix, length: subject.count)
    }

    private static func same(_ a: Character, _ b: Character, foldCase: Bool) -> Bool {
        if a == b { return true }
        guard foldCase, a.isASCII, b.isASCII else { return false }
        return a.lowercased() == b.lowercased()
    }

    // MARK: - Rendering

    /// The subject cut into runs, in order, covering every character exactly
    /// once. Concatenating `text` reproduces the input — asserted by the
    /// harness, because a diff that silently drops a character from a security
    /// notice is worse than no diff.
    static func segments(of subject: String, comparison: Comparison) -> [Segment] {
        let chars = Array(subject)
        guard !chars.isEmpty else { return [] }
        // Defensive rather than trusting: `comparison` may have been built
        // against a different string by a future caller, and clamping here
        // costs nothing while an out-of-range slice costs the app.
        let prefix = max(0, min(comparison.sharedPrefix, chars.count))
        let suffix = max(0, min(comparison.sharedSuffix, chars.count - prefix))
        let tailStart = chars.count - suffix

        var out: [Segment] = []
        func push(_ range: Range<Int>, _ run: Run) {
            guard !range.isEmpty else { return }
            let text = String(chars[range])
            // Merge with the previous run when they match, so the output is
            // maximal runs rather than one segment per call.
            if var last = out.last, last.run == run {
                last.text += text
                out[out.count - 1] = last
            } else {
                out.append(Segment(text: text, run: run))
            }
        }

        push(0..<prefix, .shared)
        if prefix < tailStart {
            push(prefix..<(prefix + 1), .pivot)
            push((prefix + 1)..<tailStart, .differing)
        }
        push(tailStart..<chars.count, .shared)
        return out
    }
}
