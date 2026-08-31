import SwiftUI

/// The vibenet address book (prd §465, 2026-08-24) — the accounts you
/// watch on Base's devnet, and every verb that manages them.
///
/// **Why this screen exists.** Reported: *"the set up screens need to feel
/// like they are only for set up."* `VibenetScreen` had become the connect
/// page AND the roster AND the rename/remove surface, which is the same
/// complaint §461 answered on the Wallet side, one seat over. The split
/// here is the ruling Alexander gave after it: **setup keeps what you do
/// once (the first address, the disconnect); the room keeps what you do
/// repeatedly.** So the roster moved here, one tap from the room it
/// describes — reachable from the vibenet face rail's book slot and from
/// the setup page's own door.
///
/// **What it deliberately does NOT copy from Wallet's WATCH tier.** Wallet's
/// screen has TWO tiers — five WATCHED addresses and an unlimited ledger of
/// NAMES — because on mainnet a watch costs a metered Zerion read on every
/// foreground and a name costs nothing. Vibenet reads a keyless devnet
/// RPC: watching is free, so there is no expensive tier to separate out.
/// One list, no cap counter, no "Everyone else" section, and no
/// `WalletStore.watchLimit` analog to state — a limit with no cost behind
/// it is a control that protects nothing (§83's shape).
///
/// **The NAMES ledger is shared** (2026-08-27, the address-book
/// unification). Every account named here lives in `AddressBook`, the same
/// store `AddressBookScreen` reads — a rename here shows up there (badged
/// "Vibenet") and survives disconnect, because naming is free and outlives
/// every watch. `VibenetWatch` still owns which addresses are WATCHED.
///
/// **The SCREEN is copied, never the type** (`AddressBookScreen`'s own
/// ruling): this room's roster (watched, uncapped, managed here) and the
/// wallet book's list (named, capped watch tier, managed there) are
/// different enough surfaces that parameterising one screen by source is how
/// the two start owing each other behaviour neither wants.
///
/// ---
///
/// **§517 (2026-08-29) rebuilt the page. Reported: *"it's not clear for
/// user where they are or what to do. and it's a lot of text in weird
/// places… presumably the watched accout would be at top… this whole thing
/// is gross and needs a redesign."*** Four things were wrong and they
/// compounded:
///
/// 1. **The page did not say where you were.** Its title was "Address
///    Book" — the name of a DIFFERENT screen it also links to — while its
///    subject is vibenet accounts. It is "Accounts" now, under a line
///    naming the network, and the full book is a row like any other.
/// 2. **The thing you watch was not at the top.** The paste field led,
///    then a demos link, then the discovery unfold — so on the reported
///    screen the user's own account sat below eight strangers'. Watched
///    accounts lead now, and nothing can displace them: the lookup moved
///    to `VibenetWatchSheet`.
/// 3. **Five type sizes in three positions.** The field's label rung, the
///    demos link, the discovery heading, each discovered row's two rungs,
///    the roster card's heading tier and the verb run's 12pt chips. What
///    is left is the ramp's ordinary row anatomy — `heading17` name,
///    `mono12` address, `subhead13` state — repeated.
/// 4. **Two quiet verbs spelled as floating blue text** ("Find another
///    account", "Full address book"), which §476 had already made one
///    pattern out of two. A tint text link *between* slabs belongs to
///    neither, so both are rows now and the one primary act is a real
///    button.
///
/// **INK, AND NO CARDS** (user ruling, 2026-08-29: *"make sure its ink
/// black not the grayish black you have and we don't use cards so i don't
/// think you need those around things"*). `dsInk()` — `DS.inkGround`, pure
/// black in dark — rather than the themed page, and the roster is rows on
/// that ground rather than a slab. Nothing draws a line either (§8's
/// no-hairlines law): the faces and the vertical rhythm do the separating.
/// The only filled shapes on the screen are two genuine controls.
struct VibenetAddressBookScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Bindable private var watch = VibenetWatch.shared

    /// **SEEDED FROM THE LAST SAVED READ, not from an empty room (prd §472).**
    ///
    /// It began as `VibenetRoom.compose(items: [], … configReached: false)`,
    /// and `VibenetRoom.headline` tests `configReached` FIRST — so the first
    /// frame of the screen built to be your roster read **"Couldn't read
    /// vibenet's current contracts"**, every open, before a single request
    /// had been made. §83's fake status, on frame one, on the one screen that
    /// exists to list what you watch.
    @State private var room: VibenetRoom
    @State private var loading = false
    /// An address watched (or unwatched) while a read is mid-flight
    /// requeues it — the `GeckoTerminal`/`Stocktwits` lesson, so the new
    /// address lands now rather than at the next visit.
    @State private var loadPending = false

    /// The naming alert — a text-entry alert needs `@State`, so it lives
    /// here rather than on the row it belongs to.
    @State private var renamingAddress: String?
    @State private var renameText = ""

    /// The lookup, which is a SHEET now rather than an unfold (§517).
    @State private var watching = false

    /// The address whose removal would take the whole seat with it — non-nil
    /// is what raises the confirm. See `unwatch`.
    @State private var removingLast: String?

    /// A row's tap opens the detail sheet, keyed by the address itself
    /// (`String` is `Identifiable`, the `L2beatScreen`/`WalletbeatScreen`
    /// shape).
    @State private var opened: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// `@MainActor` because `VibenetRoomSource.card()` is — it consults
    /// `DemoMode`. Every construction of this screen is from a `View` body,
    /// which is already main-actor, so the annotation costs nothing.
    @MainActor
    init() {
        _room = State(initialValue: VibenetRoomSource.card()
            ?? VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false))
    }

    private var connected: Bool { watch.connected }

    /// The watched accounts, in the room's own order. Seeded rows only —
    /// the room is the single source for what an account's state IS, so a
    /// row never computes one of its own.
    private var accounts: [VibenetAccountItem] { room.items }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                subjectLine

                if connected {
                    rosterSection
                    watchButton
                }

                doorsSection

                if connected { provenanceLine }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, ShellMetrics.bottomInset)
        }
        // A PULL RE-READS (prd §472). This screen is nothing but a live read
        // of a devnet, and its only read was `onAppear` — so a lock that
        // opened, a key that was revoked or a balance that moved while you sat
        // here needed you to leave the screen and come back.
        .refreshable { await load() }
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        // INK, not the themed page (§517, user ruling). `DS.inkGround` is the
        // absolute floor of the theme — pure black in dark — and this screen
        // is a list of faces on a ground, not a page of cards.
        .dsInk()
        .dsSoftScrollEdges()
        .dsScreenTitle("Accounts")
        .toolbar {
            // THE ONE PRIMARY ACTION, in the one place iOS puts a primary
            // action on a list screen. It duplicates the button below on
            // purpose: the button is what somebody standing in an empty
            // roster will find, the toolbar item is what somebody scrolled
            // to the bottom of a long one will reach for.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    DSHaptic.selection()
                    watching = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text("Watch an account"))
                }
            }
        }
        .sheet(isPresented: $watching) {
            VibenetWatchSheet(onWatched: { Task { await load() } })
        }
        .sheet(item: $opened) { address in
            VibenetAccountSheet(address: address, room: room, onRemove: unwatch)
        }
        .confirmationDialog(
            String(localized: "Stop watching your last account?"),
            isPresented: Binding(get: { removingLast != nil },
                                 set: { if !$0 { removingLast = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Stop watching"), role: .destructive) {
                if let address = removingLast { commitUnwatch(address) }
                removingLast = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { removingLast = nil }
        } message: {
            // What actually happens, in the words of the things it happens to
            // — never "this cannot be undone", which is true of most taps and
            // tells you nothing about this one.
            Text(String(localized: "It's the only account you watch, so vibenet disconnects: the chip leaves the source strip, and the address leaves your Address book unless it's also a named account on another network."))
        }
        .alert(
            String(localized: "Name this account"),
            isPresented: Binding(
                get: { renamingAddress != nil },
                set: { if !$0 { renamingAddress = nil } })
        ) {
            TextField(String(localized: "Name"), text: $renameText)
            Button(String(localized: "Save")) {
                if let address = renamingAddress { watch.setName(renameText, for: address) }
                renamingAddress = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { renamingAddress = nil }
        }
        .onAppear {
            if connected { Task { await load() } }
        }
    }

    // MARK: - Pieces

    /// **WHERE YOU ARE, in one line under the title (§517).** The screen is
    /// called "Accounts" and this says whose. Without it the title is
    /// ambiguous with the wallet's own accounts one tap away, and with the
    /// old "Address Book" title it named a different screen entirely.
    private var subjectLine: some View {
        HStack(spacing: DS.Space.s1 + 2) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Self.mark)
                .frame(width: 13, height: 13)
            Text("Base Vibenet devnet")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.bottom, DS.Space.s6)
    }

    /// **WHAT YOU WATCH, FIRST — and on the ink, not in a card.**
    ///
    /// The roster used to be `VibenetRoomCard`'s managing mode, which is a
    /// slab carrying its own headline tier. Here the rows ARE the content,
    /// so there is nothing for a card to be a card around; the room's
    /// headline would only restate the row it sits above.
    @ViewBuilder
    private var rosterSection: some View {
        // Withheld on the FIRST-EVER open, where there is no snapshot to seed
        // from, rather than drawn over an empty room — the same false failure
        // §472 closed by seeding at all.
        if !accounts.isEmpty || !loading {
            VStack(alignment: .leading, spacing: 0) {
                Text("Watching")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.bottom, DS.Space.s1)

                ForEach(accounts, id: \.address) { item in
                    accountRow(item)
                }
            }
            .padding(.bottom, DS.Space.s4)
        }
    }

    /// One account. The ramp's ordinary row anatomy and nothing else:
    /// `heading17` name, `mono12` address, `subhead13` state.
    ///
    /// The STATE line is `VibenetRoom.rowLine`, the room's own sentence, so
    /// a row can never disagree with the sheet it opens. Its tone is the
    /// one thing added here — a row that says "Not deployed yet" in the
    /// same grey as "3 keys" makes the two look like the same kind of fact.
    private func accountRow(_ item: VibenetAccountItem) -> some View {
        Button {
            DSHaptic.selection()
            opened = item.address
        } label: {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: item.address, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.name(for: item.address) ?? VibenetRoom.shortAddress(item.address))
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(VibenetRoom.shortAddress(item.address))
                        .dsText(.mono12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stateTone(item))
                            .frame(width: 7, height: 7)
                        Text(VibenetRoom.rowLine(item))
                            .dsText(.subhead13)
                            .foregroundStyle(stateWords(item))
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(12, weight: .semibold)
                    .foregroundStyle(DS.textTertiary.opacity(0.6))
            }
            .padding(.vertical, DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .contextMenu {
            Button {
                renameText = watch.name(for: item.address) ?? ""
                renamingAddress = item.address
            } label: {
                Label(String(localized: "Name this account"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                unwatch(item.address)
            } label: {
                Label(String(localized: "Stop watching"), systemImage: "minus.circle")
            }
        }
    }

    /// The dot. Three states worth telling apart at a glance, and a fourth
    /// that must NOT wear a colour: an unreached account is not a state of
    /// the account, it is a state of our reading (§83).
    private func stateTone(_ item: VibenetAccountItem) -> Color {
        guard item.reached else { return DS.textTertiary }
        if item.locked { return DS.attention }
        return item.established ? DS.confirm : DS.attention
    }

    /// The words. Only the two that are ASKING something of you take the
    /// tone — the rest is ordinary secondary text, or every row shouts.
    private func stateWords(_ item: VibenetAccountItem) -> Color {
        guard item.reached else { return DS.textTertiary }
        if item.locked { return DS.attention }
        return item.established ? DS.textSecondary : DS.attention
    }

    /// **ONE PRIMARY ACTION, and it opens a sheet rather than unfolding
    /// here (§517).** A control, not a card: the tint fill is what says
    /// "pressable", the same capsule vocabulary the rest of the app uses.
    private var watchButton: some View {
        Button {
            DSHaptic.selection()
            watching = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
                    .dsGlyph(14, weight: .semibold)
                Text("Watch another account")
                    .dsText(.callout15).fontWeight(.semibold)
            }
            .foregroundStyle(DS.tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DS.tintDim,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .padding(.bottom, DS.Space.s6)
    }

    /// **THE TWO QUIET DOORS, AS ROWS (§517).**
    ///
    /// §476 already ruled that this screen must have ONE way of saying
    /// "here is something else you can do" rather than two, and made both
    /// of these tint text links. That was right about the count and wrong
    /// about the shape: a bare tint sentence floating between sections
    /// belongs to neither of them, which is precisely what the report
    /// called text in weird places. They are rows on the same ground as
    /// everything else now — one pattern, and one that reads as a
    /// destination.
    private var doorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ONE BOOK, WALKABLE FROM EITHER ROOM (2026-08-27, the
            // address-book unification). Every account named here is a row
            // in the same `AddressBook` the wallet manager reads.
            Button {
                DSHaptic.selection()
                route.push(.addressBook)
            } label: {
                doorRow(String(localized: "Full Address book"),
                        glyph: "chevron.right", tinted: false)
            }
            .buttonStyle(PressSpring())
            .dsHover()

            // A door to Base's own demo, not a paragraph about it.
            Link(destination: URL(string: "https://chain.base.org/demos/account")!) {
                doorRow(String(localized: "Base Vibenet demos"),
                        glyph: "arrow.up.right", tinted: true)
            }
            .buttonStyle(PressSpring())
            .dsHover()
        }
    }

    private func doorRow(_ title: String, glyph: String, tinted: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(title)
                .dsText(.callout15)
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Image(systemName: glyph)
                .accessibilityHidden(true)
                .dsGlyph(12, weight: .semibold)
                .foregroundStyle(tinted ? DS.tint : DS.textTertiary.opacity(0.6))
        }
        .padding(.vertical, DS.Space.s3)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// When this was read, and the standing promise. The room's own
    /// provenance line (§468) — kept, because it is the one sentence on the
    /// screen that is about the READ rather than about an account, and
    /// without it a stale roster wears a confident face.
    @ViewBuilder
    private var provenanceLine: some View {
        if let note = VibenetRoom.note(room, drawn: accounts.count) {
            Text(note)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s6)
        }
    }

    // MARK: - Actions

    /// Removing the LAST watched account disconnects the seat, so the chip
    /// goes with it — a connected seat holding no addresses is a room that
    /// can never say anything. `VibenetScreen` relies on this too: it is
    /// the only teardown besides the explicit Disconnect.
    ///
    /// **AND THAT IS WHY THE LAST ONE ASKS (prd §472).** Every other unwatch
    /// removes a row; this one tears down the seat, drops the chip out of the
    /// source strip, forgets the room snapshot and the seen-keys ledger, and
    /// leaves the person on a screen whose subject has just ceased to exist —
    /// all from one tap of a context-menu item sitting where "remove this row"
    /// sat a moment ago. The ordinary case is untouched and stays immediate:
    /// a confirm on every removal would be the dialog nobody reads.
    private func unwatch(_ address: String) {
        guard watch.addresses.count > 1 else {
            removingLast = address
            return
        }
        commitUnwatch(address)
    }

    /// The removal itself, past whatever asking was owed.
    private func commitUnwatch(_ address: String) {
        DSHaptic.tap()
        watch.remove(address)
        if watch.connected {
            VibenetBridge.registerBridge(store: store)
            Task { await load() }
        } else {
            VibenetBridge.disconnect(store: store)
            room = VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
        }
    }

    /// Reads every watched address and composes the card; the seat's proof
    /// line carries the count.
    private func load() async {
        if loading { loadPending = true; return }
        loading = true
        defer { loading = false }
        repeat {
            loadPending = false
            let composed = await VibenetRoomSource.compose()
            room = composed
            guard watch.connected else { return }
            VibenetBridge.registerBridge(store: store)
        } while loadPending && watch.connected
    }
}
