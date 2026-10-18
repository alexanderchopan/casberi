import SwiftUI

/// **A FLAGGED TRANSFER SAYS WHAT IT IS, IN ITS BOX (prd §1377).** The three
/// kinds the Security tile lists as trying to fool you drew as ordinary
/// receipts: a poisoner's dust as a settled transfer with Save, a fake token as
/// a trade with a rate, a spam token's claim as a send counted in "This year",
/// each with a red sentence under the tiles. The verdict is the sheet's title
/// now and the box holds the evidence that proves it:
///
/// - **poisoning** — both addresses in full, the one you meant over the copy,
///   the shared last four standing out: the one difference every short form
///   hides (§1375's "…a91c" is exactly what the copy is built to match);
/// - **a fake token** — the symbol letter by letter, each borrowed letter
///   named for where it came from;
/// - **a fake transfer** — the claimed amount struck through: nothing moved.
///
/// It lives in the room's frame (the fixed box, prd §1373's swap), and nothing
/// in it truncates: an address wraps, a long figure steps down a size.
struct FlaggedReceiptBox: View {
    let flag: Flag
    /// The wallet the transfer landed in, by its name ("Savings").
    let wallet: String?
    let network: String?
    let landed: Date
    /// The amount as the row stamped it, privacy-masked ("0 USDC").
    let amount: String?
    /// What happened, for a fake token: "You got 160 ÚЅDС for 0.05 ETH".
    let happened: String?
    let priced: Bool

    enum Flag: Equatable {
        /// `original` is the address the copy imitates, when the book or the
        /// wallet's own history holds it; `name` what the person calls it.
        case poisoning(copy: String, original: String?, name: String?)
        case symbol(SymbolConfusables.Verdict)
        case spam

        /// The sheet's title: the verdict, never the party.
        var title: String {
            switch self {
            case .poisoning(_, let original, let name):
                if let name { return String(localized: "A copy of \(name)'s address") }
                if let original { return String(localized: "A copy of \(WalletStore.shortAddress(original))") }
                return String(localized: "A copy of an address you've used")
            case .symbol(let verdict):
                if let real = verdict.impersonating { return String(localized: "This isn't \(real)") }
                return String(localized: "A look-alike token")
            case .spam:
                return String(localized: "You didn't send this")
            }
        }

        /// The flag this face speaks for, so the sheet's warning lines say
        /// only the others.
        var securityFlag: String {
            switch self {
            case .poisoning: "poisoning"
            case .symbol: "symbol"
            case .spam: "spam"
            }
        }
    }

