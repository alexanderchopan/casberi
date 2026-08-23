import SwiftUI

/// The face rail — ONE control, worn by every room whose contents divide by
/// somebody (prd §362, 2026-08-11).
///
/// **Why it is one type and not two that look alike.** It shipped as two: the
/// wallet rail (prd §128/§356/§357) scoped the Wallet category to one watched
/// address, and `SocialRosterHero` drew a row of faces at the head of the
/// Farcaster/Bluesky rooms that NAVIGATED to a person's own screen. They were
/// built months apart for different jobs and had drifted into three differences
/// — size (36 vs 56), an "All" slot on one and not the other, and one pinned as
/// chrome while the other scrolled away with the room — each individually
/// defensible and collectively an app that has to be learned twice.
///
/// The user's ruling (2026-08-11) is the one that settles it: *"the app has a
/// lot of superpowers and a lot of stuff, so we need to make it stupid simple
/// and the best way to do that is things being the same"*. So the social faces
/// FILTER, exactly as the wallet faces do, and the differences collapse into one
/// component with two adapters. A row of faces above a feed means the same thing
/// everywhere it appears: *these are the people/wallets this room is made of;
/// tap one to see only theirs, tap All to see everyone.*
///
/// **What that cost, and why it is affordable.** Tapping a social face used to
/// open that person's own room, and now it narrows the feed instead. The door
/// survives twice over: the ALREADY-LIT face re-taps into their room (the source
/// strip's own re-tap grammar, `MainSurface.sourceStrip`), and every post in the
/// feed still opens its author's room from the post itself
/// (`SocialPostThread`). What was lost is a one-tap shortcut that duplicated a
/// door already on every row; what was gained is that the row of faces above the
/// feed no longer means two different things in two different rooms.
///
/// **It is chrome, and chrome is pinned.** §357 hoisted the wallet rail to
/// `MainSurface.roomControls` because a scope control mounted inside
/// `FeedScreen` — which carries `.id(filter.source)` under a move transition —
/// is destroyed by the very move it commands. The social rail inherits that
/// wholesale rather than re-earning it: a filter you are standing in must show
/// you that you are standing in it, and its "All" is the exit, so a rail that
/// scrolls away is a filter with no visible way out.
///
/// **No glass**, per the design law's own "a mark someone recognizes stays
/// opaque" — frosting a face muddies the one thing it exists to be.
struct FaceScopeRail: View {
    /// One slot. `id` is the value written to the scope when picked, so it is
    /// whatever that scope speaks: a watched address for wallets, a handle for
    /// people.
    struct Item: Identifiable, Equatable {
        let id: String
        /// The word under the face — NEVER dropped on the fold (see `faceSize`),
        /// though a rail may name its pick elsewhere entirely and draw none of
        /// them (see `namesInRoom`). Set it either way: with the caption undrawn
        /// this is still the SPOKEN label, so a wallet is never an unlabelled
        /// button to VoiceOver.
        let caption: String
        let face: Face
        /// Draws the attention ring. Social only (someone posted since you last
        /// opened this room); wallets have nothing equivalent to say, which is
        /// precisely what frees the mark to carry SELECTION on a `namesInRoom`
        /// rail — see `ringWidth`, and never set both on one rail.
        var ringed: Bool = false
        /// Mac-only hover text, for when the caption is not the whole truth (a
        /// wallet's full address under a 12-character label).
        var tooltip: String?

        enum Face: Equatable {
            /// An identicon derived from the address itself.
            case wallet(address: String)
            /// A fetched avatar, falling back to the source's own mark.
            case avatar(url: String?, source: String)
        }
    }

