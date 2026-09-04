import SwiftUI

/// The slab — the app's one shape for a manage page's controls (prd §190,
/// 2026-07-23; born on the Wallet manager as §189's `WalletSlab*`).
///
/// The complaint that started it, about the Wallet screen below its roster:
/// *"we have different fonts, different shapes, and I think to myself, how
/// would Cash App do this screen."* It was a fair census — a recessed field
/// with a side pill, a full-width capsule with a caption, three paragraph
/// footers, a headed section with a blue text link, and a gear row: six shapes
/// and four type rungs stacked on each other. The answer wasn't new art, it
/// was one rule, and the rule generalizes to every manage page in the catalog:
///
/// **Below a screen's identity area, every control is a slab** — one height,
/// one radius (`DS.Radius.widget`, the tile radius §8 already sanctions). The
/// only round things on a manage page are people and assets (§185's mark
/// grammar). The eye then reads a rhythm instead of a collage.
///
/// **One font, and it is SF Pro Text.** The mock that won this set the slabs
/// in SF Rounded, Cash App style. That would break a standing rule
/// (`Typography.swift`, 2026-07-09): SF Rounded is the DISPLAY tier only —
/// "functional text (body, rows, labels) stays SF Pro Text, which scans
/// crisper at UI sizes and keeps the app feeling native." The complaint was
/// *inconsistency*, and consistency is the fix, so every slab is the text face
/// at one weight; the rounded face stays where it lived, on display headings.
///
/// **What is NOT a slab**, deliberately: a page's own content rows (a topic, a
/// feed, a store — those wear §184/§185's marks and are the person's data, not
/// a control); the shelves and rosters above, which the ruling explicitly kept
/// ("I do not want to change any of the top shelf rows of avatars"); the
/// numbered steps of a pre-connect form (kept whole by §186); and Disconnect,
/// which stays the quiet centered red row it already is on every screen —
/// destructive sits outside the rhythm on purpose.
///
/// **One gray sentence per screen** is the companion rule. Most of the "form
/// feel" on these pages was never the controls; it was two or three footer
/// paragraphs stacked under them. Everything a footer said moves to the door,
/// dialog, or screen that owns it.
enum DSSlab {
    static let height: CGFloat = 56
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
    }

    /// TWO SIZES, named (2026-08-28 component sweep).
    ///
    /// A setup screen's slab is the page's own control and takes the room; a
    /// filter sitting above a list inside a tray is chrome over the thing you
    /// came for, and 56pt of it pushes the list down inside a height budget
    /// the tray already spends carefully. Both existed already — three trays
    /// had hand-rolled the compact one and two directory screens had
    /// hand-rolled the slab one, spelling its height as
    /// `DS.Radius.widget + 36` — so this names the rungs rather than
    /// inventing one, and there are two so nobody has to hand-tune a third.
    enum Size {
        case slab, compact

        var height: CGFloat { self == .slab ? DSSlab.height : DS.Hit.min }
        var padding: CGFloat { self == .slab ? DS.Space.s4 : DS.Space.s3 }
        /// The compact rung is a CONTROL, not a slab, and takes the control
        /// radius — 20 on a 44pt box reads as a capsule that failed.
        var shape: RoundedRectangle {
            self == .slab ? DSSlab.shape
                : RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        }
        /// Off the mark ramp's own reasoning: the glyph tracks the box.
        var glyphSize: CGFloat { self == .slab ? 15 : 14 }
    }
}

