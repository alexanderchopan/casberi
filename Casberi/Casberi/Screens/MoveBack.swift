import SwiftUI

/// **THE WAY BACK TO MOVE'S MENU (prd §1781).** The verb in a sentence used
/// to open the verbs; nothing in a sentence takes a touch now, so every
/// sentence's foot leads with this card. Move's own sentence hands it the
/// act; the sentences Move mounts (Lend, a private send, Receive privately,
/// Receive on Aztec) read it from the environment Move sets over them.
struct MoveBackCard: View {
    /// The act, where the caller holds it; else the environment's.
    var act: (() -> Void)?
    var disabled = false
    @Environment(\.moveBack) private var back

    var body: some View {
        if let go = act ?? back {
            Button {
                go()
                DSHaptic.selection()
            } label: {
                // **A BARE CHEVRON (prd §1897 item 7):** the way back at the
                // foot's left edge, with no card under it.
                Image(systemName: "chevron.left").dsGlyph(.title, weight: .bold)
                    .foregroundStyle(disabled ? DS.textTertiary : DS.textPrimary)
                    .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .disabled(disabled)
            .accessibilityLabel(Text("Back to the list"))
        }
    }
}

private struct MoveBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Move's menu, set by Move over the sentences it mounts.
    var moveBack: (() -> Void)? {
        get { self[MoveBackKey.self] }
        set { self[MoveBackKey.self] = newValue }
    }
}

/// **A SENTENCE'S CHOICES, AS ROWS (prd §1781).** The private sentences and
/// Lend write their own words; what each word did is a row here, in the
/// shape of Move's own: the name grey, what is picked in white, a chevron
/// because something opens, "Choose" in the pick's pink where the first
/// thing is still to be picked.
struct MoveChoiceRow: Identifiable {
    let id: String
    let name: String
    let value: String
    var empty = false
    var ink: Color?
    var mark: MoveRowMark?
    /// The row's own field, drawn where its value stands while `typing`
    /// (prd §1791: an amount is typed in its row). Always mounted, so it
    /// can take the focus.
    var field: AnyView?
    var typing = false
    /// The field is an amount: typed at `MoveChoiceRowLabel.figureRung` in
    /// the answer's place (prd §1892). A note typed in its row stays small.
    var figure = false
    /// A fact every line shares and this sentence cannot change (its one
    /// network): grey, with no menu chevron, and no button.
    var fixed = false
    let act: () -> Void
}

/// **A CHOICE'S ROW (prd §1782).** The name small above, what is picked
/// large beneath it, a chevron at the trailing edge: the answer is the
/// thing seen and pressed, where a small figure at the far edge read as a
/// settings form.
struct MoveChoiceRowLabel: View {
    let name: String
    let value: String
    var ink: Color = DS.textPrimary
    /// No chevron while the row's value is being typed in place.
    var chevron = true
    /// The token's or the network's own mark, before the value.
    var mark: MoveRowMark?
    /// One amber word before the answer: "New", on a first send (prd §1805).
    var note: String?
    /// **AN UNANSWERED ROW IS NAMED BY WHAT IT ASKS (prd §1892).** Nothing
    /// picked yet: the row's name is its one line, in `ink` (the pick's pink
    /// on the next row, grey on the rest). Five rows reading "Choose" read
    /// as five disabled rows.
    var asks = false
    /// Its list is open under it (prd §1889): the chevron turns up.
    var isOpen = false
    /// A figure is being typed in it (prd §1892): the row keeps a slot at
    /// `figureRung` for the caller's field (`figureSlot`), and grows to hold it.
    var typing = false
    /// The grey line under a typed figure, where it says more than the
    /// row's name ("You have $248.40").
    var caption: String?

