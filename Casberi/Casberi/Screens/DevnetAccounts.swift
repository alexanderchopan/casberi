import SwiftUI
import SwiftData

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
/// this is one control appearing four times. (The second reason this said —
/// that four screen files keep four `BridgeSetupHeader` calls where
/// `setup-copy-audit.py` can see them — went with §639: the four seats are on
/// `AccountPage`, which has no header call to audit and takes the intro as a
/// parameter. The first reason is the one that was load-bearing anyway.)
///
/// **ALL FOUR ARE ON `AccountPage` SINCE §639 (2026-09-06.)** The card is
/// gone, the roster is the chassis's "Watching · N" — one list, one verb,
/// "Remove" — and the field is the page's one bar, which filters that roster
/// as well as adding to it. `DevnetWatchingSection` went with the move: it
/// existed because three of the four seats had nowhere else to unwatch an
/// address, which is the dead end the chassis's roster now closes for all
/// four. That is a stated amendment to §465 ("setup keeps what you do ONCE"):
/// there is no setup screen any more to keep it out of.
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

// MARK: - What is there right now

/// The two facts a devnet node will state about any address for free —
/// how many times it has sent, and what it holds — read once per row and
/// shown UNDER the example's claim (prd §618, 2026-09-05).
///
/// **Why a live line under a dated claim.** `DevnetExample`'s copy says what
/// an address SHOWED when it was measured, and the sentence under every one of
/// these slabs says the chain may be reset without notice — so the claim is
/// honest and can still be stale. This line is the part that cannot be: it is
/// what the node says now. Where it lands it replaces the dated detail; where
/// the node cannot be reached the dated detail stands, past tense and all.
///
/// Two sequential calls rather than a batch because the four RPC helpers
/// share a signature and none of them shares a batch, and the point of this
/// type is to be handed any of them.
struct DevnetPeek: Equatable {
    /// The address's nonce — a count of what it SENT, never what it received.
    let sends: Int
    /// `eth_getBalance`, raw hex. Nil where the node answered the nonce but
    /// not the balance.
    let balanceWeiHex: String?

    var line: String {
        // A balance that ROUNDS TO ZERO is not a balance (§83's own
        // corollary: a figure that rounds to nothing makes no claim). At
        // three places a dust holding renders "0.000 test ETH", which reads
        // as a stated amount and is worse than saying nothing — so a
        // rendering with no non-zero digit is dropped rather than shown.
        let held: String? = balanceWeiHex
            .flatMap { FramesMoney.eth(fromWeiHex: $0, places: 3) }
            .flatMap { text in
                text.contains(where: { $0 != "0" && $0.isNumber }) ? text : nil
            }
            .map { String(localized: "\($0) test ETH") }
        let sent: String
        switch sends {
        case 0:  sent = held == nil ? String(localized: "Nothing here right now")
                                    : String(localized: "Nothing sent yet")
        case 1:  sent = String(localized: "1 send")
        default: sent = String(localized: "\(sends) sends")
        }
        guard let held else { return sent }
        return "\(sent) · \(held)"
    }

    /// One read, through whichever seat's RPC helper is handed in. Nil when
    /// the nonce did not come back — a balance alone is not a reading.
    static func read(_ address: String,
                     via call: (String, [Any]) async -> Any?) async -> DevnetPeek? {
        guard !DemoMode.isActive else { return nil }
        guard let hex = await call("eth_getTransactionCount", [address, "latest"]) as? String,
              let sends = Int(hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex, radix: 16)
        else { return nil }
        let balance = await call("eth_getBalance", [address, "latest"]) as? String
        return DevnetPeek(sends: sends, balanceWeiHex: balance)
    }
}

// MARK: - The read after a watch

/// What happens between "watched" and "the room has something": one read,
/// started the moment an address lands, reported on the screen the person is
/// still looking at (prd §618, 2026-09-05).
///
/// **The three jumping screens had nowhere to report it.** Hegotá, Frames and
/// Privacy routed into the room on the first watch, and their rooms read for
/// themselves on appear — which meant the common path was: tap Watch, land in
/// an empty room, wait, with nothing saying a read was in flight. Vibenet had
/// already solved this (2026-08-28: connecting is picking several, the
/// `RoomDoor` is the only way on) and carried the read state in its own
/// screen; this type is that mechanism lifted out so all four seats share it,
/// and so the slab and a second section (vibenet's discovery list) can drive
/// the same read.
///
/// Coalescing rather than queueing: a second watch during a read marks it
/// pending and the loop runs once more when the current one lands, so five
/// taps cost two reads, not five.
@MainActor
@Observable
final class DevnetReader {
    /// The seat's display name, for the two sentences this type owns.
    let name: String
    /// The seat's own read. Returns whether the chain was REACHED — a read
    /// that landed nothing is still a read; only unreachable is a failure.
    private let read: @MainActor () async -> Bool

