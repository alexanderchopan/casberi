import Foundation
import Observation

/// HIDE WALLET BALANCES (2026-08-13, prd §374, user: "should we add a way for a
/// user to 'hide balances'? i think we could make that a toggle in settings /
/// privacy", then "any dollar or token value, basically all the things in
/// wallet… so the setting is 'hide wallet balances'").
///
/// The case is shoulder-surfing, not secrecy: nothing about a balance leaves
/// this device, so this changes what a person STANDING NEXT TO YOU can read,
/// and nothing else. It sits in Privacy beside `privacy.hidePreviews` — the
/// same shape of promise, about the same threat — and ships OFF, because a
/// wallet whose figures are hidden by default is a wallet nobody can read.
///
/// ## Three rules, and each one is load-bearing
///
/// **1. It masks at the RENDER boundary and nowhere else.** The two dominant
/// formatters (`TokenStats.compact`, `WalletIngest.format`) are ALSO called at
/// INGEST — `WalletIngest` bakes `compact` into the persisted treemap doc and
/// interpolates `format` into every transfer title. Masking inside them would
/// write `••••` into stored data, where it would survive the toggle being
/// turned back off and would sync to every other device. So the mask is applied
/// by the view, to a string on its way to a `Text`, and the model never sees it.
///
/// **2. A hidden value must read as HIDDEN, never as zero and never as
/// unknown.** The wallet's honesty rails already spend both of those readings:
/// `WalletApprovalExposure` returns nil for "we can't know" and 0 only for a
/// grant that genuinely reaches nothing (§292), and `WalletFlow` declines to
/// draw rather than paint a confident picture of a tenth of a window. A mask
/// that rendered as "$0" or as a blank would collide with those and turn a
/// privacy setting into a false statement about somebody's money.
///
/// **3. Figures go, SHAPES stay.** A treemap cell keeps its area, a sparkline
/// keeps its curve, a share bar keeps its fill. Nobody reads a net worth off an
/// unlabelled shape, and blanking them would leave the room empty rather than
/// private — which is the difference between hiding a number and deleting the
/// screen. Percentages of a whole (an allocation share, a distance from
/// liquidation) stay for the same reason: they say proportion, not amount.
///
/// ## What it deliberately does not cover
///
/// The WALLET only, by the user's own ruling — a price on a token chart you
/// watch is public information about a market, not a statement about you.
@Observable
final class BalancePrivacy {
    static let shared = BalancePrivacy()

    private static let key = "privacy.hideBalances"

    /// Read through the singleton (never `UserDefaults` directly) so a view
    /// body that formats a value registers as an observer of this property and
    /// repaints the moment the toggle flips — otherwise the wallet would keep
    /// showing figures until something else happened to invalidate it.
    var hidden: Bool {
        didSet {
            guard hidden != oldValue else { return }
            UserDefaults.standard.set(hidden, forKey: Self.key)
        }
    }

    private init() { hidden = UserDefaults.standard.bool(forKey: Self.key) }

    /// HOLD TO PEEK (2026-08-27, prd §501) — true only while a finger is down
    /// on a withheld figure.
    ///
    /// **Never persisted, and that is the whole safety argument.** Until this,
    /// the only way to read one number was to leave for Privacy, flip the
    /// setting, come back, and remember to flip it again — and a setting left
    /// flipped is a setting that is off when you next hand somebody your
    /// phone. A reveal that cannot outlive the touch cannot be forgotten in
    /// the on position, so it strictly beats the errand it replaces on the
    /// very threat this feature exists for.
    ///
    /// **It reveals every withheld figure on screen, not the one under the
    /// finger.** `WalletValue`'s gates are static formatters called during a
    /// body pass with no idea which view is asking, so a per-figure peek would
    /// mean threading a flag through forty call sites — and the result would be
    /// worse anyway: a room with one figure lit and its own treemap labels
    /// still masked reads as a rendering fault rather than as a peek. The
    /// exposure is unchanged either way, because the whole screen is under the
    /// same eyes as the figure being held.
    ///
    /// `hidden` remains exactly what the Privacy toggle writes and reads; this
    /// is a transient lens over it, so nothing about the setting's own state,
    /// its copy, or its persistence changes.
    var peeking = false

