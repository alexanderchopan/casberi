import Foundation

/// The vibenet room's SCOPE — which of its four readings is on screen
/// (prd §482, 2026-08-26).
///
/// **Wallet's experience, vibenet's words.** `WalletSection` (§483) split that
/// room the same afternoon, and the user's instruction here was explicit about
/// what to copy and what not to: *"Vibenet has it's own categories, you already
/// have them basically. we have recent, holdings, keys, accounts… no need to
/// invent things or use wallet's exactly where we don't have. the goal is to
/// have this experience and overall look."* So the CONTROL is shared
/// (`DSSectionSwitcher`, one component, both rooms) and the VOCABULARY is not.
/// Vibenet has no Positions, no NFTs, no Permissions and no Risk — no money
/// deployed, no collectibles, and nothing granted to a third party — so
/// borrowing those names would be four scopes that are permanently empty or
/// four lies, and §83 bans both.
///
/// **Every one of these four is content the room already had.** Nothing was
/// invented to fill a strip: `holdings` is the bare hero plus the token tiles,
/// `recent` is the event rows that were the tail of the scroll, `accounts` is
/// the roster and the delegate spine, `keys` is the census and the expiry
/// runway. The scopes are a rearrangement, which is why the mapping is an
/// IDENTITY — no card changes group, so nothing can be lost in the move.
///
/// **THE ATTENTION STRIP DIED HERE, and this type is what replaced it.**
/// §482 gave the strip a row anatomy and a name, and the name moved three times
/// in one afternoon (Needs you → Worth a look → Risk) because the thing had no
/// stable identity: it was four unlike facts — a key's deadline, an account's
/// lock, an unlock's countdown, our own failed read — grouped only by "you
/// might want to look". Scoping dissolves it, because **every one of those
/// facts is already drawn in the scope that owns it**: the key's deadline is
/// the Keys runway (`VibenetKeyShelfRow`, same blue, same countdown), the lock
/// and the unlock are the roster row's own pill and ticking subtitle, and an
/// unreached account already says "Couldn't reach the chain" in its subtitle.
/// The strip existed only because those four were buried in one long scroll.
///
/// So `VibenetAttention` survives with its ranking intact and its job moved one
/// layer down: it no longer produces a view, it decides **which chip wears a
/// dot** (`attention(_:now:)`). The work it did is kept; the surface that could
/// not be named is gone.
enum VibenetSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case holdings
    case accounts
    case permissions

    var id: String { rawValue }

    /// The strip's order. `allCases` already declares it, but the order is a
    /// RULING rather than an accident of declaration (`WalletSection.order`'s
    /// own reasoning), so it is stated where a reader will look for it and
    /// where a self-test can assert it.
    ///
    /// **HOME LEADS (prd §491, amending §482's "Holdings leads").** That ruling
    /// was made before this room had a Home scope at all, and its objection was
    /// specific: opening on Accounts or Keys put a tap between the crown and
    /// its own breakdown. Home answers that outright, because Home IS the crown
    /// and its sparkline — and the instruction for this room is that it match
    /// Wallet, which opens on Home. `resolve` has fallen back to `.home` since
    /// the scope existed; the doc below and one guard were the only things that
    /// still said Holdings, which is how a ruling outlives its own reason.
    ///
    /// The original reasoning, kept because it is still why Holdings sits
    /// where it does in the order: the user moved the attention strip below the
    /// holdings card that afternoon —
    /// *"i think below because that way holdings and sparkline are together"* —
    /// because the crown, its sparkline and the per-token tiles are ONE reading
    /// at three grains. Opening on any other scope puts a tap between the crown
    /// and its own breakdown, which is the same split by a different route.
    static let order: [VibenetSection] = [.home, .activity, .holdings, .accounts, .permissions]

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .activity: return String(localized: "Activity")
        case .holdings: return String(localized: "Holdings")
        case .accounts: return String(localized: "Accounts")
        // **"Permissions", not "Keys" (user ruling, prd §491).** The scope
        // was named after the OBJECTS it lists and the room next door names
        // the same scope after the QUESTION — Wallet's Permissions answers
        // "who can act for me", and so does this one: a key here IS a grant
        // of authority, which is exactly what Wallet's top two rungs are.
        // §482 said this room has no Permissions because nothing is granted
        // to a third party; that was about token approvals and it was wrong
        // about keys.
        case .permissions: return String(localized: "Permissions")
        }
    }

    /// What the scope holds — the accessibility label and the tooltip. Short
    /// nouns are learnable but not self-explaining, and two of these are words
    /// this app uses elsewhere for something else: "Recent" is not the feed's
    /// recency, and "Keys" here are permissions on a devnet account rather than
    /// the credentials in `TokenVault`.
    var summary: String {
        switch self {
        case .home:     return String(localized: "The line, and the last few moves")
        case .activity: return String(localized: "What happened, newest first")
        case .holdings: return String(localized: "What these accounts hold")
        case .accounts: return String(localized: "The accounts you watch, and who can act for them")
        case .permissions: return String(localized: "What can act on your accounts, and when each lapses")
        }
    }

    /// The scopes this room can actually fill.
    ///
    /// **Derived from the room, never from the watch list**, for the reason the
    /// face rail's own gate gives: the two legitimately disagree — in the demo
    /// the card is a fixed fixture while the watch list holds whatever this
    /// device really watches — and a chip that opens an empty scope is the dead
    /// control §83 bans.
    ///
    /// `holdings` and `accounts` are unconditional once there is a room at all:
    /// a watched account always has a balance reading (even "couldn't be read",
    /// which is itself the answer) and always has a roster row. `keys` needs a
    /// key somewhere, and `recent` needs an event — both are genuinely absent
    /// on a fresh watch, and both appear the moment they are not.
    static func present(_ room: VibenetRoom, hasEvents: Bool) -> [VibenetSection] {
        guard !room.items.isEmpty else { return [] }
        // `home` is unconditional, the way Wallet's is: it is the front door
        // and its drawing is the crown's own line, which a watched account
        // always has (even "couldn't be read", which is itself the answer).
        var out: [VibenetSection] = [.home]
        if hasEvents { out.append(.activity) }
        // Holdings needs a token reading — the crown's native total is on Home
        // already, so a Holdings scope with nothing but ETH restates it.
        if room.items.contains(where: { !$0.tokenBalances.isEmpty }) { out.append(.holdings) }
        out.append(.accounts)
        if room.items.contains(where: { !$0.actors.isEmpty }) { out.append(.permissions) }
        return order.filter(out.contains)
    }

    /// Which chips wear a dot — `VibenetAttention`'s ranking, one layer down.
    ///
    /// A SET rather than one winner, mirroring `DSSectionSwitcher.attention`:
    /// several scopes can want you at once and each says so for itself, so
    /// nothing has to decide which alarm is "the" alarm. That also means the
    /// strip's rank ordering is no longer load-bearing for display — it still
    /// orders the lines, and nothing here reads that order.
    ///
    /// The mapping is the strip's own subjects, sent home: a key belongs to
    /// Keys, and both an account's lock and our failure to read it belong to
    /// Accounts. **An unreached read is deliberately NOT its own alarm** — it
    /// is a fact about an account, drawn on that account's row, and giving it a
    /// scope of its own would be this room grading its own failure as a
    /// category of the reader's business (§479's ordering rule, restated as a
    /// mapping).
    static func attention(_ room: VibenetRoom, now: Date = .now) -> Set<VibenetSection> {
        var out: Set<VibenetSection> = []
        for line in VibenetAttention.compose(room.items, now: now) {
            switch line.subject {
            case .key:       out.insert(.permissions)
            case .account:   out.insert(.accounts)
            case .unreached: out.insert(.accounts)
            }
        }
        return out
    }

    /// What to show when the stored choice is gone or was never made.
    ///
    /// **Resets to `home` rather than remembering**, and the divergence
    /// from `MarketsRoom.landing` is deliberate and is the same call
    /// `WalletSection` made: a venue there is a separate watchlist you were
    /// working in, so returning you to it is a kindness, while these four are
    /// FACETS OF ONE SUBJECT and the crown is the answer to "how is it going".
    /// A room that opens on Keys because you last looked at Keys hides the
    /// balance behind a tap for a reason you have long forgotten.
    static func resolve(_ wanted: VibenetSection?, present: [VibenetSection]) -> VibenetSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all. One scope is not a control,
    /// it is a label — §83's dead-control ban, in the room where the control's
    /// whole job is to say there is more than one thing to see.
    static func shows(present: [VibenetSection]) -> Bool { present.count > 1 }
}