    private(set) var reading = false
    private(set) var unreachable = false
    private var pending = false

    init(name: String, read: @escaping @MainActor () async -> Bool) {
        self.name = name
        self.read = read
    }

    var line: String { String(localized: "Reading \(name)…") }

    /// Nil while nothing is wrong. The failure sentence names what is still
    /// true (the addresses are watched) before what is not, because the
    /// person's act succeeded and only the network's did not.
    var proof: BridgeProof? {
        unreachable
            ? .failed(String(localized: "Couldn't reach \(name) just now. Your addresses are watched — the room fills in as soon as a read lands."))
            : nil
    }

    func kick() {
        if reading { pending = true; return }
        reading = true
        Task {
            defer { reading = false }
            repeat {
                pending = false
                unreachable = !(await read())
            } while pending
        }
    }
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

// MARK: - The act block

/// **Paste at the top, examples under it — the account page's act slot (prd
/// §639, 2026-09-06).**
///
/// It was `DevnetAccountsSlab` and it was a card. The four devnet seats moved
/// onto `AccountPage`, where the only filled element on the page is the input
/// field, so the card is gone and the rows sit on the page's own ground. What
/// did NOT change is the order the 2026-09-04 ruling fixed — the field first,
/// the worked examples under it — or the reasoning behind every line below.
///
/// **The field is the page's ONE BAR (§639 amendment), so its text is the
/// screen's.** It adds an address and it filters the roster underneath, which
/// is why `typed` is a binding rather than local state: the chassis reads the
/// same string to answer the same keystrokes. A partial address is a filter; a
/// whole one arms the verb.
///
/// Generic over the seat's watch list so the rows read the real one — see the
/// file header on why that is a protocol rather than a closure bag.
///
/// The status line lives here rather than at the call site because all four
/// seats had written their own version of the same three sentences (a
/// malformed address, a duplicate, and — on vibenet — a chain that could not
/// be reached), and three of the four disagreed on the wording of the first
/// two.
struct DevnetAccountsAct<W: DevnetWatchList>: View {
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
    /// The seat's RPC, for the live line under each row (`DevnetPeek`). Nil
    /// draws the dated claims alone.
    var peek: ((String) async -> DevnetPeek?)? = nil
    /// The read that follows a watch, and the two lines it can show under the
    /// field. Owned by the SCREEN (an `@State`), so a second section on the
    /// same screen can kick the same read.
    var reader: DevnetReader? = nil
    /// Register the seat. Done HERE, in the control, not left to each
    /// embedder: four screens draw this list and a seat that forgot to
    /// register reads perfectly right up until the catalog disagrees with it.
    let register: () -> Void
    /// The page's one bar. Owned by the SCREEN so the roster below filters on
    /// the same keystrokes that would add an address (§639 amendment).
    @Binding var typed: String
    /// Fires only after an address really landed — never after a duplicate or
    /// a rejected paste. Optional since §618: the act block reads for itself
    /// now, and no seat routes on a watch any more.
    var onWatched: (String) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var result: BridgeProof?
    /// What the node said about each address it has been asked about, keyed
    /// lowercase. Read once per address per mount; a row never re-asks.
    @State private var facts: [String: DevnetPeek] = [:]