    /// What the gates actually ask. `hidden` is the SETTING; this is whether a
    /// figure is withheld right now.
    var withheld: Bool { hidden && !peeking }

    /// Four bullets — enough to read as deliberately withheld at a glance, and
    /// narrow enough not to reflow a row built for "$8,924".
    static let mask = "••••"

    /// A formatted value on its way to a `Text`. Pass the string the formatter
    /// already produced; this decides whether it survives.
    func value(_ text: String) -> String { withheld ? Self.mask : text }

    /// A value that has a UNIT the mask should keep — "0.42 ETH" becomes
    /// "•••• ETH", not "••••".
    ///
    /// The unit is not a balance and hiding it costs the row its subject: a
    /// history of "Received ••••" tells you nothing about what you hold, while
    /// "Received •••• ETH" still says which asset moved. The same reasoning
    /// keeps a merchant, a counterparty and a date visible — this setting hides
    /// AMOUNTS, and turning it into a general redaction would be a different
    /// feature nobody asked for.
    func amount(_ text: String, unit: String?) -> String {
        guard withheld else { return text }
        guard let unit, !unit.isEmpty else { return Self.mask }
        return "\(Self.mask) \(unit)"
    }

    /// A whole sentence built around a value — the room heads compose these
    /// (`GnosisPayRoom.headline`, the composition strip's mover line), so the
    /// number cannot be intercepted on its own.
    ///
    /// Returns nil while hiding, and the CALLER decides what to do with that:
    /// most drop the line entirely, which is right, because a sentence whose
    /// only content was a figure has nothing left to say. Deliberately not a
    /// masked sentence — "•••• on your card in 30 days" reads like a rendering
    /// bug, where an absent line reads like a setting.
    func sentence(_ text: @autoclosure () -> String) -> String? {
        withheld ? nil : text()
    }
}

/// The wallet's DISPLAY formatters — `TokenStats.compact` and
/// `WalletIngest.format` with the privacy gate in front (prd §374).
///
/// It exists so the gate is in one place per shape rather than at forty call
/// sites, and so the rule is greppable: a wallet VIEW that calls
/// `TokenStats.compact` directly is a leak, which `scripts/hide-balances-audit.py`
/// fails the build over. The underlying formatters keep their old names and
/// their old behaviour precisely because INGEST still needs them unmasked —
/// see `BalancePrivacy`'s rule 1.
enum WalletValue {

    /// "$1.2M" for display — the room's compact dollar voice, gated.
    static func money(_ usd: Double) -> String {
        BalancePrivacy.shared.value(TokenStats.compact(usd))
    }

    /// "$8,924" for display — the EXACT dollar voice §292 uses on the approvals
    /// and address cards, where the whole job is ordering figures against each
    /// other and compacting would throw away the resolution the ranking is made
    /// of. Gated the same way.
    static func exactMoney(_ usd: Double) -> String {
        BalancePrivacy.shared.value(WalletApprovalExposure.money(usd))
    }

    /// "12,977 AERO" for display — the unit survives the mask (see
    /// `BalancePrivacy.amount`), so a hidden row still says which asset moved.
    static func token(_ amount: Double, _ symbol: String) -> String {
        BalancePrivacy.shared.amount("\(WalletIngest.format(amount)) \(symbol)",
                                     unit: symbol)
    }

    /// A bare number with no unit and no currency — a health factor, a vote
    /// weight. Gated because `WalletIngest.format` is also how token amounts
    /// are spelled, and a caller reaching for the raw formatter in a view is
    /// the leak this type exists to make visible.
    static func number(_ v: Double) -> String {
        BalancePrivacy.shared.value(WalletIngest.format(v))
    }

    // MARK: - The baked titles

