import SwiftUI

/// The Walletbeat room's head (prd §419).
///
/// Composed through `DSRoomChassis.Head` (prd §745): the wallets are
/// `MarkedRow`s — the shape L2BEAT's chains share — and the directory door is
/// the template's `HeadLink`.
///
/// HOLDS NO `Thing`. The tap hands back a `sourceRef` and the section that owns the sheet
/// does the lookup against the live corpus (corollary 5).
struct WalletbeatRoomCard: View {
	let room: WalletbeatRoom
	/// The room's kind tiles (prd §816), drawn in the head's `scopes` slot —
	/// the Privy pattern. Nil, or fewer than two kinds, draws the head alone.
	var tiles: DSScopeTiles<RoomKindTile>? = nil
	var onOpen: (String) -> Void
	var onBrowse: () -> Void

	var body: some View {
		DSRoomChassis.Head(
			lead: .sentence(WalletbeatRoom.headline(room)),
			notes: [.note(WalletbeatRoom.note(room))],
			footnotes: [.quiet(WalletbeatRoom.coverageNote(room))],
			tiles: tiles) {
			if !room.items.isEmpty {
				DSRoomChassis.Block {
					DSRoomChassis.Rows(items: room.items) { index, item in
						DSRoomChassis.MarkedRow(
							name: item.name,
							// An unresolved incident is the one thing that outranks the
							// rating, so it is said in words on the row.
							flag: item.openIncidents > 0 ? String(localized: "Unresolved") : nil,
							line: WalletbeatRoom.leadLine(item),
							index: index,
							action: { onOpen(item.id) }) {
							WalletbeatMark(name: item.name, walletID: item.walletID, size: DS.Mark.row)
						} trailing: {
							WalletbeatShape(counts: item.counts)
						}
					}
				}
			}

			// The label is the VERB the tier is missing (prd §421), and it NAMES the
			// wallet when the app already knows which one you use (prd §430). Every word
			// of it lives in `WalletbeatRoom`, where the harness compiles it.
			DSRoomChassis.Block {
				DSRoomChassis.HeadLink(title: WalletbeatRoom.browseLabel(room), action: onBrowse)
			}
		}
	}
}