    var body: some View {
        Group {
            switch flag {
            case .poisoning(let copy, let original, let name):
                poisoning(copy: copy, original: original, name: name)
            case .symbol(let verdict):
                symbol(verdict)
            case .spam:
                spam
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Poisoning

    private func poisoning(copy: String, original: String?, name: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let original {
                Text(verbatim: name ?? String(localized: "The address you've used"))
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                address(original, ink: DS.textSecondary)
                Text("The copy")
                    .dsText(.label12).foregroundStyle(DS.destructiveInk)
                    .padding(.top, DS.Space.s2)
            }
            address(copy, ink: DS.destructiveInk)
            Spacer(minLength: DS.Space.s2)
            Text(original == nil ? String(localized: "It ends like an address you've used.")
                                 : String(localized: "Same last four. A different account."))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: poisonLine)
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "It sent Savings 0 USDC to sit in your history · Oct 10". The day word
    /// stands apart (prd §1359): "Today" and "Oct 10" take no one preposition.
    private var poisonLine: String {
        let day = FeedScreen.dayWord(landed)
        switch (wallet, amount) {
        case let (w?, a?): return String(localized: "It sent \(w) \(a) to sit in your history · \(day)")
        case let (nil, a?): return String(localized: "It sent you \(a) to sit in your history · \(day)")
        default: return String(localized: "It wrote itself into your history · \(day)")
        }
    }

    /// The whole address, grouped by four, its last four in the page's ink:
    /// the part the copy matched, so the eye goes to what agrees and reads
    /// the rest as different.
    private func address(_ raw: String, ink: Color) -> some View {
        let parts = Self.grouped(raw)
        return (Text(verbatim: parts.head).foregroundStyle(ink)
                + Text(verbatim: parts.tail).foregroundStyle(DS.textPrimary).bold())
            .dsText(.mono17)
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "0x7b3e 91f0 2c4d a8b1 5e60 d2f7 3c19 b84e 06a2 " and "a91c". Hex goes
    /// by fours with the prefix on the first; any other address (base58)
    /// stays one word, its last four apart.
    static func grouped(_ raw: String) -> (head: String, tail: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return ("", trimmed) }
        let tail = String(trimmed.suffix(4))
        var body = String(trimmed.dropLast(4))
        guard ENS.isHexAddress(trimmed) else { return (body, tail) }
        body = String(body.dropFirst(2))
        var groups: [String] = []
        var i = body.startIndex
        while i < body.endIndex {
            let j = body.index(i, offsetBy: 4, limitedBy: body.endIndex) ?? body.endIndex
            groups.append(String(body[i..<j]))
            i = j
        }
        if !groups.isEmpty { groups[0] = "0x" + groups[0] }
        return (groups.joined(separator: " ") + " ", tail)
    }

    // MARK: - A fake token

    private func symbol(_ verdict: SymbolConfusables.Verdict) -> some View {
        let letters = Array(verdict.symbol)
        let borrowed = letters.filter { Self.origin(of: $0) != nil }.count
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    let origin = Self.origin(of: letter)
                    VStack(spacing: DS.Space.s1) {
                        Text(verbatim: String(letter))
                            .dsText(.heading40)
                            .foregroundStyle(origin == nil ? DS.textPrimary : DS.destructiveInk)
                        Text(verbatim: origin ?? " ")
                            .dsText(.label12)
                            .foregroundStyle(DS.destructiveInk)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: verdict.sentence))
            Text(verbatim: borrowedLine(borrowed, real: verdict.impersonating))
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
            Spacer(minLength: DS.Space.s2)
            if let happened {
                Text(verbatim: "\(happened) · \(FeedScreen.dayWord(landed))")
                    .dsText(.heading17).monospacedDigit().foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Text(verbatim: footLine(priced: priced))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func borrowedLine(_ n: Int, real: String?) -> String {
        guard let real else { return String(localized: "Look-alike letters, made to pass for a token you know") }
        return n == 1 ? String(localized: "One letter borrowed to look like \(real)")
                      : String(localized: "\(n) letters borrowed to look like \(real)")
    }

    /// "No market prices it · Everyday on Base", the price half only when true.
    private func footLine(priced: Bool) -> String {
        var parts: [String] = []
        if !priced { parts.append(String(localized: "No market prices it")) }
        if let place = place { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// Where a letter that is not plain Latin came from: "Cyrillic", "Greek",
    /// "Accent", else "Look-alike"; nil for an ordinary letter or digit.
    static func origin(of letter: Character) -> String? {
        guard !letter.isASCII else { return nil }
        guard let scalar = letter.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x0400...0x052F: return String(localized: "Cyrillic")
        case 0x0370...0x03FF: return String(localized: "Greek")
        default:
            let decomposed = String(letter).decomposedStringWithCanonicalMapping.unicodeScalars
            if decomposed.count > 1, decomposed.first?.isASCII == true { return String(localized: "Accent") }
            return String(localized: "Look-alike")
        }
    }

    // MARK: - A fake transfer

    private var spam: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrow.down.circle.dotted")
                .dsGlyph(.title)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: amount ?? String(localized: "A token transfer"))
                .dsText(.heading34)
                .monospacedDigit()
                .strikethrough(true, color: DS.textTertiary)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
                .padding(.top, DS.Space.s2)
            Text(verbatim: wallet.map { String(localized: "Nothing left \($0)") }
                 ?? String(localized: "Nothing left your account"))
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: DS.Space.s2)
            Text("A spam token wrote this to advertise itself")
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: [FeedScreen.dayWord(landed), network].compactMap { $0 }.joined(separator: " · "))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "Everyday on Base", or whichever half is known.
    private var place: String? {
        switch (wallet, network) {
        case let (w?, n?): return String(localized: "\(w) on \(n)")
        case let (w?, nil): return w
        case let (nil, n?): return n
        default: return nil
        }
    }
}