    var body: some View {
        // **HOME'S ROW (prd §1889, the user over Home and Move side by side:
        // "i like it").** The mark leads, what is picked is the row's name,
        // and what the row asks is its grey line under it, as every Wallet
        // row reads; a chevron because something opens. A row with no mark
        // keeps the column, so every answer starts at one edge.
        HStack(alignment: .center, spacing: Self.leadGap) {
            Group {
                if let mark {
                    MoveRowMark(token: mark.token, network: mark.network, brand: mark.brand, size: Self.markSize)
                } else {
                    // No mark yet: the row's own glyph on a quiet disc, as
                    // Home's rows lead (prd §1889).
                    MoveRowGlyph(symbol: Self.glyph(for: name))
                }
            }
            .frame(width: Self.markSize, height: Self.markSize)
            VStack(alignment: .leading, spacing: Self.lineGap) {
                if typing {
                    // The figure's slot: the caller's field draws over it.
                    Text(verbatim: "0").dsText(Self.figureRung).hidden().accessibilityHidden(true)
                    Text(verbatim: caption ?? name).dsText(.fact15).foregroundStyle(DS.textSecondary).lineLimit(1)
                } else if asks {
                    Text(verbatim: name).dsText(.heading20).foregroundStyle(ink).lineLimit(1)
                } else {
                    HStack(spacing: DS.Space.s2) {
                        if let note {
                            Text(verbatim: note).dsText(.heading17).foregroundStyle(DS.attentionInk).lineLimit(1)
                        }
                        Text(verbatim: value)
                            .dsText(.heading20)
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: name).dsText(.fact15).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            // **THE LIST OPENS UNDER THE ROW, SO THE CHEVRON POINTS DOWN (prd
            // §1892):** a chevron to the right said a page would push.
            Image(systemName: "chevron.down").dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(DS.Motion.standard, value: isOpen)
                .opacity(chevron && !typing ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(minHeight: typing ? Self.typingHeight : Self.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(asks ? Text("Choose") : Text(verbatim: ""))
    }

    static let markSize: CGFloat = 36
    /// Between a row's answer and its name.
    static let lineGap: CGFloat = 2
    /// **THE AMOUNT IS THE FIGURE WHILE IT IS TYPED (prd §1892).** The typed
    /// figure was the smallest thing on the screen, at the row's far edge.
    static let figureRung: DSTextStyle = .heading44
    /// A row holding a typed figure and its line.
    static let typingHeight: CGFloat = 92

    /// The caller's field, laid over a typing row's slot: the same two
    /// lines, so the figure stands exactly where the slot is at any size.
    static func figureSlot<Field: View>(name: String, @ViewBuilder field: @escaping () -> Field) -> some View {
        VStack(alignment: .leading, spacing: lineGap) {
            MoveFigureFit(content: field)
            Text(verbatim: name).dsText(.fact15).lineLimit(1).hidden().accessibilityHidden(true)
        }
        .padding(.leading, leadColumn)
    }

    /// A row's glyph when it has no mark, by what it asks.
    static func glyph(for name: String) -> String {
        switch name {
        case String(localized: "To"): "person"
        case String(localized: "From"): "wallet.bifold"
        case String(localized: "Network"): "globe"
        case String(localized: "Amount"): "dollarsign"
        case String(localized: "Token"): "circle.circle"
        case String(localized: "When"): "clock"
        case String(localized: "Co-signer"): "person.2"
        case String(localized: "Signs"): "iphone"
        default: "circle.dotted"
        }
    }
    static let leadGap: CGFloat = DS.Space.s4
    /// Where a row's words start: an open list lines up under them (prd §1889).
    static var leadColumn: CGFloat { markSize + leadGap }
    static let height: CGFloat = 64
}

/// **A FACT UNDER THE CHOICES (prd §1892, every sentence since §1896).** Its
/// name grey, its figure trailing, at the facts' pitch, in the answers'
/// column: the private sends and Earn wrote theirs as a line at the page's
/// edge ("about a minute", "Earns 5.1% today"). A fact with no figure is
/// its name alone.
struct MoveFactRow: View {
    let name: String
    var value: String?
    var valueInk: Color = DS.textPrimary
    var nameInk: Color = DS.textSecondary
    /// In the rows' column under a sentence still drawn with them; the
    /// Deck's facts stand at the page's edge (prd §1897 item 1).
    var indented = true
    /// A word that acts on the fact, in the figure's place ("Use all",
    /// prd §1916).
    var act: (word: String, run: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(nameInk)
                .fixedSize(horizontal: false, vertical: true)
            if let value, act != nil {
                Text(verbatim: value).dsText(.body17).foregroundStyle(nameInk).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if let act {
                Button {
                    act.run()
                    DSHaptic.snap()
                } label: {
                    Text(verbatim: act.word).dsText(.heading17).foregroundStyle(DS.pickInk)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
            } else if let value {
                Text(verbatim: value).dsText(.body17).foregroundStyle(valueInk)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }
        }
        .frame(minHeight: MoveSentence.factHeight)
        .padding(.leading, indented ? MoveChoiceRowLabel.leadColumn : 0)
        .accessibilityElement(children: .combine)
    }
}

/// A typed figure at its own width, drawn smaller only when it is wider
/// than its row (prd §1892): a field cannot shrink its own text, and
/// eighteen decimals at `figureRung` ran off the trailing edge.
struct MoveFigureFit<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 0
    @State private var room: CGFloat = 0

    var body: some View {
        content()
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .scaleEffect(room > 0 && width > room ? room / width : 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
    }
}

/// **A ROW'S GLYPH ON A QUIET DISC (prd §1889, Receive's places since
/// §1892):** the lead of a Move row with no token, network or app mark of
/// its own, at the mark's size, so every answer starts at one edge.
struct MoveRowGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).dsGlyph(.body, weight: .medium)
            .foregroundStyle(DS.textSecondary)
            .frame(width: MoveChoiceRowLabel.markSize, height: MoveChoiceRowLabel.markSize)
            .background(Circle().fill(DS.fillFaint))
            .accessibilityHidden(true)
    }
}

/// A choice's answer with its mark and the menu chevron: a whole row's
/// trailing edge, or one half of a pair (Swap's network and token).
struct MoveChoiceValue: View {
    let value: String
    var ink: Color = DS.textPrimary
    var chevron = true
    var mark: MoveRowMark?
    var note: String?

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            if let note {
                Text(verbatim: note).dsText(.heading17).foregroundStyle(DS.attentionInk).lineLimit(1)
                    .transition(.opacity)
            }
            if let mark { mark }
            // **A LONG NAME WRAPS, IT NEVER SHRINKS (prd §1805):** two lines
            // at the row's own size, read from the trailing edge.
            Text(verbatim: value)
                .dsText(.heading20)
                .foregroundStyle(ink)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down").dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .opacity(chevron ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

/// **A NETWORK ALWAYS SHOWS ITS MARK (prd §1792, user: "are we going to
/// show icons for networks? we should always imo").** A token wears its
/// own mark with its network's as a badge; a network alone wears its own.
/// In rows and menus, never inside Move's sentence.
struct MoveRowMark: View {
    /// A token's symbol.
    var token: String?
    /// A network's bundled mark (`MoveSentence.networkMark`).
    var network: String?
    /// A merchant's or an app's mark, by its catalogue name.
    var brand: String?
    var size: CGFloat = 24

    var body: some View {
        if let brand {
            BridgeIcon(name: brand, size: size).accessibilityHidden(true)
        } else if let token {
            AssetMark(name: token, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if let network {
                        disc(network, size / 2)
                            .overlay(Circle().stroke(DS.page, lineWidth: 2))
                            .offset(x: size / 6, y: size / 6)
                    }
                }
                .accessibilityHidden(true)
        } else if let network {
            disc(network, size).accessibilityHidden(true)
        }
    }

    private func disc(_ name: String, _ side: CGFloat) -> some View {
        Image(name).resizable().scaledToFill().frame(width: side, height: side).clipShape(Circle())
    }
}

struct MoveChoiceRows<Menu: View>: View {
    let rows: [MoveChoiceRow]
    var disabled = false
    /// The ink of the first row still to be picked: the pick's, or Aztec's
    /// own on an Aztec sentence (prd §1779).
    var nextInk: Color = DS.pickInk
    /// **A LIST IS A MENU ON ITS ROW (prd §1784).** The id of the row whose
    /// menu is up, and that row's list. The rows stay where they are; a tap
    /// outside the menu sets this nil.
    var open: Binding<String?>
    @ViewBuilder var menu: (String) -> Menu
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        if !rows.isEmpty {
            let next = rows.first { $0.empty }?.id
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { r in
                    if r.fixed {
                        MoveChoiceRowLabel(name: r.name, value: r.value, ink: DS.textSecondary, chevron: false, mark: r.mark)
                    } else {
                    Button {
                        guard !r.typing else { return }
                        r.act()
                        DSHaptic.selection()
                    } label: {
                        MoveChoiceRowLabel(name: r.name, value: r.typing ? " " : r.empty ? String(localized: "Choose") : r.value,
                                           ink: r.id == next ? nextInk : r.empty ? DS.textSecondary : r.ink ?? DS.textPrimary,
                                           chevron: !r.typing, mark: r.empty || r.typing ? nil : r.mark,
                                           asks: r.empty && !r.typing, isOpen: open.wrappedValue == r.id,
                                           typing: r.typing && r.figure)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Changes it"))
                    // The row whose list is open stays lit; the rest step back (prd §1889).
                    .opacity(open.wrappedValue == nil || open.wrappedValue == r.id ? 1 : MoveSentence.steppedBack)
                    .animation(DS.Motion.standard, value: open.wrappedValue)
                    .animation(DS.Motion.standard, value: r.typing)
                    .overlay(alignment: r.figure ? .leading : .trailing) {
                        if let field = r.field {
                            Group {
                                if r.figure { MoveChoiceRowLabel.figureSlot(name: r.name) { field } } else { field }
                            }
                            .opacity(r.typing ? 1 : 0)
                            .allowsHitTesting(r.typing)
                            .accessibilityHidden(!r.typing)
                        }
                    }
                    // The list opens in place under its row (prd §1889).
                    if open.wrappedValue == r.id {
                        MoveMenuBox { menu(r.id) }
                            .environment(chrome)
                            .transition(.opacity)
                    }
                    }
                }
            }
            .disabled(disabled)
        }
    }
}

/// One sum in an amount's menu.
struct MoveAmountPick: Identifiable {
    let id: String
    let title: String
    var trailing: String?
    var picked = false
    let act: () -> Void
}

/// **AN AMOUNT'S MENU, FOR EVERY SENTENCE (prd §1802).** What you have at
/// its head, the sums as rows, then "Another amount", which raises the keys
/// in the row. The Half · All pills under a sentence are retired for it.
struct MoveAmountMenu: View {
    var have: String?
    let picks: [MoveAmountPick]
    var ink: Color = DS.pickInk
    let another: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let have {
                // The scope, as a caption (prd §1804).
                Text(verbatim: have).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 28, alignment: .leading)
            }
            ForEach(picks) { p in row(p.title, trailing: p.trailing, picked: p.picked, act: p.act) }
            row(String(localized: "Another amount"), trailing: nil, picked: false, act: another)
        }
    }

