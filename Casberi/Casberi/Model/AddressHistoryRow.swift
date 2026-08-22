import Foundation

/// A history row on an ADDRESS's own profile, split into the two things a row
/// on that screen has to say (2026-08-22, prd §443).
///
/// ## Why the split exists
///
/// Every row in `AddressCard.historySection` drew `WalletValue.title(thing)` —
/// "Sent 0.25 ETH to Mom" — six times, on Mom's own profile, under a 76pt
/// portrait of Mom with her name at `heading28` above it. The counterparty
/// clause is the screen restating its own subject on every line, and it is
/// also the widest part of the string, so the DATE (the only per-row fact the
/// eye is actually scanning for) was pushed to a second line under a title
/// that had already been clamped.
///
/// So: the verb leads, the stamped amount trails with its sign, and the date
/// rides under the amount. Direction then reads straight down the right edge
/// of the column instead of being buried mid-sentence in six different
/// horizontal positions.
///
/// ## The three rules, each load-bearing
///
/// **1. Facts come from STAMPED FIELDS, never from the title.** §363's rule,
/// and the reason this takes `direction`/`amount` rather than a string to
/// parse: a localized title reorders, and a row landed before those fields
/// existed has the number only inside its prose. A row that cannot be split
/// keeps its whole sentence — which is why `fallbackTitle` is a parameter and
/// not something this type derives.
///
/// **2. The counterparty is dropped only because the SCREEN is the
/// counterparty.** Nothing here is reusable on the feed, where the same row
/// must name who it dealt with. That is why this lives beside the card rather
/// than inside `WalletValue`: the elision is a property of the surface, not of
/// the row.
///
/// **3. The SIGN survives §374's mask and the figure does not.** Which way the
/// relationship ran is not a balance — the identical ruling `summaryLine`
/// already makes for the net line one section up ("net −0.80 ETH" → "net
/// −•••• ETH"). The symbol survives too, for `BalancePrivacy.amount`'s own
/// stated reason: a row reading "−••••" has lost its subject, "−•••• ETH"
/// still says which asset moved.
///
/// ## What it deliberately does NOT decide
///
/// Colour. A view that tints `+` green and `−` red turns a ledger into a
/// verdict — "+120 USDC" in confirm-green congratulates you for your mother
/// paying you back, and the same green on a duster's inbound transfer
/// congratulates you for being dusted. Direction is a fact on this screen and
/// wears the text ramp like every other fact; `address-history-row-selftest.sh`
/// fails the build if the card ever reaches for `DS.confirm` or
/// `DS.destructive` in the history rows.
///
/// Foundation-only by design, so the harness compiles it WHOLE and unmodified.
/// `hidden`/`mask` are parameters rather than reads of `BalancePrivacy.shared`
/// for the same reason — the gate stays at the call site, where the audit can
/// see it.
enum AddressHistoryRow {

    /// What a row draws: a lead phrase, and a trailing signed amount when the
    /// row was stamped as a one-directional transfer.
    struct Parts: Equatable {
        /// The left column. Either the verb alone ("Sent") or, for a row that
        /// could not be split, its whole title.
        var lead: String
        /// The right column, signed. nil for a row with no stamped transfer —
        /// an approval, a mint, a Peer fill — which keeps its sentence in
        /// `lead` and states nothing on the right but its date.
        var amount: String?
    }

    /// Split one row.
    ///
    /// - Parameters:
    ///   - direction: `Thing.transferDirection` — "sent" or "received", or nil.
    ///   - amount: `Thing.transferAmount`, stamped as "0.9962 ETH".
    ///   - fallbackTitle: what the row draws when it cannot be split. Pass
    ///     `WalletValue.title(thing)`, which has already applied §374's mask
    ///     to the prose — this type never masks a title it did not build.
    ///   - hidden: `BalancePrivacy.shared.hidden`.
    ///   - mask: `BalancePrivacy.mask`.
    static func parts(direction: String?,
                      amount: String?,
                      fallbackTitle: String,
                      hidden: Bool,
                      mask: String) -> Parts {
        guard let direction, direction == "sent" || direction == "received",
              let amount, !amount.trimmingCharacters(in: .whitespaces).isEmpty
        else { return Parts(lead: fallbackTitle, amount: nil) }

        let received = direction == "received"
        let verb = received ? String(localized: "Received") : String(localized: "Sent")
        // A true MINUS, not a hyphen — the same glyph `summaryLine` uses for
        // the net line directly above these rows, so the two agree.
        let sign = received ? "+" : "\u{2212}"
        let (figure, symbol) = split(amount)
        let shown = hidden ? mask : figure
        guard let symbol else { return Parts(lead: verb, amount: sign + shown) }
        return Parts(lead: verb, amount: "\(sign)\(shown) \(symbol)")
    }

    /// "0.9962 ETH" → ("0.9962", "ETH"); "1,200 USDC" → ("1,200", "USDC").
    ///
    /// The symbol is the trailing token and only when it is a plausible one —
    /// letters only, 2…12 characters, the `MoneyReceipt.split` rule (§363).
    /// A spoofed token whose "symbol" is a phishing domain must not be promoted
    /// into the one slot §374's mask leaves visible, and an amount whose tail
    /// is not a symbol is returned whole rather than guessed at.
    ///
    /// Any sign already on the stamped string is stripped: direction carries
    /// the sign here, and a stamped "-0.25" would otherwise print "−−0.25".
    static func split(_ amount: String) -> (figure: String, symbol: String?) {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        let pieces = trimmed.split(separator: " ")
        guard let tail = pieces.last.map(String.init), pieces.count >= 2,
              tail.count >= 2, tail.count <= 12, tail.allSatisfy(\.isLetter)
        else { return (unsigned(trimmed), nil) }
        let head = pieces.dropLast().joined(separator: " ")
        return (unsigned(head), tail)
    }

    private static func unsigned(_ text: String) -> String {
        var out = text
        while let first = out.first, first == "-" || first == "+" || first == "\u{2212}" {
            out.removeFirst()
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
