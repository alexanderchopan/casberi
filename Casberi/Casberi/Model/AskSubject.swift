import Foundation

/// WHAT THE DESTINATION YOU PICKED CAN ACTUALLY SEE (prd §577, 2026-09-02).
///
/// The ask surface turns blue and gives the chosen destination a 176pt face;
/// under it there is room for one reading. This decides what that reading is,
/// and it exists as its own Foundation-only type for one reason: **every
/// candidate for that slot is a claim about somebody else's system, and the
/// wrong claim there is the §83 fake status on the screen where believing it
/// costs money.**
///
/// ## THE CORRECTION THIS TYPE EXISTS TO ENCODE
///
/// The first cut of this surface drew the watched wallets' combined value —
/// "Bankr can see $19,742 in 3 wallets" — because it was the biggest true
/// number the app had lying around. **It is not true of Bankr.** Bankr acts on
/// the account held at bankr.bot behind the key you pasted; the addresses you
/// watch in Casberi are a different set of money that Bankr has never been told
/// about and cannot reach. Printing this app's total under Bankr's face would
/// have told somebody their watched wallet was the thing about to be traded.
///
/// So the wallet reading is **not available to any agent**, and the type says
/// so by having no case for it. What is left is what is genuinely ours:
///
/// - **The corpus.** The device and every model-behind-a-key are handed the
///   numbered candidates (`OnDeviceModel.numberedCandidates`), so the live
///   match count is a true statement about what that destination will read.
/// - **Nothing, for Bankr.** It grounds on its account and never on the
///   candidates — its own bridge comment says so — so the match count would be
///   a lie there too, and there is no second figure to put in its place. **A
///   "things Bankr has done for you" count was drawn and then refused on a
///   grep**: §529 describes landing a `.run` row per completed job
///   (`bankr:job:<id>`) and the 2026-08-31 amendment that collapsed the two
///   verbs took it with it — nothing in the tree lands one, so the figure had
///   no source and would have been a count of zero things dressed as a record.
///   The empty Bankr surface is therefore its face, the invitation at the head
///   rung, and no figure at all, which is §563's ruling anyway: the one act on
///   a surface takes the crown.
///
/// ## WHY THE CAPTION IS PART OF THE READING
///
/// A bare "3" under Bankr's face is unreadable, and a figure whose caption is
/// written at the call site is a figure whose caption drifts away from it. The
/// two travel together or neither is trustworthy.
enum AskSubject {

    /// What a destination reads from before it answers.
    enum Ground: Equatable {
        /// The things you saved — the numbered candidates this destination is
        /// handed. The device and every model-behind-a-key.
        case corpus
        /// Its own account, which this app has never read and cannot show.
        /// Bankr, and only Bankr.
        case ownAccount
        /// A local search over the corpus. Find.
        case search
    }

    /// The `AgentProvider.rawValue`s that answer from an account of their own
    /// rather than from the things we hand them.
    ///
    /// A SET rather than a check against one name, because the distinction is
    /// a property a second seat could have (an agent with its own exchange
    /// account would join it) — and because a bare `== "bankr"` at three call
    /// sites is how one of them ends up not updated.
    static let ownAccountAgents: Set<String> = ["bankr"]

    static func ground(forAgent raw: String?) -> Ground {
        guard let raw else { return .corpus }
        return ownAccountAgents.contains(raw) ? .ownAccount : .corpus
    }

    // MARK: - The reading

    /// A figure and the words that make it readable. Never one without the
    /// other.
    struct Reading: Equatable {
        let figure: String
        let caption: String
    }

    /// The corpus reading — what the live search has matched so far.
    ///
    /// **Nil under one match, and nil while the read is still out.** A `0` at
    /// the crown rung is a verdict on your typing delivered in the largest type
    /// the app owns, and a count still in flight is honestly absent rather than
    /// stale — so the two silences read the same and neither is a claim.
    /// (`draftCrown`'s own 2026-09-02 rule, carried here whole.)
    static func corpus(matches: Int?) -> Reading? {
        guard let matches, matches > 0 else { return nil }
        return Reading(figure: "\(matches)",
                       caption: String(localized: "match so far"))
    }

    // MARK: - The line under the words

    /// The one sentence under a draft, saying where this destination looks.
    ///
    /// **Bankr's is the disclosure, and it is the most valuable line on the
    /// screen** — somebody typing "swap half my eth" into this app has every
    /// reason to think it means the ETH the app is showing them, and it does
    /// not. It is stated where the instruction is being written rather than in
    /// a sheet afterwards, because by then it is a confirmation of a mistake
    /// rather than a chance not to make one.
    ///
    /// The other grounds get nil, not a sentence: the corpus reading above
    /// already carries its own caption, and a second line restating it is
    /// §213's restatement.
    static func draftNote(ground: Ground, agent: String?) -> String? {
        switch ground {
        case .ownAccount:
            let name = agent ?? String(localized: "This agent")
            return String(localized: "\(name) acts on its own account — not the wallets you watch here.")
        case .corpus, .search:
            return nil
        }
    }

    /// The invitation, per ground. An agent that can act is invited to be told
    /// what to do as well as asked; everything else is asked.
    static func invitation(ground: Ground) -> String {
        switch ground {
        case .ownAccount: return String(localized: "Ask, or tell it what to do")
        case .corpus, .search: return String(localized: "Ask or search")
        }
    }
}
