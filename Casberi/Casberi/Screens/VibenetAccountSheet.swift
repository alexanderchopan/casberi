import SwiftUI

/// R3.2 (2026-08-23) — the account detail SHEET, replacing the card's old
/// expand-in-place block. `.sheet(item:)` on `VibenetScreen`, keyed by the
/// address itself (`String` is `Identifiable` — the same shape
/// `L2beatScreen`/`WalletbeatScreen` use for a chain/wallet id, no wrapper
/// type needed).
///
/// R4.7 (2026-08-23) shrank this to a shell: the actual content (hero,
/// keys, history, sync, doors) moved to `VibenetAccountDetail`, which
/// `VibenetRoomCard` now draws INLINE the moment the room narrows to one
/// account — reported: *"everything a user needs to see about this
/// account should be present on this screen, not on some other
/// screen."* This sheet still exists for "All", where several accounts
/// share the screen and only a room card's one-line-each summary fits;
/// what it presents is the identical view, so the two can never disagree.
///
/// VALUE TYPES ONLY. `room` is a `VibenetRoom` struct, not a `Thing` —
/// nothing here is SwiftData, so none of the six liveness corollaries in
/// CLAUDE.md apply. What DOES apply is the shape of the problem they solve:
/// `room` can go stale while the sheet is open (a foreground refresh
/// re-composes it, or the address gets unwatched from the row's own
/// context menu). `item` is recomputed from the LATEST `room` every body
/// pass, and if the address is no longer in it, the sheet shows nothing
/// and dismisses itself rather than rendering a frozen, wrong account.
struct VibenetAccountSheet: View {
    let address: String
    let room: VibenetRoom
    var onRemove: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    /// The rename alert lives HERE, not delegated to the presenting
    /// screen — an `.alert` attached to a view BEHIND an active sheet
    /// never shows (the sheet covers it), so the screen's own alert (for
    /// the card's context menu) can't double as this one. No separate
    /// target to track: this sheet is always about `address`.
    @State private var renaming = false
    @State private var renameText = ""

    /// The key whose sheet is up (prd §478 — a key's depth is a
    /// presentation, never a row growing in place). A local wrapper rather
    /// than making `VibenetActor` `Identifiable` in the model: identity here
    /// is presentation state, and the account-qualified id is
    /// `VibenetKeySeenDiff.keyID`'s own reasoning — an actorId is unique
    /// within an account, not across them.
    private struct PresentedKey: Identifiable {
        let actor: VibenetActor
        let item: VibenetAccountItem
        var id: String { VibenetKeySeenDiff.keyID(address: item.address, actorId: actor.actorId) }
    }
    @State private var openedKey: PresentedKey?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private var item: VibenetAccountItem? { room.items.first { $0.address == address } }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ScrollView {
                        // The same content `VibenetRoomCard` draws inline
                        // once the room narrows to this one account — see
                        // `VibenetAccountDetail`'s own doc for why this
                        // sheet still exists (2026-08-23): it's still the
                        // way in from "All", where several accounts are on
                        // screen and only one line each fits.
                        // `room` here is ALWAYS the full, unscoped watch
                        // list (see this file's own doc — the sheet
                        // deliberately bypasses the rail's scope), so
                        // `VibenetAccountMapping.links` can see every
                        // watched-to-watched relationship this account
                        // takes part in, not just the ones inside
                        // whatever the rail currently narrows to.
                        VibenetAccountDetail(
                            item: item,
                            links: VibenetAccountMapping.links(room.items),
                            sharedKeys: VibenetKeyReuse.sharing(item, in: room.items),
                            onOpenKey: { openedKey = PresentedKey(actor: $0, item: item) })
                            .padding(DS.Space.s4)
                    }
                    .dsPageBackground()
                    .dsSoftScrollEdges()
                } else {
                    // The address vanished from `room` (unwatched, or a
                    // re-compose that dropped it) — dismiss rather than
                    // show a frozen or empty account. `Color.clear` gives
                    // `onAppear` something to fire from with no flash of
                    // empty content.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .navigationTitle(item.map { VibenetWatch.shared.name(for: $0.address) ?? VibenetRoom.shortAddress($0.address) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                if item != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                renameText = VibenetWatch.shared.name(for: address) ?? ""
                                renaming = true
                            } label: {
                                Label(String(localized: "Name this account…"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onRemove(address)
                                dismiss()
                            } label: {
                                Label(String(localized: "Stop watching"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            // This sheet is its own presentation host, so a nested sheet
            // presents cleanly — the half-open-then-close class is about a
            // `.sheet` on a List ROW resolving to the screen's controller,
            // which this is not.
            .sheet(item: $openedKey) { key in
                VibenetKeySheet(actor: key.actor, item: key.item,
                                sharedKeys: VibenetKeyReuse.sharing(key.item, in: room.items))
            }
            .alert(String(localized: "Name this account"), isPresented: $renaming) {
                TextField(String(localized: "Name"), text: $renameText)
                Button(String(localized: "Save")) {
                    VibenetWatch.shared.setName(renameText, for: address)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
        .dsPageSheet()
    }
}
