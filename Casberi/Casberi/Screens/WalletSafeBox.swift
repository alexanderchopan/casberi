import SwiftUI

/// **THE SAFE PICK'S BOX (prd §1614).** Your account is a Safe, so the pick
/// answers "who can move this money, and what waits on me?". At rest: the
/// money across them, then one line per Safe — its name, who signs it, its
/// owners as faces (yours in the pick's ink), how many must sign. When a
/// transaction waits on your signature the box becomes the queue: the count
/// in the pick's ink, what your signature does, each transaction named by
/// what it does, then Review and sign, which opens the sign block (§1249);
/// nothing signs from the box.
///
/// Replaces the treemap the pick drew (§1069), which never said "Safe".
struct WalletSafeBox: View {
    /// Composed in `.task`, never in a body: the queue and the configs are
    /// stored reads and the names reach the address book.
    @State private var roster = SafeRoster(safes: [])
    @State private var room: SafeRoom?
    /// The money across the Safes, already masked under Hide balances.
    let total: String?
    /// Opens a queued transaction by its `sourceRef`.
    var onOpen: (String) -> Void
    /// Opens a Safe: your account's keys, or the Safe's own app.
    var onOpenSafe: (SafeRoster.Safe) -> Void
    /// Changes when the queue's rows land, are signed or leave, so the box
    /// reads the queue again (the row itself is keyed on the total only).
    var queueKey: Int = 0

    private var yourTurn: [SafeRoom.Entry] {
        (room?.entries ?? []).filter(\.yourTurn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if let lead = yourTurn.first {
                Text(verbatim: SafeRoster.toSign(yourTurn.count))
                    .dsText(.price40)
                    .foregroundStyle(DS.pickInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: SafeRoster.signStatement(safeName: SafeRoomSource.name(for: lead.safeAddress),
                                                        have: lead.have, required: lead.required))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(yourTurn.prefix(2))) { entry in
                        entryRow(entry)
                    }
                    signRow(lead)
                }
            } else {
                // Before the money is read, the figure is how many Safes.
                Text(verbatim: total ?? (roster.safes.count == 1 ? String(localized: "1 Safe")
                                         : String(localized: "\(roster.safes.count) Safes")))
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: SafeRoster.statement(roster, waiting: room?.entries.count ?? 0))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(roster.safes.prefix(SafeRoster.boxCap))) { safe in
                        safeRow(safe)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: queueKey) {
            compose()
            await SafeRosterReading.shared.refresh()
            compose()
        }
    }

    private func compose() {
        room = SafeRoomSource.compose()
        roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
    }

    // MARK: - Rows

    private func safeRow(_ safe: SafeRoster.Safe) -> some View {
        Button {
            DSHaptic.selection()
            onOpenSafe(safe)
        } label: {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: safe.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: SafeRoster.line(safe))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                SafeFaces(faces: safe.faces)
                if let need = SafeRoster.need(safe) {
                    Text(verbatim: need)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(verbatim: [safe.name, SafeRoster.line(safe), SafeRoster.need(safe)]
            .compactMap { $0 }.joined(separator: ", ")))
    }

    private func entryRow(_ entry: SafeRoom.Entry) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(entry.ref)
        } label: {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: SafeRoster.entryName(entry.descriptionText))
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: waitingLine(entry))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: String(localized: "\(entry.have) of \(entry.required)"))
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// The one act: the sign block, which reads, simulates and signs.
    private func signRow(_ lead: SafeRoom.Entry) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(lead.ref)
        } label: {
            HStack {
                Text("Review and sign")
                    .dsText(.body17)
                    .foregroundStyle(DS.pickInk)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// "Studio · waiting on you and 1 other". The owners still to sign are
    /// named by address, and yours is among them on your turn, so it is
    /// counted as you rather than named again by your wallet's name.
    private func waitingLine(_ entry: SafeRoom.Entry) -> String {
        let safe = SafeRoomSource.name(for: entry.safeAddress)
        guard entry.yourTurn else { return safe }
        let others = max(entry.waitingOn.count - 1, 0)
        switch others {
        case 0: return String(localized: "\(safe) · waiting on you")
        case 1: return String(localized: "\(safe) · waiting on you and 1 other")
        default: return String(localized: "\(safe) · waiting on you and \(others) others")
        }
    }
}

/// A Safe's owners as faces: yours in the pick's ink with what
/// it is (this iPhone, the recovery key, the co-signer), the others by the
/// first letter of their name (prd §1614).
struct SafeFaces: View {
    let faces: [SafeRoster.Face]
    private let size: CGFloat = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(faces.prefix(SafeRoster.faceCap).enumerated()), id: \.offset) { _, face in
                disc(face)
            }
            if faces.count > SafeRoster.faceCap {
                disc(.person("+\(faces.count - SafeRoster.faceCap)"))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func disc(_ face: SafeRoster.Face) -> some View {
        ZStack {
            Circle().fill(face.isYours ? DS.pickInk : DS.fillStrong)
            switch face {
            case .phone: glyph("iphone")
            case .recovery: glyph("key.fill")
            case .coSigner: glyph("person.badge.key.fill")
            case .you: glyph("person.fill")
            case .person(let initial):
                if initial.isEmpty {
                    glyph("person.fill")
                } else {
                    Text(verbatim: initial)
                        .dsText(.label12)
                        .foregroundStyle(DS.textPrimary)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .dsGlyph(.caption)
            .foregroundStyle(Color.white)
    }
}
