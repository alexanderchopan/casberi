import SwiftUI

/// The setup screen's chassis and its slot order (prd §608, 2026-09-04).
///
/// Sixty-two screens carry `BridgeSetupHeader`, and the vocabulary they draw
/// with has been standard since §190/§252/§315: one header, one slab family,
/// one disconnect row, one mode chip, one copy audit. What drifted was the
/// ANATOMY. Measured across the sixty-two as they stood, the same six blocks
/// were arranged in **forty-eight distinct orders**, and twelve screens put
/// the room door or the connected state ABOVE the identity block while the
/// rest put them below.
///
/// Two things follow, and they are deliberately different mechanisms.
///
/// **The chassis is a TYPE.** Every one of the sixty-two ended its `List` with
/// the same seven modifiers in the same order — `.listStyle(.insetGrouped)`,
/// `.scrollContentBackground(.hidden)`, `.bridgeSetupWash(name:)`,
/// `.dsAdaptiveContentWidth()`, `.dsPageBackground()`, `.dsSoftScrollEdges()`,
/// and the title. That is not a convention anybody chose sixty-two times; it
/// is one screen copy-pasted, and one of them (`AppleWalletScreen`) had
/// already lost `.listStyle` and one (`WalletScreen`) the wash, which is what
/// a copy-pasted chassis does over a year. It lives here now.
///
/// **The slot order is an AUDIT**, not a set of generic parameters, and the
/// reason is §595's, one day older: `setup-copy-audit.py` discovers a connect
/// screen by its `BridgeSetupHeader` call and reads that screen's intro and
/// its `RoomDoor(source:)` out of the same file. Six slot closures per screen
/// would have compiled, but it would also have meant a combinatorial pile of
/// convenience initializers for the screens that fill three of the six — and
/// the order is a fact about the SOURCE, which is exactly the kind of fact
/// this repo makes mechanical rather than remembered.
/// `scripts/setup-anatomy-audit.py` reads the body and fails the build when
/// the blocks are out of order.
///
/// ## The slots, in order
///
/// 1. **identity** — `BridgeConnectedState` when it is working,
///    `BridgeSetupHeader` when it is not. Who this is and whether it is done.
/// 2. **room** — `RoomDoor`. What just landed, one tap away.
/// 3. **act** — the ONE thing this screen is for: the connect form, the paste
///    field, the folder picker. `DSSlabButton`'s "a screen's one filled block"
///    rule governs here and only here.
/// 4. **more** — second acts that only exist once the first has happened
///    (X's author fetch, Instagram's caption pass, a watch list).
/// 5. **recent** — `RecentThingsSection`. Proof, in the person's own rows.
/// 6. **upkeep** — `ImportUpkeepSection`. How old this import is, and how to
///    take it back out.
/// 7. **exits** — `DevnetExplorerRow`, then `BridgeDisconnectSection`. The
///    ways off this screen, quiet, at the bottom, destructive last.
///
/// A screen fills the slots it has. It never reorders them, and the audit is
/// what makes that true a year from now rather than today.
struct BridgeSetupPage<Content: View>: View {
    /// The app whose wash this is. Kept as a name rather than a colour for
    /// `bridgeSetupWash`'s own stated reason.
    let name: String
    /// A LITERAL title — resolves through the string catalog, which is what a
    /// bare `.dsScreenTitle("Stripe")` did before this type existed, and four
    /// languages carry entries for some of these brand names.
    fileprivate var titleKey: LocalizedStringKey?
    /// A COMPUTED title (`bridge.rawValue`) — not localized, matching what
    /// `.dsScreenTitle` did for a `String` variable before. Keeping both
    /// spellings is deliberate: folding them into one would have quietly
    /// changed which overload thirty screens resolve to, in four languages,
    /// with nothing on screen to say so.
    fileprivate var titleText: String?
    @ViewBuilder var content: () -> Content

    private var list: some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: name)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
    }

    @ViewBuilder var body: some View {
        // Exactly one branch is ever taken for a given screen — the title
        // spelling is fixed at the call site — so this is a compile-time fork
        // wearing an `if`, not a view that can change identity at runtime.
        if let titleText {
            list.dsScreenTitle(titleText)
        } else {
            list.dsScreenTitle(titleKey ?? LocalizedStringKey(name))
        }
    }
}