/// The field slab — one shape holding both the input and its verb. Replaces
/// field-plus-side-pill, which read as two controls for one act.
///
/// The verb is text, not a filled capsule: a filled control inside a filled
/// well is the "button in a button" that made these areas busy. It dims until
/// there's something to act on, so it still says when it's live (the §83 rule
/// that a control states its own disabled state, not just grays its label).
struct DSSlabField: View {
    let placeholder: String
    @Binding var text: String
    /// The verb, in caps — the one place caps are right, because it's a
    /// control label inside a field, not an eyebrow over content (§8 bans
    /// ALL-CAPS eyebrows, which this isn't).
    let actionLabel: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var focus: FocusState<Bool>.Binding? = nil
    /// Fires even when the field is empty, for callers whose verb doesn't need
    /// input (the address book's NAME opens a sheet).
    var alwaysEnabled = false
    /// A caller-supplied arm condition — overrides the default "text isn't
    /// empty" when the verb should only light up in a specific state (the
    /// address book's ADD, live only when the typed text is an addable
    /// address, not any old search term).
    var isArmed: Bool? = nil
    /// A SECOND verb inside the same slab (prd §212, 2026-07-25) — the quieter
    /// one, shown only while `secondaryArmed`. It exists because the Wallet
    /// manager has two real things to do with a typed address (watch it, which
    /// is capped and starts syncing; or just name it, which is neither), and
    /// the second one was a floating text button on its own line under the
    /// field — a fifth block on a page whose whole problem was block count.
    /// Two verbs in one slab is still one control for one act; a second line
    /// was two.
    var secondaryLabel: String? = nil
    var secondaryArmed = false
    var secondaryAction: () -> Void = { }
    /// A LEADING glyph inside the well — in practice `magnifyingglass`, which
    /// is the whole reason five screens hand-rolled this field instead of
    /// using it (2026-08-28). Absent by default: a setup slab's placeholder
    /// already says what it wants.
    var glyph: String? = nil
    /// Offer an × that empties the field once there is something in it.
    ///
    /// Only ever right on a field you FILTER with, never on one you fill in:
    /// clearing a typed key is a keystroke away and the × would sit where a
    /// verb belongs. Off by default for that reason.
    var clearable = false
    /// A spinner in the trailing slot, for a field whose submit goes to the
    /// network (`DSSlabButton.busy`'s sibling).
    var busy = false
    /// Which rung — `.slab` is the page's own control, `.compact` is a filter
    /// over a list. See `DSSlab.Size`.
    var size: DSSlab.Size = .slab
    /// The return key's word. `.return` everywhere but the fields whose submit
    /// really does finish something.
    var submitLabel: SubmitLabel = .return
    /// `.never` because this slab was born holding API keys, handles and
    /// addresses, where a capital letter inserted by the keyboard is a wrong
    /// value. A field that holds a NAME somebody is writing says so.
    var autocapitalization: TextInputAutocapitalization = .never
    let action: () -> Void