    private var draft: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the preview is about, or nil while the field holds nothing
    /// that is already one. RESOLVING is still a plain validity check and
    /// never a lookup — none of these chains has a name registrar.
    ///
    /// **What §618 changed, and what it did not.** This doc used to add "a
    /// live read fired per keystroke would be a claim about an account nobody
    /// has agreed to watch yet", and one read now does fire here. The rule it
    /// was protecting holds: nothing is read PER KEYSTROKE, because this
    /// property is nil until 42 characters make a whole address, so the read
    /// happens once, on a complete address the person has typed on purpose.
    /// It asks the seat's own RPC — the host the rows below already ask and
    /// the one `NetworkReach` declares for this seat — for two public facts,
    /// and it is what turns "New address" into "3 sends · 0.5 test ETH", so
    /// a wrong paste is visible BEFORE it is watched rather than after.
    private var previewAddress: String? {
        W.isValidAddress(draft) ? draft : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSlabField(placeholder: placeholder,
                        text: $typed,
                        actionLabel: String(localized: "Watch"),
                        focus: $focused,
                        isArmed: previewAddress != nil,
                        // The paste FILLS the field; the preview and the
                        // armed verb then do exactly what they do for a
                        // typed address. A clipboard that is not an address
                        // gets the same sentence a typed one would.
                        paste: { pasted in
                            typed = pasted
                            result = W.isValidAddress(pasted) ? nil : malformed
                        },
                        action: watchTyped)

            addressPreview
                .animation(DS.Motion.standard, value: previewAddress)

            BridgeSyncStatusRows(
                syncing: reader?.reading ?? false,
                syncingLine: reader?.line ?? "",
                proof: result ?? reader?.proof)

            if let mine {
                DevnetAccountRow(address: mine,
                                 title: String(localized: "This phone"),
                                 detail: [mineDetail, fact(for: mine)]
                                    .compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: " · "),
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
                    // The live line replaces the dated claim once it lands;
                    // until then, and where the node cannot be reached, the
                    // claim stands (it is written in the past tense for
                    // exactly this — see `DevnetExample`).
                    DevnetAccountRow(address: example.address,
                                     title: example.title,
                                     detail: fact(for: example.address) ?? example.detail,
                                     watching: watch.isWatching(example.address),
                                     tint: tint) { take(example.address) }
                }
            }
        }
        .task { await peekRows() }
        .task(id: previewAddress) {
            guard let address = previewAddress else { return }
            await peekOne(address)
        }
    }

    /// Not connected the field is the connect form and says what to paste.
    /// Connected it is the add verb AND the roster's filter, and the words
    /// have to say both (§639 amendment) — a person with nine watched
    /// addresses types to find one at least as often as to add one.
    private var placeholder: String {
        watch.addresses.isEmpty
            ? String(localized: "0x… devnet address")
            : AccountPageShape.findPlaceholder(String(localized: "an address"))
    }

    private var malformed: BridgeProof {
        .failed(String(localized: "That doesn't look like a devnet address — it needs to be 0x followed by 40 hex characters."))
    }

    private func fact(for address: String) -> String? {
        facts[address.lowercased()]?.line
    }

    /// One read per row, all rows at once. Each lands on its own so the
    /// first answer draws while the rest are still out. The reads run as
    /// children; the `@State` write happens here, on the task's own actor.
    private func peekRows() async {
        guard let peek else { return }
        let rows = (mine.map { [$0] } ?? []) + examples.map(\.address)
        await withTaskGroup(of: (String, DevnetPeek?).self) { group in
            for address in rows where facts[address.lowercased()] == nil {
                group.addTask { (address, await peek(address)) }
            }
            for await (address, read) in group {
                if let read { facts[address.lowercased()] = read }
            }
        }
    }

    private func peekOne(_ address: String) async {
        guard let peek, facts[address.lowercased()] == nil,
              let read = await peek(address) else { return }
        facts[address.lowercased()] = read
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
                                                   : (fact(for: address) ?? String(localized: "New address")))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s2)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    private func watchTyped() {
        let address = draft
        guard W.isValidAddress(address) else {
            result = malformed
            return
        }
        DSHaptic.tap()
        guard watch.add(address) else {
            result = .says(String(localized: "Already watching that address."))
            typed = ""
            return
        }
        typed = ""
        landed(address)
    }

    private func take(_ address: String) {
        guard watch.add(address) else { return }
        landed(address)
    }

    /// One place for what follows a watch: register the seat, start the read
    /// the person can see, tell the screen. No routing — since §618 the
    /// `RoomDoor` above is the only way on for every seat, so a second tap
    /// can never yank the list out from under the thumb still using it.
    private func landed(_ address: String) {
        result = nil
        register()
        reader?.kick()
        onWatched(address)
    }
}

// MARK: - The roster's facts