    /// A wallet row's title, with its amount withheld while §374 is on.
    ///
    /// This is the feature's hardest surface and the densest one: every
    /// history row is `Text(thing.title)`, and that title — "Received 0.42 ETH
    /// from sam.eth" — was interpolated AT INGEST, so no formatter gate can
    /// reach it.
    ///
    /// ## Why it re-composes rather than redacting
    ///
    /// The cheap version is `title.replacingOccurrences(of: transferAmount,
    /// with: masked)`, and it was rejected: when the stamped string is not a
    /// verbatim substring of the title — a localization that reorders, a row
    /// landed before the field existed — the replacement quietly does NOTHING
    /// and the amount stays on screen. A privacy control whose failure mode is
    /// "shows it anyway, invisibly" is worse than one that hides too much, so
    /// this builds the line from the stamped fields instead and treats every
    /// case it cannot build as one to hide.
    ///
    /// It also keeps §363's rule intact: facts come from stamped fields and
    /// are never parsed back out of a localized title. The only thing read out
    /// of `transferAmount` is its trailing SYMBOL, and that field is one we
    /// stamp ourselves in a documented shape ("0.9962 ETH"), not prose.
    ///
    /// ## The three cases, in order
    ///
    /// 1. **Stamped transfer** — recomposed, keeping the direction, the asset
    ///    and the counterparty, because those are not balances and a row with
    ///    none of them is not a row.
    /// 2. **No stamped amount, and no digit anywhere in the title** — nothing
    ///    to hide, so it is left exactly as it is ("Approved Uniswap to manage
    ///    all Doodles", a mint, a delegation).
    /// 3. **No stamped amount, but the title carries digits** — masked WHOLE.
    ///    Over-hiding on purpose: this is the swap ("Swapped 0.5 ETH → 1,200
    ///    USDC"), the capped approval, and every transfer landed before these
    ///    fields existed. The row keeps its glyph, its time and its tap.
    ///
    /// **The stated limit:** case 3 is coarse, and rows that predate
    /// `transferAmount` can only ever be all-or-nothing, because for those the
    /// number exists solely inside the title. That is a real cost of the
    /// setting, not a bug to be fixed later by parsing.
    static func title(_ thing: Thing) -> String {
        guard BalancePrivacy.shared.withheld else { return thing.title }
        if let recomposed = maskedTransferTitle(thing) { return recomposed }
        guard thing.title.contains(where: \.isNumber) else { return thing.title }
        return BalancePrivacy.mask
    }

    /// Case 1 — nil whenever the row wasn't stamped as a one-directional
    /// transfer, which is exactly when the caller must fall back to hiding.
    private static func maskedTransferTitle(_ thing: Thing) -> String? {
        guard let direction = thing.transferDirection,
              let amount = thing.transferAmount, !amount.isEmpty
        else { return nil }
        let received = direction == "received"
        let masked = BalancePrivacy.shared.amount(amount, unit: symbol(in: amount))
        let verb = received ? String(localized: "Received") : String(localized: "Sent")
        guard let who = thing.transferCounterparty, !who.isEmpty else {
            return "\(verb) \(masked)"
        }
        return received ? String(localized: "\(verb) \(masked) from \(who)")
                        : String(localized: "\(verb) \(masked) to \(who)")
    }

    /// A transfer's stamped amount alone, gated — "4,242 USDT", no verb and no
    /// counterparty (prd §449).
    ///
    /// For the one caller that must NOT say a direction: the wallet's flagged
    /// pile, where the chain's own claim about who sent what is the thing
    /// being contradicted. nil when the row carries no stamped amount (landed
    /// before the field existed), which is the caller's cue to fall back to
    /// `title(_:)` rather than to invent one — the same all-or-nothing limit
    /// that method already states for its own case 3.
    ///
    /// Gated through `BalancePrivacy.amount`, so the unit survives §374's mask
    /// while the figure does not: a hidden row can still say the symbol was a
    /// lookalike, which is the whole reason it is in that pile.
    static func transferAmount(_ thing: Thing) -> String? {
        guard let amount = thing.transferAmount, !amount.isEmpty else { return nil }
        return BalancePrivacy.shared.amount(amount, unit: symbol(in: amount))
    }

    /// The asset symbol at the tail of a stamped `transferAmount` ("0.9962
    /// ETH" → "ETH"). Letters only and length-capped, the `MoneyReceipt.split`
    /// rule (§363): a spoofed token whose "symbol" is a phishing domain must
    /// not be promoted into the one slot the mask leaves visible. nil when the
    /// tail isn't a plausible symbol, which masks the amount whole.
    private static func symbol(in amount: String) -> String? {
        guard let tail = amount.split(separator: " ").last.map(String.init),
              tail.count >= 2, tail.count <= 12,
              tail.allSatisfy({ $0.isLetter })
        else { return nil }
        return tail
    }
}
