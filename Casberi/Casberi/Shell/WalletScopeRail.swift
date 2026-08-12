import SwiftUI

/// The wallet face rail (prd §128, widened to the whole Wallet category by
/// §356, hoisted to the shell by §357) — an "All" circle then one face per
/// watched wallet, then the verb that adds another. Scopes every Wallet-category
/// room (balance, Peer, Privacy Pools, Gnosis Pay, Railgun) to one watched
/// address.
///
/// **It lives on `MainSurface`, not on `FeedScreen`, and that is the whole of
/// §357.** It was a `safeAreaInset` INSIDE the feed, and the feed carries
/// `.id(filter.source)` under a full-page move transition — so every venue
/// change destroyed the rail and built a fresh one, sliding five identical
/// faces off one edge and back in from the other to say nothing had changed.
/// The scope had already been moved to the shell (`ShellChrome.walletScope`)
/// precisely because it spans the category; the control that sets it was still
/// a property of one room. Mounted at the shell it simply stands still while
/// the room travels beneath it, which is the argument the pinning was chosen
/// for in the first place.
///
/// It draws the social roster's own construction — `ShapedRows.faceSlot`'s
/// circular face over a name — rather than a row of word pills, so the stacked
/// controls stop being three glass capsules of words: categories are words in
/// circles, rooms are word pills, wallets are FACES.
///
/// **No glass, unlike the room switcher above it.** The design law already says
/// a mark someone recognizes stays opaque — frosting a face only muddies the one
/// thing it exists to be — so the faces sit ON the page rather than in a capsule
/// of their own, which also stops a third glass bar from stacking under the
/// other two.
struct WalletScopeRail: View {
    /// The watch list, in the person's own order.
    let addresses: [WalletStore.WatchedAddress]
    /// The scope showing — nil is "All".
    let scope: String?
    /// The shell's fold state (`ShellChrome.minimized`). See `faceSize`.
    let compact: Bool
    let onPick: (String?) -> Void
    let onAdd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the rail draws at all — which is ALSO the test for whether it,
    /// rather than a room's own header, carries the add-a-wallet verb
    /// (`FeedScreen.showsAddHint`). One rule with two readers on two different
    /// screens now, so it is spelled once here: two `+`s a thumb-width apart,
    /// both opening the wallet manager, is one control too many, and a copy of
    /// this predicate in the feed would be free to drift out of step with the
    /// rail it is describing.
    static func shows(source: String, watched: Int) -> Bool {
        BridgeCatalog.category(forSource: source) == CategoryFold.walletCategory
            && watched > 1
    }

    /// `DS.Face.list` (36) at rest, `.row` (26) folded — the ramp's own tiers,
    /// not two literals invented here.
    ///
    /// **The rail compresses, it does not drop its captions** (user ruling,
    /// 2026-08-11: "i think we need the name captions and instead maybe make
    /// rail compress"). A wallet's caption is the one thing distinguishing "Main"
    /// from "Cold"; an identicon is a hash, not a name you can read at a glance,
    /// so folding the words away would leave a row of coloured circles that says
    /// less the further you scroll — exactly backwards, since the deeper you are
    /// in a stream the more you need to know whose it is. What is spare when you
    /// are reading is the SIZE of the portrait, not the identity under it.
    ///
    /// `DS.Face.list` is where the whole rail was pinned rather than the shelf
    /// tier's 56 (§356's own note: pinned above a room the rail is chrome and
    /// stays subordinate to it), so the fold takes it one rung further down the
    /// same ramp instead of introducing a size the app draws nowhere else.
    ///
    /// **`.row` is the FLOOR, not merely the next rung down** — the ramp's
    /// `.badge` (20) is right there and would take `slotHeight` to 40, under the
    /// 44pt touch minimum, on a control whose whole slot is the tap target. A
    /// folded rail that is prettier and no longer reliably tappable is a worse
    /// trade than not folding at all.
    ///
    /// **The "All" and "+" circles are the SAME size as the faces, and always
    /// were** (user, 2026-08-11: "shouldn't All and + be the same size as the
    /// avatars?"). Measured off the rendered frame: all five circles are exactly
    /// 102px wide. What differed was WEIGHT — they carried `DS.fillFaint`, which
    /// on the light theme is 3% black, so the circle's edge barely registered and
    /// only the glyph inside read, beside faces that are saturated gradients edge
    /// to edge. They take `DS.tintDim` now, the same wash §358 gave the strip's
    /// word chips, which is what "All" is in both places. **The lesson is the
    /// measurement**: "these look smaller" was a true observation with a false
    /// cause, and had it been fixed by growing the frame the rail would have
    /// ended up with two circle sizes to explain forever.
    private var faceSize: CGFloat { compact ? DS.Face.row : DS.Face.list }

