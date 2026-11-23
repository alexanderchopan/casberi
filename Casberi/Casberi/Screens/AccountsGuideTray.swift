import SwiftUI

/// **HOW YOUR ACCOUNTS WORK (prd §1947).** Account's door opens this tray:
/// the intro, then each account on Account's plate fill, closed to its name
/// and Public or Private; a tap opens its Receive, Send (Swap for
/// Railgun) and Earns in place, the chevron turning. Every account starts
/// closed (user: "yes closed"); more than one may be open.
struct AccountsGuideTray: View {
    @State private var open: Set<String> = []

    var body: some View {
        DSTray(title: AccountsGuide.title, height: 720, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: AccountsGuide.intro)
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: AccountsGuide.lede)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, DS.Space.s2)
                ForEach(AccountsGuide.accounts(pools: .current)) { account in
                    plate(account)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Space.s3)
        }
        .task {
            // Privacy Pools' minimum, rates and fee, as Receive reads them.
            if PrivateMove.available, !DemoMode.isActive {
                await PrivateMoneyStore.shared.readYield(including: .ethereum)
            }
        }
    }

    private func plate(_ account: AccountsGuide.Account) -> some View {
        let isOpen = open.contains(account.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    if isOpen { open.remove(account.id) } else { open.insert(account.id) }
                }
            } label: {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    // The name and its kind alone (user, 2026-11-23: a one-line
                    // summary left out what made it true, "kind of misleading").
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(verbatim: account.name)
                            .dsText(.heading20)
                            .foregroundStyle(account.aztec ? DS.aztecInk : DS.textPrimary)
                        Text(verbatim: AccountsGuide.kindWord(account.kind))
                            .dsText(.fact15)
                            .foregroundStyle(DS.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .dsGlyph(.caption, weight: .semibold)
                        .foregroundStyle(DS.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, DS.Space.s3)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])
            .accessibilityHint(Text(isOpen ? "Closes how it works" : "Opens how it works"))
            if isOpen {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    ForEach(account.parts) { part in
                        partView(part)
                    }
                }
                .padding(.bottom, DS.Space.s4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AccountPlate<EmptyView>.bleed)
        .background(SectionPanel.fill, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    private func partView(_ part: AccountsGuide.Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: part.title)
                .dsText(.heading17)
                .fontWeight(.bold)
                .foregroundStyle(DS.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(part.paragraphs, id: \.self) { words in
                Text(verbatim: words)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = part.goodToKnow {
                (Text(verbatim: part.noteLabel + ": ").foregroundStyle(DS.textPrimary).fontWeight(.semibold)
                    + Text(verbatim: note).foregroundStyle(DS.textSecondary))
                    .dsText(.fact15)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