    /// A menu's row is menu type (prd §1804): the name at `heading17`, its
    /// figure grey beside it, and a mark on the pick.
    private func row(_ title: String, trailing: String?, picked: Bool, act: @escaping () -> Void) -> some View {
        Button {
            act()
            DSHaptic.selection()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: title).dsText(.heading17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let trailing {
                    Text(verbatim: trailing).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit().lineLimit(1)
                }
                if picked { MoveMenuCheck(ink: ink) }
            }
            .frame(minHeight: MoveSentence.listRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}

/// A row's list as its menu (prd §1784): a menu's width, as tall as its
/// rows up to `MoveSentence.menuRoom`, then they scroll, on the system's own
/// popover ground. A popover on the phone too, never a sheet.
struct MoveMenuBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // **IN PLACE, NOT A BOX (prd §1889, retiring §1804's glass):** the
        // list stands under its row in the rows' column; the page scrolls.
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, DS.Space.s2)
    }
}

/// A list's own name at its head, which closes it without a pick (prd
/// §1781): the sentence's word used to, and takes no touch now.
struct MoveListBack: View {
    let name: String
    var ink: Color = DS.pickInk
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            // The glyph in the head column, as every section name's (prd §1496).
            HStack(spacing: DSRoomChassis.headGap) {
                Image(systemName: "chevron.left").dsGlyph(.body, weight: .semibold)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: name).dsText(.heading24)
            }
            .foregroundStyle(ink)
            .frame(minHeight: MoveSentence.listRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Closes the list"))
    }
}