    let items: [Item]
    /// The scope showing — nil is "All".
    let scope: String?
    /// The shell's fold state (`ShellChrome.minimized`). See `faceSize`.
    let compact: Bool
    /// **The room names the pick itself, so the rail draws faces only** (prd
    /// §450, 2026-08-22, user ruling on a mock: *"i almost feel like we should
    /// remove the names there"*, then *"D is best"*).
    ///
    /// ONE flag rather than a `captions` knob beside a `selectionRing` knob,
    /// and that is the whole point: those two are not independent settings, they
    /// are one ruling with two consequences. Dropping the caption takes the
    /// selection weight with it (§362 drew selection as opacity AND the
    /// caption's semibold), so the ring has to step in — and the ring is only
    /// free where `ringed` has nothing to say, which is the same rooms whose
    /// caption moved. Two flags would let a caller ask for a captionless rail
    /// with no visible selection at all, a state nobody designed.
    ///
    /// True only for the WALLET rail, and §362's sameness ruling is knowingly
    /// bent here rather than broken: the wallet room has a crown card directly
    /// under the rail with a caption slot already in it
    /// (`WalletBalanceHeadline.caption`), and a social room has neither that
    /// card nor five faces — a Farcaster roster runs to dozens, where unlabelled
    /// avatars are the §362 identicon problem at scale. So the rail keeps one
    /// anatomy and one behaviour; what differs is whether the name is drawn HERE
    /// or one card down, which is a fact about the room, not a style.
    var namesInRoom: Bool = false
    /// Scope equality. A closure because the two adapters do NOT agree on it:
    /// hex compares case-insensitively (EIP-55 case is a checksum) while a
    /// handle is a plain string. Getting this wrong empties a room rather than
    /// failing loudly, so it is the caller's to state.
    let matches: (String, String) -> Bool
    let onPick: (String?) -> Void
    /// Re-tapping the lit face. nil = re-tap does nothing (the wallet rail:
    /// there is no "deeper" a watched address goes).
    var onReTap: ((Item) -> Void)?
    /// The trailing verb, when the rail has one. nil = no slot.
    var addTitle: String?
    var onAdd: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `DS.Face.list` (36) at rest, `.row` (26) folded — the ramp's own tiers,
    /// not two literals invented here.
    ///
    /// **This is the size BOTH rails wear now**, and the social faces came down
    /// to it rather than the wallet faces going up to the social row's old 56.
    /// §356's reasoning decides it: pinned above a room, a rail is chrome and
    /// stays subordinate to the content it scopes. At 56 it read as the room's
    /// headline — which is exactly what `SocialRosterHero` was, and it is not
    /// what either of them is any more.
    ///
    /// **The rail compresses, it does not drop its captions** (user ruling,
    /// 2026-08-11: "i think we need the name captions and instead maybe make
    /// rail compress"). A caption is the one thing distinguishing "Main" from
    /// "Cold", or two friends whose avatars are both a dark square; an identicon
    /// is a hash, not a name you can read at a glance. Folding the words away
    /// leaves a row of coloured circles that says less the further you scroll —
    /// backwards, since the deeper you are in a stream the more you need to know
    /// whose it is. What is spare when you are reading is the SIZE of the
    /// portrait, not the identity under it.
    ///
    /// **`.row` is the FLOOR, not merely the next rung down** — the ramp's
    /// `.badge` (20) is right there and would take `slotHeight` to 40, under the
    /// 44pt touch minimum, on a control whose whole slot is the tap target. A
    /// folded rail that is prettier and no longer reliably tappable is a worse
    /// trade than not folding at all.
    private var faceSize: CGFloat {
        // A captionless rail has nothing left to give. Its slot is already at
        // `DS.Hit.min` (see `slotHeight`), so folding could only shrink the
        // circle inside a hole the same size — the one thing the note above
        // says a fold must not do. The rail arrives 20pt shorter than the
        // captioned one and stays there; `compact` is still passed, and still
        // gated on `!showsRail` at the call site, because the SOCIAL rail reads
        // it and the two share this initializer.
        guard !namesInRoom else { return DS.Face.list }
        return compact ? DS.Face.row : DS.Face.list
    }

    /// 66 is what buys a name room to read. Without a name the slot is exactly
    /// the touch floor, which is what makes the whole rail fit: All + five
    /// wallets (§170's cap) + the add verb is `7 × 44 + 6 × 2 + 2 × DS.Space.s4`
    /// = 356pt, inside the 393pt of an iPhone 17 Pro. The control stops
    /// scrolling on the phone it was measured against — a small phone still
    /// scrolls, and nothing here promises otherwise.
    private var slotWidth: CGFloat { namesInRoom ? DS.Hit.min : 66 }