    /// Slot height tracks the face, so the fold actually returns vertical space
    /// to the room rather than shrinking a circle inside a hole the same size.
    /// 46pt folded, 56pt at rest — see `faceSize` for why it may not go lower.
    private var slotHeight: CGFloat { faceSize + DS.Space.s1 + 16 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                chip(address: nil)
                ForEach(addresses) { addr in
                    chip(address: addr.address,
                         label: addr.label.isEmpty ? addr.short : addr.label)
                }
                // "Add another wallet" belongs WITH the wallets (user,
                // 2026-08-11). It used to be a bare `+` in the room's header
                // capsule beside a status line — which in a room that now draws
                // every watched wallet as a face read as an orphan: the one
                // control about wallets, sitting on the one row that isn't. The
                // header keeps `Manage`, which is its real job; the rail takes
                // the verb that acts on it.
                addSlot
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s1)
        }
        .scrollIndicators(.hidden)
    }

    /// The trailing "add another wallet" slot — same circle as "All", folding on
    /// the same ramp so the rail compresses as one object.
    private var addSlot: some View {
        Button {
            DSHaptic.selection()
            onAdd()
        } label: {
            VStack(spacing: DS.Space.s1) {
                // `dsGlyph`, not `.font(.system(size:))` — a frozen glyph size
                // beside Dynamic-Type text is the class `design-ramp-audit.py`
                // exists to catch, and this one would have slipped past it on a
                // technicality: the audit matches a LITERAL size, and a ternary
                // is not one. Inherited from the code this rail was lifted out
                // of; fixed on the way rather than carried over.
                Image(systemName: "plus")
                    .dsGlyph(compact ? 11 : 13)
                    .foregroundStyle(DS.tint)
                    .frame(width: faceSize, height: faceSize)
                    .background(Circle().fill(DS.tintDim))
                Spacer(minLength: 0)
            }
            .frame(width: 66, height: slotHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add a wallet"))
    }

    /// One face over its name — `ShapedRows.faceSlot`'s construction, the
    /// grammar the wallet manager's own roster and the social roster already
    /// share (prd §356).
    ///
    /// **Selection is opacity and weight, never a ring** (§351's rule, which this
    /// control has to respect rather than restate): a tint ring already means
    /// "the active chip" one tier up in the strip and a dashed orange one means
    /// "needs reconnecting", so a third ring here would be a third meaning for
    /// the same mark. The face itself is the identity, so it can carry selection
    /// by simply being the only one at full strength.
    /// A nil `address` is the "All" slot, which draws its own word and takes no
    /// caption — hence the defaulted `label`.
    private func chip(address: String?, label: String = "") -> some View {
        let isOn = isOn(address)
        return Button {
            guard !isOn else { return }
            DSHaptic.selection()
            onPick(address)
        } label: {
            VStack(spacing: DS.Space.s1) {
                if let address {
                    WalletFace(address: address, size: faceSize, circular: true)
                    Text(label)
                        .dsText(.label12)
                        .fontWeight(isOn ? .semibold : .regular)
                        .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                } else {
                    // "All" has no identity to wear, and it CANNOT be a pile of
                    // the faces themselves — at the five-wallet cap (§170) an
                    // overlapped composite is mush at this size. It takes the
                    // strip's own "All" treatment instead: a word in a circle,
                    // which reads the same at any count.
                    //
                    // And it carries NO caption, because the circle already IS
                    // the word — captioning it prints "All" twice in one slot,
                    // one above the other (caught on screen, 2026-08-11). The
                    // slot keeps its full height regardless, or every face
                    // beside it would sit a caption's-worth higher.
                    Text("All")
                        .dsText(.label11).fontWeight(.semibold)
                        .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                        .frame(width: faceSize, height: faceSize)
                        .background(Circle().fill(DS.tintDim))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: slotHeight, alignment: .top)
            // A 44pt-wide slot is the touch floor; the extra width is what gives
            // a name room to read rather than truncate at the face.
            .frame(width: 66)
            .opacity(isOn ? 1 : 0.4)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// Hex compares case-insensitively (EIP-55 case is a checksum), base58
    /// exactly (Solana case is identity) — `WalletWatch.sameAddress`, which the
    /// scope machinery (`WalletStore.scopeMatches`) already runs on. `FeedScreen`
    /// carried a private byte-identical copy of that rule until this moved;
    /// there is one now.
    private func isOn(_ address: String?) -> Bool {
        guard let address else { return scope == nil }
        guard let sel = scope else { return false }
        return WalletWatch.sameAddress(sel, address)
    }
}