extension BridgeSetupPage {
    /// The name is the title. The commonest case by far.
    init(name: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(name: name, titleKey: LocalizedStringKey(name),
                  titleText: nil, content: content)
    }

    init(name: String, title: LocalizedStringKey,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(name: name, titleKey: title, titleText: nil, content: content)
    }

    init(name: String, computedTitle: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(name: name, titleKey: nil, titleText: computedTitle,
                  content: content)
    }
}

/// What a setup screen says happened (prd §608).
///
/// `BridgeSyncStatusRows` took a free `String?` and a separate `Bool` saying
/// whether that string was a failure, and the two drifted apart in both
/// directions.
///
/// **The Bool was the dangerous half, and it had already shipped wrong.**
/// §252 found five screens passing a hardcoded `resultIsError: false` while
/// assigning real failures ("Couldn't reach the chain…") into the same
/// variable — so a network failure arrived in confirm green, wearing the
/// count-up animation, with no shake and no failure haptic. Each was fixed by
/// hand, and nothing stopped the sixth. **A failure that cannot be spelled
/// green is better than a failure somebody remembered to spell red**, so the
/// message and its tone are one value here and the pair is unrepresentable.
///
/// **The String was the drifting half.** Measured across the sixty-two setup
/// screens: fifteen distinct wordings for a successful outcome — "Up to date",
/// "\(n) new", "\(n) in", "\(n) landed…", "Connected", "Connected.",
/// "Connected — 1 app", "Connected to \(name)" — and thirty-six distinct lines
/// for "reading". The reading lines STAY free text and that is not an
/// oversight: "Reading the pool's doors…" is the one moment a bridge says what
/// it is actually doing, and it differs because the work differs. The
/// OUTCOMES are the same four events everywhere, so they are cases.
///
/// `landed`'s optional noun keeps the two shapes that were really carrying
/// meaning — "3 new" and "3 games in" — and collapses the other six spellings
/// of them.
enum BridgeProof: Equatable {
    /// Nothing arrived, and nothing was wrong. The commonest outcome.
    case upToDate
    /// Rows landed. `noun` nil reads "3 new"; a noun reads "3 games in".
    case landed(Int, noun: String? = nil)
    /// The handshake worked, before anything has synced. `detail` names what
    /// it connected TO when the bridge really holds that fact — never a guess
    /// (`BridgeConnectedState`'s identity rule, same reasoning).
    case connected(String? = nil)
    /// A line this bridge composes ITSELF, because the outcome really is
    /// several facts at once — an import receipt ("8,412 imported · 61 already
    /// here · 240 older not imported") is three numbers and cannot be one
    /// case without inventing a shape for every importer.
    ///
    /// **It is not an escape hatch for a count**, and the audit enforces that:
    /// a `says` whose text matches a canonical shape — a bare "N new", "Up to
    /// date", a lone "Connected" — fails the build, because `landed`,
    /// `upToDate` and `connected` exist precisely so those read the same on
    /// sixty-two screens. Reach for it when no other case is TRUE, never when
    /// another case is merely inconvenient.
    case says(String)
    /// It didn't work, in the bridge's own words. Free text on purpose: the
    /// whole value of this case is saying WHICH failure, and a closed set
    /// would collapse "check your connection" onto "that key was refused".
    case failed(String)

    var isFailure: Bool { if case .failed = self { return true }; return false }

    /// The line as drawn. `landed(0)` is `upToDate`, so a caller need not
    /// spell the ternary that forty-nine screens spelled by hand.
    var line: String {
        switch self {
        case .upToDate:
            return String(localized: "Up to date")
        case let .landed(count, noun):
            if count <= 0 { return String(localized: "Up to date") }
            guard let noun, !noun.isEmpty else {
                return String(localized: "\(count) new")
            }
            return String(localized: "\(count) \(noun) in")
        case let .connected(detail):
            guard let detail, !detail.isEmpty else {
                return String(localized: "Connected")
            }
            return String(localized: "Connected — \(detail)")
        case let .says(line):
            return line
        case let .failed(message):
            return message
        }
    }
}