/// **A ROW THAT OPENS A SCREEN (prd §1824).** Its words, and the door's grey
/// chevron at the trailing edge (§1385: a door is grey with its chevron), so
/// it reads as tappable beside a pink verb ("Copy") that acts at once.
struct MoveDoorRowLabel: View {
    let title: String
    /// Under a row with a mark (prd §1892): its words start where that
    /// row's name does, at a list row's height, so it reads as that row's.
    var inColumn = false

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right").dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: inColumn ? MoveSentence.listRowHeight : MoveChoiceRowLabel.height)
        .padding(.leading, inColumn ? MoveChoiceRowLabel.leadColumn : 0)
        .contentShape(Rectangle())
    }
}

/// **A MOVE PAGE'S NAME STAYS, ITS ROWS PASS UNDER IT (prd §1892).** Every
/// sentence Move mounts leads with its verb as the page's name; a page
/// longer than the sheet scrolled it away and cut its top row against the
/// grabber. It stands over the page on the page's own ground, which fades
/// out under it as the foot's fades in (§1610).
struct MovePinnedHead<Head: View>: View {
    let inTray: Bool
    @ViewBuilder let head: () -> Head

    var body: some View {
        head()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .background {
                Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: MoveSentence.headFade)
                        }
                    }
                    .padding(.bottom, -MoveSentence.headFade)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// **A FOOT'S GROUND FADES IN (prd §1610, every sentence since §1892).**
    /// The page's own ground under a mounted sentence's foot, soft over
    /// `MoveSentence.footFade` above it: a row passing under goes soft
    /// instead of being cut in half.
    func moveFootGround(inTray: Bool) -> some View {
        background {
            Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: MoveSentence.footFade)
                        Color.black
                    }
                }
                .padding(.top, -MoveSentence.footFade)
                .allowsHitTesting(false)
        }
    }

    /// **THE SENTENCE STEPS AWAY WHILE A ROW IS ANSWERED (prd §1892).** An
    /// open list or a typed figure takes the sentence's room over the foot;
    /// it comes back saying the pick. Collapsed, never unmounted: Move's own
    /// rows are read off it.
    func moveSentenceAway(_ away: Bool) -> some View {
        frame(height: away ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(away ? 0 : 1)
            .accessibilityHidden(away)
            .animation(DS.Motion.standard, value: away)
    }
}

/// The mark on a menu's current pick (prd §1804): it draws itself in.
struct MoveMenuCheck: View {
    var ink: Color = DS.pickInk

    var body: some View {
        Image(systemName: "checkmark")
            .dsGlyph(.caption, weight: .bold)
            .foregroundStyle(ink)
            .symbolEffect(.bounce, options: .nonRepeating)
            .accessibilityLabel(Text("Picked"))
    }
}

/// **A VERB PRESSED GROWS TOWARD THE TITLE IT BECOMES (prd §1805).** From
/// its leading edge, so the word stays on its margin.
struct MoveVerbPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1, anchor: .leading)
            .animation(DS.Motion.standard, value: configuration.isPressed)
    }
}
