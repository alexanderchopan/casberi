import SwiftUI

/// **THE ACCOUNTS CROWN IS THE ACCOUNTS YOU FOLLOW, FACE BY FACE (prd §941).**
///
/// §940 drew a bar per address tied to yours, and the user named what it
/// was: *"just a line w/ a number repeating stuff that is elsewhere"*. The
/// list under it already says who each account is tied to, in words, so the
/// crown does not draw relationships at all — a cluster view was mocked and
/// declined (*"it's like it is trying too hard"*). What the screen lacked was
/// the COUNT of your accounts, and a face for each.
///
/// **A face is the account picker too.** Tapping one scopes the room to that
/// account, the same `walletScope` the account menu under the tiles writes,
/// so the two can never disagree: pick from the menu and the face lights, tap
/// the face and the menu reads its name. A second tap goes back to all.
struct RoomAccountsFaces: View {
    struct Face: Identifiable, Equatable {
        /// The stored address — the scope's own key.
        let id: String
        let name: String
    }

    let faces: [Face]
    let selected: String?
    var onPick: (String?) -> Void

    /// Five across fits the box at the face size a roster of PEOPLE wants;
    /// past ten they step down and drop their names, which the list still says.
    private var roomy: Bool { faces.count <= 10 }
    private var size: CGFloat { roomy ? 56 : 40 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSFigureReading(number: String(faces.count),
                            caption: faces.count == 1 ? String(localized: "account")
                                                      : String(localized: "accounts"))
            // Centred in what is left of the fixed box (a thin roster must
            // not hang from the reading).
            Spacer(minLength: DS.Space.s3)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2),
                                     count: roomy ? 5 : 6),
                      spacing: DS.Space.s3) {
                ForEach(faces) { face in
                    button(face)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(DS.Motion.standard, value: selected)
    }

    private func isLit(_ face: Face) -> Bool {
        selected.map { WalletWatch.sameAddress($0, face.id) } ?? false
    }

    private func button(_ face: Face) -> some View {
        let lit = isLit(face)
        return Button {
            DSHaptic.selection()
            onPick(lit ? nil : face.id)
        } label: {
            VStack(spacing: DS.Space.s1) {
                WalletFace(address: face.id, size: size, circular: true)
                if roomy {
                    Text(face.name)
                        .dsText(.label12)
                        .foregroundStyle(lit ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            // One lit, the rest quiet — the treemap's press (prd §939).
            .opacity(selected != nil && !lit ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(face.name))
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