    /// Slot height tracks the face, so the fold actually returns vertical space
    /// to the room rather than shrinking a circle inside a hole the same size.
    ///
    /// Captionless it is floored at `DS.Hit.min` instead, because the SLOT is
    /// the tap target: `faceSize + DS.Space.s1 * 2` lands on 44 at rest and
    /// would fall to 34 folded, under the floor, on a control whose whole slot
    /// is the thing you aim at.
    private var slotHeight: CGFloat {
        namesInRoom ? max(DS.Hit.min, faceSize + DS.Space.s1 * 2)
                    : faceSize + DS.Space.s1 + 16
    }

    /// How far an out-of-scope slot recedes (user, 2026-08-13: *"the avatars on
    /// socials that aren't selected but followed are very dim. same for
    /// wallet"*).
    ///
    /// **Nothing recedes while nothing is picked.** The rail's DEFAULT state is
    /// "All", where no item is `isOn` — so a flat `isOn ? 1 : dim` dimmed the
    /// entire roster the moment the room opened, which is the state the rail
    /// spends nearly all of its life in. That says "these are excluded" over a
    /// row of faces that are all included, in a room the person is looking at
    /// precisely because they follow every one of them. Recession is only
    /// meaningful against something raised; with no scope there is nothing to
    /// recede FROM, so every face sits at full strength and "All" is named by
    /// its own slot's ink and weight, exactly as before.
    ///
    /// **And when a scope IS picked it is 0.7, not 0.4.** The design law's "a
    /// mark someone recognizes stays opaque" is the same rule that keeps glass
    /// off these faces two paragraphs up; 40% of an avatar is a portrait behind
    /// frosting, and 40% of an identicon is a smudge. 0.7 is not a new number —
    /// it is what `scrollTransition` below already fades an edge slot to, so the
    /// control has ONE recessed weight rather than two that must be explained
    /// against each other. It also stops the two compounding: an edge slot in a
    /// scoped rail was 0.7 × 0.4 = 0.28, which is fainter than any disabled
    /// control in this app.
    ///
    /// Opacity is still doing less work than it looks like it is — the caption's
    /// weight and ink carry selection alongside it (see `slot`), which is what
    /// lets the dim end be this gentle without the lit face becoming ambiguous.
    private var restOpacity: Double { scope == nil ? 1 : 0.7 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                allSlot
                ForEach(items) { item in
                    slot(item)
                }
                if let addTitle, onAdd != nil {
                    addSlot(title: addTitle)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s1)
        }
        .scrollIndicators(.hidden)
    }

    /// "All" — the default, and the exit.
    ///
    /// It CANNOT be a pile of the faces themselves: at the wallet cap (§170)
    /// five overlapped portraits are mush at this size, and a social roster can
    /// run to dozens. It takes the strip's own "All" treatment instead — a word
    /// in a circle, which reads the same at any count.
    ///
    /// It carries NO caption, because the circle already IS the word; captioning
    /// it prints "All" twice in one slot, one above the other (caught on screen,
    /// 2026-08-11). The slot keeps its full height regardless, or every face
    /// beside it would sit a caption's-worth higher.
    ///
    /// **The circle is the same size as the faces, and always was** (user,
    /// 2026-08-11: "shouldn't All and + be the same size as the avatars?").
    /// Measured off the rendered frame: every circle was already exactly 102px
    /// wide. What differed was WEIGHT — `DS.fillFaint` is 3% black on the light
    /// theme, so the edge barely registered beside faces that are saturated
    /// gradients edge to edge. `DS.tintDim` is what "All" is in the strip too.
    /// **The lesson is the measurement**: "these look smaller" was a true
    /// observation with a false cause, and fixing it by growing the frame would
    /// have left the rail with two circle sizes to explain forever.
    private var allSlot: some View {
        let isOn = scope == nil
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(nil)
        } label: {
            VStack(spacing: DS.Space.s1) {
                Text("All")
                    .dsText(.label11).fontWeight(.semibold)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                    .frame(width: faceSize, height: faceSize)
                    .background(Circle().fill(DS.tintDim))
                // Reserves the caption's line so this circle sits level with
                // the faces beside it. With no captions in the rail there is no
                // line to reserve, and it centres in its slot instead.
                if !namesInRoom { Spacer(minLength: 0) }
            }
            .frame(width: slotWidth, height: slotHeight,
                   alignment: namesInRoom ? .center : .top)
            .opacity(isOn ? 1 : restOpacity)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsTooltip(String(localized: "Show everything"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One face over its name.
    ///
    /// **Selection is opacity and weight, never a ring** (§351's rule, which this
    /// control respects rather than restates): a tint ring already means "the
    /// active chip" one tier up in the strip and a dashed orange one means "needs
    /// reconnecting", so a third ring for selection would be a third meaning for
    /// one mark. The face itself is the identity, so it can carry selection by
    /// being the only one at full strength — which is also what leaves the ring
    /// free to keep saying the one thing it says here (`ringed`: they posted
    /// since you last looked).
    ///
    /// "The only one at full strength" is a claim that only makes sense once
    /// there IS one — see `restOpacity` for why an unscoped rail dims nothing.
    private func slot(_ item: Item) -> some View {
        let isOn = isOn(item.id)
        return Button {
            DSHaptic.selection()
            // Re-tapping the lit face goes DEEPER rather than doing nothing —
            // the source strip's own grammar (`MainSurface.sourceStrip`, where a
            // re-tap pops to root). It is what keeps a person's own room one tap
            // from the rail now that the first tap filters instead of navigating.
            if isOn {
                onReTap?(item)
            } else {
                onPick(item.id)
            }
        } label: {
            VStack(spacing: DS.Space.s1) {
                face(item.face)
                    .overlay(
                        Circle().strokeBorder(DS.tint, lineWidth: ringWidth(item, isOn: isOn))
                            .padding(-3)
                    )
                if !namesInRoom {
                    Text(item.caption)
                        .dsText(.label12)
                        .fontWeight(isOn ? .semibold : .regular)
                        .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                }
            }
            // `minHeight`: `slotHeight` reserves a hardcoded 16pt for the
            // caption, which is a `label12` and so needs roughly 43 at the
            // largest accessibility size. Pinned, the name under every face
            // was cut off; a floor keeps the rail's rhythm at every ordinary
            // size and lets it grow rather than clip at the extremes.
            .frame(minHeight: slotHeight, alignment: namesInRoom ? .center : .top)
            // A 44pt-wide slot is the touch floor; the extra width is what gives
            // a name room to read rather than truncate at the face — see
            // `slotWidth` for why a rail that names elsewhere gives it back.
            .frame(width: slotWidth)
            .opacity(isOn ? 1 : restOpacity)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        // **The tooltip is the only place the full identity can go.** The caption
        // is `lineLimit(1)` inside a 66pt slot, so an unnamed wallet reads as
        // `…4f4f` and two sharing those four characters are indistinguishable
        // at a glance — the exact failure `dsTooltip` was written for one tier
        // up, and the trade the one-truncation ruling accepts on purpose. It
        // stays Mac-only for that modifier's own reason: on a touch surface
        // `help()` becomes an accessibility HINT, and VoiceOver would then read a
        // 42-character hex after every wallet's name. The spoken label is left as
        // the caption — a summary a person can hear.
        .dsTooltip(item.tooltip ?? item.caption)
        // **The spoken label, which the caption used to supply for free.**
        // `dsTooltip` is Mac-only by its own ruling (on a touch surface `help()`
        // becomes an accessibility HINT, and VoiceOver would read a 42-character
        // hex after every wallet), so with the caption gone a slot's only
        // remaining content is an identicon — an image with no text in it at
        // all. VoiceOver would announce five unlabelled buttons. Set for BOTH
        // rails rather than only the captionless one: where the caption is
        // drawn this is the same string it already spoke, so the two can never
        // drift, and there is no `if` here to get backwards later.
        .accessibilityLabel(Text(item.caption))
        // Chips ease at the strip's edges instead of clipping flat — the source
        // strip's own grammar (SourceChips:370), one tier down (2026-08-04).
        // Under Reduce Motion only the fade survives.
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.7)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func face(_ face: Item.Face) -> some View {
        switch face {
        case .wallet(let address):
            WalletFace(address: address, size: faceSize, circular: true)
        case .avatar(let url, let source):
            if let url, !url.isEmpty {
                RemoteThumb(urlString: url, size: faceSize, fallback: source, circular: true)
            } else {
                BridgeIcon(name: source, size: faceSize, circular: true)
            }
        }
    }

    /// The trailing verb slot — same circle as "All", folding on the same ramp so
    /// the rail compresses as one object.
    private func addSlot(title: String) -> some View {
        Button {
            DSHaptic.selection()
            onAdd?()
        } label: {
            VStack(spacing: DS.Space.s1) {
                // `dsGlyph`, not `.font(.system(size:))` — a frozen glyph size
                // beside Dynamic-Type text is the class `design-ramp-audit.py`
                // exists to catch, and this one would have slipped past it on a
                // technicality: the audit matches a LITERAL size, and a ternary
                // is not one.
                Image(systemName: "plus")
                    .dsGlyph(compact ? 11 : 13)
                    .foregroundStyle(DS.tint)
                    .frame(width: faceSize, height: faceSize)
                    .background(Circle().fill(DS.tintDim))
                if !namesInRoom { Spacer(minLength: 0) }
            }
            .frame(width: slotWidth, height: slotHeight,
                   alignment: namesInRoom ? .center : .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityLabel(Text(title))
        // Captionless, so on Mac the tooltip is the only thing that says what
        // this circle does before you click it.
        .dsTooltip(title)
    }

    /// **The ring means ONE thing per rail, and the two can never coexist.**
    ///
    /// On the social rail `ringed` says "they posted since you last looked". On
    /// the wallet rail that flag is never set — `FaceScopeRail.Item.ringed`'s own
    /// doc says wallets have nothing equivalent to say — which is what leaves
    /// the mark free to carry selection there (prd §450). §351 reserves a tint
    /// ring for "the active chip" one tier up in the strip, and this is the same
    /// meaning one tier down, so it reads as the app being consistent rather
    /// than as a third sense for one mark.
    ///
    /// Gated on `namesInRoom` — the ADAPTER's flag, not a per-item one — so a
    /// rail is either a "posted since" rail or a "this is the pick" rail and
    /// never both at once. Without the caption's semibold, opacity alone was
    /// carrying selection, and `restOpacity` is a gentle 0.7 by ruling.
    private func ringWidth(_ item: Item, isOn: Bool) -> CGFloat {
        (item.ringed || (namesInRoom && isOn)) ? 2 : 0
    }

    private func isOn(_ id: String) -> Bool {
        guard let scope else { return false }
        return matches(scope, id)
    }
}

/// The wallet adapter (prd §128, widened to the whole Wallet category by §356,
/// hoisted to the shell by §357, folded into `FaceScopeRail` by §362).
enum WalletScopeRail {
    /// Whether the rail draws at all — which is ALSO the test for whether it,
    /// rather than a room's own header, carries the add-a-wallet verb
    /// (`FeedScreen.showsAddHint`). One rule with two readers on two different
    /// screens, so it is spelled once here: two `+`s a thumb-width apart, both
    /// opening the wallet manager, is one control too many, and a copy of this
    /// predicate in the feed would be free to drift out of step with the rail it
    /// is describing.
    static func shows(source: String, watched: Int) -> Bool {
        BridgeCatalog.category(forSource: source) == CategoryFold.walletCategory
            && watched > 1
    }

    static func items(_ addresses: [WalletStore.WatchedAddress]) -> [FaceScopeRail.Item] {
        addresses.map { addr in
            let label = addr.label.isEmpty ? WalletStore.shortAddress(addr.address) : addr.label
            return FaceScopeRail.Item(
                id: addr.address,
                caption: label,
                face: .wallet(address: addr.address),
                tooltip: addr.label.isEmpty ? addr.address : "\(addr.label) · \(addr.address)")
        }
    }

    /// Hex compares case-insensitively (EIP-55 case is a checksum), base58
    /// exactly (Solana case is identity) — `WalletWatch.sameAddress`, which the
    /// scope machinery (`WalletStore.scopeMatches`) already runs on.
    static func matches(_ scope: String, _ id: String) -> Bool {
        WalletWatch.sameAddress(scope, id)
    }

    /// What the CROWN CARD calls the scoped wallet (prd §450) — its name, and
    /// the address tail that goes beside it.
    ///
    /// **It lives here, next to `items`, because the rail and that card are now
    /// two halves of one answer**: the rail rings a face and says nothing, the
    /// card says who it is. Derived twice, the ringed face and the name a
    /// centimetre below it are free to disagree — and nothing would look wrong
    /// when they did.
    ///
    /// **A wallet with no name gets `shortAddress` and NO tail — deliberately
    /// not a fuller head-and-tail form**, though this line finally has the room
    /// for one. That spelling was retired on 2026-08-12 for "naming nobody",
    /// and the harder reason is that `AddressSafety.displayForm` keys on
    /// `shortAddress` ON PURPOSE: the display form IS the address-poisoning
    /// surface, so a second, longer truncation here would be the one place in
    /// the app whose display the lookalike check cannot see. The wallet with no
    /// name is also not the one anybody complained about.
    ///
    /// A stored label is only a name if a person typed it — `add`/`addBulk`
    /// file a bare address under its own short form as a display fallback, so
    /// `isAutoName` is what keeps the card from printing "…4f4f · …4f4f".
    static func caption(for address: String,
                        in addresses: [WalletStore.WatchedAddress])
    -> (name: String, detail: String?) {
        let short = WalletStore.shortAddress(address)
        guard let entry = addresses.first(where: { matches($0.address, address) }),
              !entry.label.isEmpty,
              !WalletStore.isAutoName(entry.label, for: entry.address)
        else { return (short, nil) }
        return (entry.label, short)
    }
}

/// The social adapter (prd §362, 2026-08-11) — what `SocialRosterHero` was,
/// minus the navigation and minus its own separate anatomy.
enum SocialScopeRail {
    /// Rooms whose rows divide by author. `FeedScreen.Shape` is the app's one
    /// answer to "is this a social room", so it is asked rather than a second
    /// list of source names kept in step with it by hand.
    static func shows(source: String, accounts: Int) -> Bool {
        FeedScreen.isSocialRoom(source) && accounts > 1
    }

    /// The room's watched accounts, in the STORE's own order.
    ///
    /// Deliberately not ranked by who has posted most, which is what the head
    /// card did. A head card is read once and may say whatever is most
    /// interesting; a pinned control is a place, and position is half the
    /// identity of a small circular face. The switcher one tier up made the same
    /// call for the same reason — "a capsule this short has not earned learned
    /// order and one that reshuffles between opens reads as broken".
    /// `source` is the FALLBACK mark for an account with no avatar — the
    /// network's own icon, exactly as the roster card drew it. Passed in rather
    /// than read off `SocialAccount.subtitle`, which is "@handle · bio" and would
    /// hand `BridgeIcon` a name matching no bridge, so every avatar-less account
    /// would fall through to the generic placeholder.
    static func items(_ accounts: [SocialAccount], source: String,
                      fresh: Set<String>) -> [FaceScopeRail.Item] {
        accounts.map { account in
            FaceScopeRail.Item(
                id: account.key,
                caption: account.title,
                face: .avatar(url: account.avatarURL, source: source),
                ringed: fresh.contains(account.key),
                tooltip: account.subtitle)
        }
    }

    /// A handle is a plain string — no checksum, no case games. Stated as its own
    /// function anyway so the two adapters are read side by side and the wallet
    /// rule can never be applied here by accident.
    static func matches(_ scope: String, _ id: String) -> Bool { scope == id }
}
