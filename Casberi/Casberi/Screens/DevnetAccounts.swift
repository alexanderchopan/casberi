import SwiftUI

/// **THE FOUR DEVNET SETUP SCREENS SHARE ONE ANATOMY (user, 2026-09-04:
/// "i think they should share common framework and also be better").**
///
/// Base Vibenet, Ethrex Hegotá, Frames Devnet and Ethrex Privacy all ask the
/// same thing of somebody — *which addresses on this chain do you want to
/// read?* — and until this file they asked it four different ways. Measured
/// across the four screens as they stood:
///
/// * **Three affordances for one act.** Vibenet drew face rows carrying a
///   `Watch` / `✓ Watching` state; Hegotá and Frames drew title-plus-address
///   rows with a tint-coloured word at the end; Privacy drew `DSSlabDoor`s
///   under a heading. One tap, three shapes.
/// * **Two field components.** Vibenet used `DSSlabField` with a live address
///   preview; the other three used `BridgeFieldRow` with a hand-rolled result
///   line underneath. Three copies of "That isn't an address", three
///   wordings.
/// * **The field led on every screen** — and every one of those screens
///   carries a doc comment saying, in its own words, that a pasted stranger's
///   address shows a correct blank that reads like a broken feature. The
///   examples are the answer to that and they sat at the bottom.
///
/// **THE FIELD IS AT THE TOP OF THE SLAB, ABOVE THE EXAMPLES (user ruling,
/// 2026-09-04: "i think the watch / paste field should be at top not
/// bottom").** So the reading is: here is the box, and here are addresses to
/// put in it if you have none of your own. One card, one act, no hunting
/// below the fold for the thing that makes the screen usable.
///
/// **Why a shared CONTROL and not a shared SCREEN.** `VibenetWatchViews`'s own
/// header already draws this line and it holds here: `AddressBookScreen`'s
/// ruling is "copy the structure, not the type" for a screen's LAYOUT, and
/// this is one control appearing four times. Keeping four screen files also
/// keeps four `BridgeSetupHeader` calls and four `RoomDoor`s where
/// `setup-copy-audit.py` can see them — folding the whole body into one
/// generic view would have moved every intro and every room `source:` out of
/// the audit's reach, and silently dropped four screens' copy coverage.
///
/// **The watch list is a PROTOCOL rather than four closures.** The four
/// `@Observable` singletons already carry byte-identical APIs; a generic over
/// them means the row reads the real list, so SwiftUI's observation still
/// redraws a row the moment its address is watched. A closure bag would have
/// broken exactly that, and the failure would be a `Watch` verb that never
/// turns into a check — the §83 dead control these rows were rebuilt to
/// delete.

// MARK: - The watch list

/// What every devnet watch list can do. Deliberately READ-AND-WATCH only:
/// there is no `removeAll`, no naming and no key here, because those are acts
/// the shared controls never make and a protocol that named them would invite
/// one to.
protocol DevnetWatchList: AnyObject, Observable {
    var addresses: [String] { get }
    var connected: Bool { get }
    func isWatching(_ address: String) -> Bool
    @discardableResult func add(_ raw: String) -> Bool
    func remove(_ address: String)
    func name(for address: String) -> String?
    /// Static, so the field can arm its verb against the seat's own rule
    /// without an instance — and so a field can never be armed by one chain's
    /// rule while writing another chain's list.
    static func isValidAddress(_ raw: String) -> Bool
}

extension VibenetWatch: DevnetWatchList {}
extension HegotaWatch: DevnetWatchList {}
extension FramesWatch: DevnetWatchList {}
extension PrivacyDevnetWatch: DevnetWatchList {}

// MARK: - An example account

/// An address worth handing somebody, and the claim it makes about itself.
///
/// The claim is the whole reason these exist: every one of these chains is
/// small enough that a random address shows nothing, so an example is only
/// worth a row if it says what watching it will SHOW. "An address holding
/// coins · Shows the vault's unspent pieces" is a row; a bare address is a
/// fact you cannot act on.
///
/// **Each seat's list is MEASURED against its own chain and dated in the
/// seat's own file**, never invented here — if a chain is reset these become
/// ordinary addresses rather than broken ones, which is why the copy says
/// what they showed rather than promising what they will.
struct DevnetExample: Identifiable {
    let address: String
    let title: String
    let detail: String
    var id: String { address }
}

// MARK: - One row