    private var armed: Bool {
        if let isArmed { return isArmed }
        return alwaysEnabled || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasText: Bool { !text.isEmpty }

    var body: some View {
        // Spacing unchanged at `s3` — the glyph joins the row every existing
        // slab already lays out, rather than the row being re-tuned around it.
        HStack(spacing: DS.Space.s3) {
            if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(size.glyphSize, weight: .medium)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
            }
            Group {
                if let focus {
                    field.focused(focus)
                } else {
                    field
                }
            }
            if busy { ProgressView().controlSize(.small) }
            if clearable, hasText {
                Button {
                    DSHaptic.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(size.glyphSize, weight: .regular)
                        .foregroundStyle(DS.textTertiary)
                        .dsTapTarget(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
            if let secondaryLabel, secondaryArmed {
                Button(action: secondaryAction) {
                    Text(secondaryLabel)
                        .dsText(.subhead13).fontWeight(.bold)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            // An EMPTY verb means this slab is one of a pair — the first of
            // two inputs a single act needs (Steam's profile beside its key,
            // Mail's address beside its app password). The verb belongs to the
            // last field, where the act completes; repeating it on both would
            // read as two ways to connect.
            if !actionLabel.isEmpty {
                Button(action: action) {
                    Text(actionLabel)
                        .dsText(.subhead13).fontWeight(.bold)
                        .foregroundStyle(armed ? DS.tint : DS.textTertiary)
                        .animation(DS.Motion.standard, value: armed)
                }
                .buttonStyle(.plain)
                .disabled(!armed)
            }
        }
        .animation(DS.Motion.standard, value: secondaryArmed)
        .padding(.horizontal, size.padding)
        // **A FLOOR, NOT A FIXED HEIGHT (prd §545, 2026-08-31, reported: "the
        // search and paste field is clipped or messed up somehow").** `.frame
        // (height:)` pins the slab at 56 whatever is inside it, so at larger
        // Dynamic Type the placeholder and its verb are drawn into a box that
        // cannot grow and the text is cut off at the slab's own edge — on the
        // one control that is the way IN to this screen.
        //
        // A minimum keeps every default-size field pixel-identical (they all
        // measure under 56 today) and lets the two that need it grow. The
        // vertical padding is what stops a grown field's text touching the
        // edge it just pushed out.
        .padding(.vertical, DS.Space.s2)
        .frame(minHeight: size.height)
        // **THE TOP IS THE EDGE (prd §524/§542's rule, applied here
        // 2026-09-03, reported: "address book search bar is still clipping and
        // weird" — the SECOND report on this control).**
        //
        // §545 read the first report as a Dynamic Type overflow and swapped the
        // pinned height above for a floor. Its own entry said what to do if
        // that was wrong: *"if the report was at DEFAULT type size then
        // something else is also wrong and this did not fix it."* It was at
        // default type. The height was never the problem.
        //
        // **The fill was.** A bare `DS.surfaceWell` is `#080809` and the ink
        // page is `#000000` — a 1.03:1 step, so on the screen where this field
        // sits directly on the page it draws no top edge, no side edge and no
        // corner. What is left is a placeholder floating in black with a verb
        // beside it, which reads exactly as a box cut off above its text. This
        // is prd §449's finding one control over, in the same words the wallet
        // tray's pile earned them: on an ink page there is nothing darker than
        // the page to dip toward, so a recess drawn by tone alone is an
        // invisible one.
        //
        // It was the LAST member of its own family without an edge, which is
        // what makes this a §542 miss rather than a design question: the sweep
        // that made the page ink converted nine sites by anatomy, and every
        // other slab already reads — `DSSlabDoor` and `DSSlabSwitch` are the
        // same shape at the same height on `DS.gray100`, and every card on the
        // page takes `dsInkFill`'s pour. Only the field kept a token chosen
        // back when it sat on a `#111113` card.
        //
        // The fix is the app's own universal answer rather than a new one: the
        // well tone KEPT (a field is still something you look into, and the
        // recess is correct wherever this slab really does sit on a card) with
        // `DS.pourInk` across the top, which is `dsSheetSurface`'s "the pour is
        // the surface's only edge" verbatim. On ink the top composites to
        // ~`#1a1a1b` and the corner is drawn again; on a card nothing moves but
        // the same top every neighbour already wears.
        //
        // Spelled here rather than through `dsInkFill` because that helper
        // fills `DS.surfaceSheet` — black — which is the card's tone, not a
        // well's, and would put the field on the same plane as the thing
        // holding it.
        // **THE WELL FILL IS GONE; THE POUR STAYS** (prd §590, 2026-09-03,
        // user: *"the search apps bar looks like it has a card behind it too
        // pls remove"*, after the same ruling took the cards off the catalog's
        // sections and, before that, off every sheet head in §583).
        //
        // Everything above still holds and is why this is a TRIM rather than a
        // deletion. §545's device report — the field reading as "a box cut off
        // above its text" — was a field with NO edge at all, and the answer to
        // it was the pour, not the fill: on ink the pour composites a top and
        // redraws the corner, which is what makes this legible as a control.
        // The fill was the part that made it read as an object sitting on the
        // page rather than a recess in it, and it is the part the user is
        // naming.
        //
        // Asked rather than assumed, because §545's report is real evidence
        // against removing this wholesale — the choice was between a quieter
        // field and no background at all, and the quieter field is the ruling.
        //
        // **On a CARD this now draws nothing but its own top.** That is the
        // honest trade and it is the smaller loss: a slab inside a card is
        // already bounded by the card, so the recess was the least load-bearing
        // there; on the ink page, where this field mostly lives, the pour is
        // doing all the work it ever did.
        .background {
            LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(size.shape)
        }
    }

    @ViewBuilder private var field: some View {
        Group {
            if secure {
                SecureField(LocalizedStringKey(placeholder), text: $text)
            } else {
                TextField(LocalizedStringKey(placeholder), text: $text)
            }
        }
        .dsText(.body17)
        .foregroundStyle(DS.textPrimary)
        .tint(DS.tint)
        .keyboardType(keyboard)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled()
        .submitLabel(submitLabel)
        .onSubmit(action)
    }
}

/// The primary slab — a screen's one filled block, so it reads as THE verb.
///
/// A door's label is a VERB, never a route (ruling 2026-08-14, from a report
/// that "the words barely fit in the CTA": "Open pagerduty.com → Integrations
/// → API Access Keys" ran edge to edge inside the 56pt slab). The big words
/// stay short — "Get your API key" — and the address goes to `detail`, quiet
/// type under the verb, still on the button so the door stays checkable
/// against the address bar it opens. The tab trail belongs to the step lines
/// below, or nowhere when the URL lands on the tab directly.
struct DSSlabButton: View {
    let title: String
    /// The address under the verb — a fact, not part of the verb. Empty keeps
    /// the plain single-line slab.
    var detail: String = ""
    var systemImage: String? = nil
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .dsGlyph(15)
                }
                if detail.isEmpty {
                    verb
                } else {
                    VStack(spacing: 1) {
                        verb
                        Text(detail)
                            .dsText(.label12)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            // Quiet against the fill, not a second headline —
                            // the disabled fill already flattens everything to
                            // tertiary below, so only the live state dims it.
                            .opacity(enabled && !busy ? 0.75 : 1)
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            // A hand-rolled fill must swap the FILL when inert, not just dim
            // the label (§83, paid for by a button that read live while dead).
            .foregroundStyle(enabled && !busy ? AnyShapeStyle(.white)
                                              : AnyShapeStyle(DS.textTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: DSSlab.height)
            .background(enabled && !busy ? AnyShapeStyle(DS.tint)
                                         : AnyShapeStyle(DS.gray200),
                        in: DSSlab.shape)
            .contentShape(DSSlab.shape)
            .animation(DS.Motion.standard, value: busy)
            .animation(DS.Motion.standard, value: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }

    /// One line, shrinking a little before it would ever wrap — a verb the eye
    /// can't finish reading is worse than one set a point smaller, and German
    /// and Japanese make a long label out of a short one on every screen at
    /// once. It never earns a second line: the anatomy above exists so that a
    /// label long enough to wrap is a label carrying an address that belongs
    /// in `detail`.
    private var verb: some View {
        Text(LocalizedStringKey(title))
            .dsText(.body17).fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// A door slab — a title and the fact it stands in front of. The fact is the
/// point: a door reading "Address book · 4 names" hides nothing, where a
/// headed section holding the same four rows was just furniture.
struct DSSlabDoor: View {
    let title: String
    var detail: String = ""
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .dsGlyph(15, weight: .medium)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Text(detail)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .dsGlyph(12)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(height: DSSlab.height)
            .background(DS.gray100, in: DSSlab.shape)
            .contentShape(DSSlab.shape)
        }
        .buttonStyle(.plain)
    }
}

/// A switch slab — the shape for a control that STARTS something, on the
/// pages where flipping it is the whole act (a chain on OpenSea or
/// GeckoTerminal, a seat on Peer or Privacy Pools). Those rows aren't settings
/// hiding in a card; each one is that screen's connect verb for one lane, so
/// it gets a full block rather than a line in a stacked toggle list.
///
/// The detail line stays ONE line and carries the lane's own fact, never an
/// explanation — explanations belong to the screen's single sentence.
struct DSSlabSwitch: View {
    let title: String
    var detail: String = ""
    @Binding var isOn: Bool

    var body: some View {
        // `Toggle` rather than a hand-rolled knob: it keeps the switch trait
        // for VoiceOver and the whole label as the target. (Sim gotcha, not a
        // bug: switches ignore a synthetic tap — drive them with a drag
        // across the knob.)
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .tint(DS.tint)
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DSSlab.height)
        .background(DS.gray100, in: DSSlab.shape)
    }
}

/// The screen's one sentence — the promise, centered under its controls.
/// Every manage page gets exactly one; everything else a footer used to say
/// moves behind the door or dialog that owns it.
struct DSSlabNote: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s1)
    }
}

/// A scannable checkmark list — capabilities or features, one per line (prd
/// §192, 2026-07-23). Born on `BridgeConnectedState` ("capabilities are
/// sentences") for the CONNECTED state; promoted here so the product page can
/// render the same visual grammar PRE-connect, when a bridge's differentiated
/// features don't fit the one-sentence hook the summary rule caps at (Wallet's
/// approval/DeFi/Safe monitoring is the case that forced this: six real,
/// distinct capabilities were being crammed into one 60-word run-on clause
/// rather than deleted or restructured). Same lines, same look, whichever side
/// of Connect you're standing on.
///
/// The MARK is a parameter because a checkmark makes a CLAIM (this is granted,
/// this is verified) and not every scannable list is making it. Stripe's setup
/// screen put two of these on one page — the six scopes the key will hold, and
/// the four kinds of news that land — and in a green checkmark apiece they read
/// as one list of ten equivalent facts, when one is a permission and the other
/// is content (caught on screen, 2026-07-31). A list of what ARRIVES takes the
/// neutral bullet instead; the checkmark stays for what's actually granted.
struct DSCheckList: View {
    let lines: [String]
    /// The leading mark. Defaults to the granted-capability checkmark.
    var systemImage = "checkmark"
    /// Its color — confirm green reads as "yes, you have this"; tertiary is the
    /// neutral bullet for a list that isn't claiming anything.
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Image(systemName: systemImage)
                        .dsGlyph(11, weight: .bold)
                        .foregroundStyle(tint ?? DS.confirm)
                    Text(LocalizedStringKey(line))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    /// The list-row dress every slab stack wears: full-bleed to the screen's
    /// own margins, no list chrome, no separator. One modifier so a slab
    /// section can never drift from the wallet's spacing.
    func dsSlabSection(topPadding: CGFloat = DS.Space.s2) -> some View {
        self
            .listRowInsets(EdgeInsets(top: topPadding, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