/// What the chassis's "Watching · N" says about each address (prd §639).
///
/// `DevnetWatchingSection` drew this list itself, in a card, with its own
/// Remove button — three of the four seats carried it because they had nowhere
/// else to unwatch an address. The list is the account page's now, so what is
/// left is the part only this family knows: the SUBLINE. On a chain the app
/// stamps per-address rows for (vibenet) that is a week count like every other
/// seat's; on the three that do not it is what the node says right now — "3
/// sends · 0.5 test ETH" — because a row reading "quiet this week" about a
/// chain we never attribute rows on would be a claim we cannot make.
///
/// One read per address per visit, kicked from the screen's `onAppear` and
/// again when the watch list changes.
@MainActor
@Observable
final class DevnetRosterReader {
    let seatID: String
    let source: String
    private(set) var rows: [AccountPageShape.Row] = []
    private var facts: [String: DevnetPeek] = [:]

    init(seatID: String, source: String) {
        self.seatID = seatID
        self.source = source
    }

    /// Rebuild the rows, then fill in the live lines as the node answers.
    /// Ordered as the watch list is ordered — the person's own order.
    func refresh<W: DevnetWatchList>(watch: W, context: ModelContext,
                                     peek: ((String) async -> DevnetPeek?)?) async {
        let addresses = watch.addresses
        compose(watch: watch, weekly: weekly(context: context))
        guard let peek else { return }
        await withTaskGroup(of: (String, DevnetPeek?).self) { group in
            for address in addresses where facts[address.lowercased()] == nil {
                group.addTask { (address, await peek(address)) }
            }
            for await (address, read) in group {
                if let read { facts[address.lowercased()] = read }
            }
        }
        compose(watch: watch, weekly: weekly(context: context))
    }

    /// This week's rows per address, from the corpus. Empty on the three seats
    /// that land rows without an `authorHandle` — see the type's own doc.
    private func weekly(context: ModelContext) -> [String: (week: Int, new: Bool)] {
        let source = self.source
        let weekStart = Date.now.addingTimeInterval(-7 * 86_400)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.capturedAt >= weekStart })
        descriptor.fetchLimit = 2000
        let things = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        let lastLooked = AccountVisits.lastLooked(seatID)
        var book: [String: (week: Int, new: Bool)] = [:]
        for thing in things {
            guard let handle = thing.authorHandle?.lowercased(), !handle.isEmpty else { continue }
            let was = book[handle] ?? (0, false)
            book[handle] = (was.week + 1, was.new || (lastLooked.map { thing.capturedAt > $0 } ?? false))
        }
        return book
    }

    private func compose<W: DevnetWatchList>(watch: W, weekly: [String: (week: Int, new: Bool)]) {
        rows = watch.addresses.map { address in
            let key = address.lowercased()
            let counted = weekly[key]
            // The count where the seat stamps one, the node's own line where
            // it does not, and the address itself where neither answered.
            let subline: String
            if let counted {
                subline = AccountPageShape.subline(nouns: String(localized: "rows"),
                                                   weekCount: counted.week)
            } else {
                subline = facts[key]?.line ?? WalletStore.shortAddress(address)
            }
            return AccountPageShape.Row(
                id: address,
                title: watch.name(for: address) ?? WalletStore.shortAddress(address),
                subline: subline,
                weekCount: counted?.week ?? 0,
                hasNew: counted?.new ?? false,
                isYou: false,
                avatarURL: nil)
        }
    }

    /// Drop what the node said about an address that is no longer watched, so
    /// re-watching it reads fresh rather than replaying a stale line.
    func forget(_ address: String) {
        facts.removeValue(forKey: address.lowercased())
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
    /// PLAIN on the account page (prd §639), the way `BridgeDisconnectSection`
    /// is: the same verb and the same host line, left-aligned on the page's own
    /// ground instead of centred in a card, because the page has no cards.
    var plain = false

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
                VStack(alignment: plain ? .leading : .center, spacing: 1) {
                    Text("Open the explorer")
                        .dsText(.body17)
                        .foregroundStyle(DS.tint)
                    Text(host)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: plain ? .leading : .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(ExplorerGround(plain: plain))
        }
    }
}

/// The card row everywhere but the account page, where the row is the page.
private struct ExplorerGround: ViewModifier {
    let plain: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if plain {
            content
                .frame(minHeight: 56)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            content.dsListCardRow()
        }
    }
}