/// The row shape every devnet account wears: a face, a claim, the address,
/// and a trailing word saying what the tap does — or that you already took it.
///
/// **A row you have taken says so and stops being tappable** (the 2026-08-28
/// vibenet ruling, generalised). `add` refuses a duplicate, so before this a
/// second tap on a taken row did precisely nothing while looking exactly like
/// a tap that worked. `.disabled` is enough because the whole control is text
/// and the text changes — §83's corollary about a button painting its own
/// background does not bite here.
struct DevnetAccountRow: View {
    let address: String
    let title: String
    var detail: String? = nil
    let watching: Bool
    let tint: Color
    /// This phone's own key, where the seat has one. Draws the same row so it
    /// reads as one more account rather than a special case, and skips the
    /// identicon for a mark that says whose it is.
    var isMine = false
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                face
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(title))
                        .dsText(.callout15)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // Both facts on one line: what it shows, then which
                    // address it is. Two lines of tertiary text under a
                    // 15pt title is the wall §315 keeps deleting.
                    Text(subtitle)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                verb
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(watching)
        .animation(DS.Motion.standard, value: watching)
    }

    private var subtitle: String {
        let short = WalletStore.shortAddress(address)
        guard let detail, !detail.isEmpty else { return short }
        return "\(detail) · \(short)"
    }

    @ViewBuilder private var face: some View {
        if isMine {
            ZStack {
                Circle().fill(DS.gray100)
                Image(systemName: "iphone")
                    .dsGlyph(15, weight: .medium)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(width: DS.Face.list, height: DS.Face.list)
        } else {
            WalletFace(address: address, size: DS.Face.list, circular: true)
        }
    }

    @ViewBuilder private var verb: some View {
        if watching {
            Label(String(localized: "Watching"), systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(String(localized: "Watch"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - The accounts slab

/// **Paste at the top, examples under it, in one card.**
///
/// Generic over the seat's watch list so the rows read the real one — see the
/// file header on why that is a protocol rather than a closure bag.
///
/// The status line lives here rather than at the call site because all four
/// seats had written their own version of the same three sentences (a
/// malformed address, a duplicate, and — on vibenet — a chain that could not
/// be reached), and three of the four disagreed on the wording of the first
/// two.
struct DevnetAccountsSlab<W: DevnetWatchList>: View {
    let watch: W
    /// The seat's own colour, for the `Watch` verb only. Nothing else on the
    /// slab is tinted: the colour says which row is actionable, and a card
    /// full of it says nothing.
    let tint: Color
    /// Measured, dated in the seat's own file. May be empty — a chain with
    /// nothing worth pointing at draws the field alone rather than an
    /// apology.
    var examples: [DevnetExample] = []
    /// This phone's signing address, on the seats that make a key. Nil where
    /// the seat is watch-only.
    var mine: String? = nil
    /// What this phone's row says under its title.
    var mineDetail: String = ""
    /// A read is in flight — shown, never blocking.
    var syncing: Bool = false
    var syncingLine: String = ""
    /// The line under the field when nothing has been typed and nothing has
    /// failed. Nil where a roster below already says what is watched.
    var idleNote: String? = nil
    /// Register the seat. Done HERE, in the control, not left to each
    /// embedder: four screens draw this list and a seat that forgot to
    /// register reads perfectly right up until the catalog disagrees with it.
    let register: () -> Void
    /// Fires only after an address really landed — never after a duplicate or
    /// a rejected paste.
    let onWatched: (String) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool
    @State private var result: String?
    @State private var resultIsError = false

    private var draft: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the preview is about, or nil while the field holds nothing
    /// that is already one. A plain validity check, never a lookup: none of
    /// these chains has a name registrar, and a live read fired per keystroke
    /// would be a claim about an account nobody has agreed to watch yet.
    private var previewAddress: String? {
        W.isValidAddress(draft) ? draft : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSlabField(placeholder: String(localized: "0x… devnet address"),
                        text: $typed,
                        actionLabel: String(localized: "Watch"),
                        focus: $focused,
                        isArmed: previewAddress != nil,
                        action: watchTyped)

            addressPreview
                .animation(DS.Motion.standard, value: previewAddress)

            BridgeSyncStatusRows(
                syncing: syncing,
                syncingLine: syncingLine,
                result: result ?? (previewAddress == nil ? idleNote : nil),
                resultIsError: result == nil ? false : resultIsError)

            if let mine {
                DevnetAccountRow(address: mine,
                                 title: String(localized: "This phone"),
                                 detail: mineDetail,
                                 watching: watch.isWatching(mine),
                                 tint: tint,
                                 isMine: true) { take(mine) }
            }

            if !examples.isEmpty {
                // The one head on the card. Its words carry the offer, so a
                // row underneath never has to repeat it.
                Text(String(localized: "Addresses worth watching"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
                ForEach(examples) { example in
                    DevnetAccountRow(address: example.address,
                                     title: example.title,
                                     detail: example.detail,
                                     watching: watch.isWatching(example.address),
                                     tint: tint) { take(example.address) }
                }
            }
        }
    }

    /// What the typed address resolves to, right now — the face costs nothing
    /// (an identicon is deterministic from the address, so this is the exact
    /// face the row will wear, drawn a second early).
    @ViewBuilder private var addressPreview: some View {
        if let address = previewAddress {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: address, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.name(for: address) ?? WalletStore.shortAddress(address))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(watch.isWatching(address) ? String(localized: "Already watching")
                                                   : String(localized: "New address"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .dsWell()
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    private func watchTyped() {
        let address = draft
        guard W.isValidAddress(address) else {
            result = String(localized: "That doesn't look like a devnet address — it needs to be 0x followed by 40 hex characters.")
            resultIsError = true
            return
        }
        DSHaptic.tap()
        guard watch.add(address) else {
            result = String(localized: "Already watching that address.")
            resultIsError = false
            typed = ""
            return
        }
        typed = ""
        result = nil
        register()
        onWatched(address)
    }

    private func take(_ address: String) {
        guard watch.add(address) else { return }
        result = nil
        register()
        onWatched(address)
    }
}

// MARK: - The roster

/// What you are already watching, with the door out.
///
/// **It stays on the setup screen for three of the four seats, and that is a
/// stated exception to §465 rather than an oversight.** That ruling puts what
/// you do REPEATEDLY in the room, which is why vibenet has no roster here —
/// its accounts live on the room's own face rail. Hegotá, Frames and Privacy
/// have no equivalent rail yet, so removing this would leave a pasted address
/// with nowhere at all to be unwatched: a §83 dead end, which is worse than an
/// inconsistency. When those rooms grow a rail this section leaves with it.
struct DevnetWatchingSection<W: DevnetWatchList>: View {
    let watch: W
    let register: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(watch.addresses.count == 1
                 ? String(localized: "Watching")
                 : String(localized: "Watching \(watch.addresses.count)"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            ForEach(watch.addresses, id: \.self) { address in
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(watch.name(for: address) ?? WalletStore.shortAddress(address))
                            .dsText(.callout15)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(WalletStore.shortAddress(address))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Button {
                        DSHaptic.selection()
                        watch.remove(address)
                        register()
                    } label: {
                        Text(String(localized: "Remove"))
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(DS.Motion.standard, value: watch.addresses)
    }
}

// MARK: - The explorer

/// The way off this screen and onto the chain's own explorer.
///
/// **A centred card row, the shape `BridgeDisconnectSection` already uses**
/// (user, 2026-09-04: *"the 'open the explorer' doesn't really seem like rest
/// of the style"*). It shipped as a `DSSlabDoor` — a full-width filled slab
/// with a leading title, a trailing host and a chevron — which is the grammar
/// of a door onto ANOTHER SCREEN IN THIS APP, sitting between an inset-grouped
/// card and a centred destructive row and matching neither.
///
/// It is also not that kind of door: it leaves the app entirely. The two rows
/// at the foot of these screens are both exits now, one neutral and one
/// destructive, in one shape.
///
/// The host is stated under the verb rather than beside it, because a door out
/// of the app must be checkable against the address bar it lands on — the
/// honesty rule §315's own door budget exists to keep.
struct DevnetExplorerRow: View {
    /// The chain's explorer. A browser door, never a fetch — every one of
    /// these hosts sits in `network-reach-audit.sh`'s denylist for exactly
    /// that reason, and the day one is fetched it belongs in `NetworkReach`
    /// instead.
    let url: String

    private var host: String {
        URL(string: url)?.host() ?? url
    }

    var body: some View {
        Section {
            Button {
                DSHaptic.selection()
                if let target = URL(string: url) {
                    UIApplication.shared.open(target)
                }
            } label: {
                VStack(spacing: 1) {
                    Text("Open the explorer")
                        .dsText(.body17)
                        .foregroundStyle(DS.tint)
                    Text(host)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsListCardRow()
        }
    }
}
