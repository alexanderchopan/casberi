import SwiftUI

/// The type ramp — **FIVE SIZES, ONE FAMILY** (prd §532, 2026-08-29).
///
/// ## What changed and why
///
/// This file used to carry sixteen distinct point sizes (9 · 10 · 11 · 12 · 13
/// · 14 · 16 · 18 · 20 · 22 · 24 · 28 · 34 · 40 · 48 · 148), and **1,562 of the
/// app's ~1,900 `dsText` calls sat in five rungs spanning 11–18pt** — steps of
/// one and two points, which is 8–14% and therefore below the threshold where a
/// size step reads as RANK. It reads as wobble instead, which this file's own
/// `rowTitle17` note already said in as many words ("17 and 18 don't separate,
/// they wobble") and then never generalised: `label11` shipped one point under
/// `label12` for months, in the same rows.
///
/// The ramp is now the usual five, at a ratio of about 1.5 throughout:
///
///     12  caption   metadata, chips, tags, timestamps
///     17  body      running text, row titles (semibold), a row's figure (bold)
///     24  title     a card's name
///     40  head      the one head on a tray, a sheet or a room
///     64  crown     money, one per surface (§506)
///
/// Steps: 1.42 · 1.41 · 1.67 · 1.60. The span from caption to crown is 5.3×,
/// against roughly 4.4× before — **further apart AND fewer**, which is the whole
/// move. Hierarchy that used to be attempted with a point or two of size is
/// carried by the three ink tiers (`DS.textPrimary`/`Secondary`/`Tertiary`) and
/// by weight, which is a bigger vocabulary than the sizes ever were: five sizes
/// × three tiers × four weights.
///
/// **The crown had to move 48 → 64.** Left at 48 it sits 1.2× from a 40pt head
/// — the same crowding this pass exists to delete, relocated to the top of the
/// ramp. At 64 the biggest number in the app is unmistakably the biggest thing
/// in the app, and §506's "one crown per surface" gets easier to hold.
///
/// ## The family
///
/// **Figtree, which was already the brand** — `website/styles.css` has embedded
/// it as a variable TTF and set the whole site in it since the site existed,
/// while the app ran on SF. The marketing surface and the product disagreed
/// about what the brand looks like, and the product was the one that was wrong.
/// The five static weights in `Shared/Fonts/` are instanced from **that same
/// file**, so the app and the site are byte-identical rather than merely
/// similar.
///
/// It is OFL-licensed (free commercially, embeddable, the font itself may not
/// be resold), 200KB for five weights, and it carries `tnum` — tabular figures,
/// which a money app cannot do without and which `dsTabularDigits` needs.
///
/// `Shared/` is synchronized into all three targets, so the app, the share
/// extension and the widgets all carry the font and all read this file. Each
/// registers it in its own `Info.plist` under `UIAppFonts`; an extension does
/// not inherit the host app's registration.
///
/// **`rounded` is gone.** SF Rounded was the display face and SF Pro Text the
/// functional one (the 2026-07-09 rule); with one family there is no second
/// face to switch to, which is what prd §190 ("we have different fonts", fixed
/// with ONE font) was reaching for. `monospaced` survives and still resolves to
/// SF Mono — Figtree has no monospaced cut, and a mono rung is a second FAMILY
/// on purpose, for log lines and device codes.
///
/// **It fails safe.** `Font.custom` falls back to the system face if
/// registration ever fails, so a broken bundle is plain-looking, never blank.
///
/// ## Dynamic Type
///
/// Unchanged in shape: every style scales via `UIFontMetrics` against its
/// nearest system text style, and the scaled result is handed to
/// `Font.custom(_:fixedSize:)` — `fixedSize` precisely BECAUSE the scaling has
/// already happened here, where `size:` would scale it a second time.
///
/// **Accessibility Bold Text is not free with a custom family.** SF answers
/// `legibilityWeight` by itself; Figtree does not, so the modifier maps the
/// weight up a step when the setting is on. Without that mapping the setting
/// silently does nothing, which is the dead-control class §83 bans.
struct DSTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineHeight: CGFloat
    /// Anchor for Dynamic Type scaling.
    var relative: UIFont.TextStyle = .body
    /// SF Mono rather than the brand family — log lines, device codes, the one
    /// place character grouping matters more than the brand does.
    var monospaced = false

    /// SwiftUI `lineSpacing` is additive over the font's intrinsic leading; this
    /// approximates the CSS line-height without measuring UIFont metrics.
    var lineSpacing: CGFloat { max(0, lineHeight - size * 1.18) }

    /// The Dynamic-Type-scaled `Font` alone, for call sites that can't use the
    /// `dsText` view modifier — e.g. a segment inside a concatenated `Text`
    /// (`Text + Text`), which requires `Text`'s own `.font(_:)` overload to
    /// stay `Text`-typed rather than erasing to `some View`.
    ///
    /// Deliberately does NOT read `legibilityWeight`: it is a plain computed
    /// property with no view context to read an environment from. A concatenated
    /// segment therefore keeps its ramp weight under Accessibility Bold Text —
    /// stated here rather than discovered later.
    var scaledFont: Font {
        let scaled = UIFontMetrics(forTextStyle: relative).scaledValue(for: size)
        return DSFont.font(size: scaled, weight: weight, monospaced: monospaced)
    }
}

/// The family, and the weight→face table (prd §532).
///
/// **Five faces, resolved BY NAME rather than by trait.** The five statics are
/// instanced with typographic family/subfamily names (name IDs 16/17) so
/// CoreText groups them under one "Figtree" family — which is what lets the
/// app's `.dsText(.x).fontWeight(.y)` idiom keep working at its ~250 call
/// sites. A rung's OWN weight never depends on that grouping: it names the
/// PostScript face outright, so it is exact whatever CoreText decides.
enum DSFont {
    /// PostScript names, as generated into `Shared/Fonts/`.
    static let regular   = "Figtree-Regular"
    static let medium    = "Figtree-Medium"
    static let semibold  = "Figtree-SemiBold"
    static let bold      = "Figtree-Bold"
    static let extraBold = "Figtree-ExtraBold"

    /// Only five weights are shipped, so lighter-than-regular maps to regular
    /// and heavier-than-extrabold maps to extrabold. Nothing in the ramp asks
    /// for either, but a `.fontWeight` override at a call site can.
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return regular
        case .regular:                   return regular
        case .medium:                    return medium
        case .semibold:                  return semibold
        case .bold:                      return bold
        case .heavy, .black:             return extraBold
        default:                         return regular
        }
    }

    /// One step up the shipped ladder — the Accessibility Bold Text answer.
    static func bolder(_ weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return .medium
        case .medium:                              return .semibold
        case .semibold:                            return .bold
        default:                                   return .heavy
        }
    }

    static func font(size: CGFloat, weight: Font.Weight, monospaced: Bool) -> Font {
        monospaced
            ? .system(size: size, weight: weight, design: .monospaced)
            : .custom(name(for: weight), fixedSize: size)
    }
}

extension DSTextStyle {
    // ============================================================= 64 · CROWN
    /// The one figure that IS the surface — the wallet total, a room's headline
    /// number. **One per card, sheet or room** (§506): the hierarchy this makes
    /// is WITHIN a surface, and you never see two crowns at once, so a second
    /// room having its own flattens nothing while a second on the SAME surface
    /// is the real defect.
    static let price48 = DSTextStyle(size: 64, weight: .heavy, tracking: 0, lineHeight: 64, relative: .largeTitle)

    // ============================================================== 40 · HEAD
    /// The head of a tray, a sheet or a room — the rung that says WHERE YOU
    /// ARE. Line height is 1.0: a head is one or two words and tight leading is
    /// what makes two lines read as one object rather than as a paragraph.
    static let heading34 = DSTextStyle(size: 40, weight: .heavy, tracking: 0, lineHeight: 40, relative: .largeTitle)
    /// The day brief's opening sentence. Same rung as the head — a lede IS the
    /// head of the document it opens, and §506 already ruled it "sets a
    /// SENTENCE, never a figure".
    static let heading28 = DSTextStyle(size: 40, weight: .heavy, tracking: 0, lineHeight: 40, relative: .largeTitle)
    /// Money at head size — a figure that leads a card without being its crown.
    static let price40 = DSTextStyle(size: 40, weight: .heavy, tracking: 0, lineHeight: 40, relative: .largeTitle)
    /// A device-flow user code: the one string on its screen, read aloud off
    /// the glass and typed into another device. Monospaced so the character
    /// groups stay even, and head-sized because it IS the screen.
    static let monoCode34 = DSTextStyle(size: 40, weight: .bold, tracking: 0, lineHeight: 44, relative: .largeTitle, monospaced: true)

    // ============================================================= 24 · TITLE
    /// A card's name.
    static let heading22 = DSTextStyle(size: 24, weight: .bold, tracking: 0, lineHeight: 28, relative: .title2)
    /// A stat card's figure — the same rung, because a card's number and a
    /// card's name are peers.
    static let stat24 = DSTextStyle(size: 24, weight: .bold, tracking: 0, lineHeight: 28, relative: .title2)

    // ============================================================== 17 · BODY
    /// A row's title — a heading for the line it leads. Says "tappable" by
    /// WEIGHT (semibold against the subline's regular), never by a second face.
    static let heading17 = DSTextStyle(size: 17, weight: .semibold, tracking: 0, lineHeight: 24, relative: .headline)
    /// Running text.
    static let body17 = DSTextStyle(size: 17, weight: .regular, tracking: 0, lineHeight: 25, relative: .body)
    /// Was a rung of its own at 16 — two points under `body17`, which reads as
    /// inconsistency rather than as rank. Kept as a NAME (the ~300 call sites
    /// are unchanged and the intent still reads) at the body size.
    static let callout15 = DSTextStyle(size: 17, weight: .regular, tracking: 0, lineHeight: 25, relative: .body)
    /// Long-form prose that is the whole point of its surface — a note body, a
    /// post's own words, a sheet's lead summary. Regular weight with the band's
    /// most open leading; what separates it from `body17` is air and ink, not a
    /// size nobody could see.
    static let reading20 = DSTextStyle(size: 17, weight: .regular, tracking: 0, lineHeight: 27, relative: .body)
    /// A row's figure. Bold at the body size — the face and the weight carry
    /// it, so a row is TWO sizes rather than four.
    static let price16 = DSTextStyle(size: 17, weight: .bold, tracking: 0, lineHeight: 22, relative: .callout)
    /// Monospaced body — command cards, diagnostic log lines.
    static let mono13 = DSTextStyle(size: 17, weight: .regular, tracking: 0, lineHeight: 24, relative: .body, monospaced: true)

    // =========================================================== 12 · CAPTION
    /// Running metadata — a sentence that is not the subject of its surface.
    static let subhead13 = DSTextStyle(size: 12, weight: .regular, tracking: 0, lineHeight: 17, relative: .caption1)
    /// A label, chip, tag or timestamp — medium, because a caption that is a
    /// NAME rather than a sentence needs the weight to hold at this size.
    static let label12 = DSTextStyle(size: 12, weight: .medium, tracking: 0, lineHeight: 16, relative: .caption1)
    /// Was 11 — one point under `label12`, in the same rows, for months.
    static let label11 = DSTextStyle(size: 12, weight: .medium, tracking: 0, lineHeight: 16, relative: .caption2)
    static let tab10 = DSTextStyle(size: 12, weight: .medium, tracking: 0, lineHeight: 16, relative: .caption2)
    /// Monospaced caption.
    static let mono12 = DSTextStyle(size: 12, weight: .regular, tracking: 0, lineHeight: 16, relative: .caption1, monospaced: true)
    /// The streaming-response "still writing" dot (GenRenderer).
    static let indicator9 = DSTextStyle(size: 12, weight: .regular, tracking: 0, lineHeight: 16, relative: .caption2)
    /// A token's fallback avatar initial when no logo art exists (GenRenderer).
    static let badgeInitial11 = DSTextStyle(size: 12, weight: .bold, tracking: 0, lineHeight: 16, relative: .caption2)

    // ======================================================== OUTSIDE THE FIVE
    // `flourish148` WAS HERE and is deleted (prd §585, 2026-09-03). Its own
    // doc named its single purpose — "the onboarding step card's giant
    // background numeral" — and that card went with the onboarding fork in
    // §563, leaving the app's loudest rung with ZERO callers.
    //
    // It was proposed for re-use, on the reasoning that a system whose
    // personality is extreme proportions should spend its biggest type once
    // somewhere. That is backwards and is the lesson worth keeping: **a figure
    // gets its size because the CONTENT wants it, not because a token exists
    // needing a home.** The two candidates were measured against that and both
    // failed — the empty feed has no figure to draw (a count of nothing), and
    // the All lede sits under the day divider that already spends §506's one
    // crown per surface. An unused rung is a fork waiting to drift back (the
    // pour's `Color?` precedent, and §583's deleted paper), so it goes.

    // ============================================== WIDGETS — THEIR OWN SCALE
    // A widget is not a phone screen. A small tile is ~155pt across and its
    // text is sized by the tile rather than by the reader's distance from it,
    // so the five sizes above do not govern here and forcing them would
    // overflow every family. **The FAMILY does govern** — these all render in
    // Figtree like everything else, so a tile and the app it opens are the same
    // product. Sizes and weights are unchanged from what shipped.
    /// The Live Activity's "Recording" chrome label and its lock-screen timer.
    static let widgetChrome15  = DSTextStyle(size: 15, weight: .semibold, tracking: 0, lineHeight: 20, relative: .subheadline)
    /// Dynamic Island's compact-trailing timer.
    static let widgetTimer13   = DSTextStyle(size: 13, weight: .semibold, tracking: 0, lineHeight: 18, relative: .footnote)
    /// The accessory-rectangular widget's eyebrow, and the hero widget's new-count ring badge.
    static let widgetEyebrow11 = DSTextStyle(size: 11, weight: .semibold, tracking: 0, lineHeight: 15, relative: .caption2)
    /// The accessory-rectangular widget's title line.
    static let widgetTitle14   = DSTextStyle(size: 14, weight: .bold, tracking: 0, lineHeight: 19, relative: .footnote)
    /// The accessory-rectangular widget's subline.
    static let widgetSubline11 = DSTextStyle(size: 11, weight: .regular, tracking: 0, lineHeight: 15, relative: .caption2)
    /// The default-family hero widget's title line.
    static let widgetTitle17   = DSTextStyle(size: 17, weight: .bold, tracking: 0, lineHeight: 22, relative: .callout)
    /// The default-family hero widget's subline.
    static let widgetSubline12 = DSTextStyle(size: 12, weight: .regular, tracking: 0, lineHeight: 16, relative: .caption1)
    /// The medium widget's treemap cell terms — semibold so a one-word theme
    /// reads against its own cell's fill at a glance.
    static let widgetTreemapTerm12 = DSTextStyle(size: 12, weight: .semibold, tracking: 0, lineHeight: 15, relative: .caption1)
    /// The medium widget's recent-item row title, under the treemap.
    static let widgetRecentTitle12 = DSTextStyle(size: 12, weight: .semibold, tracking: 0, lineHeight: 16, relative: .caption1)
    /// The LARGE family's headline — the brief's sentence gets the room the
    /// medium tile never had.
    static let widgetHeadline20 = DSTextStyle(size: 20, weight: .bold, tracking: 0, lineHeight: 25, relative: .title3)
    /// A widget's own figure — the wallet tile's total.
    static let widgetFigure24  = DSTextStyle(size: 24, weight: .bold, tracking: 0, lineHeight: 28, relative: .title2)
}

private struct DSTextModifier: ViewModifier {
    let style: DSTextStyle
    // Reading the size category invalidates the view when the setting changes.
    @Environment(\.sizeCategory) private var sizeCategory
    // …and the Bold Text setting, which a custom family has to answer itself.
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        let scaled = UIFontMetrics(forTextStyle: style.relative)
            .scaledValue(for: style.size)
        let weight = legibilityWeight == .bold ? DSFont.bolder(style.weight) : style.weight
        content
            .font(DSFont.font(size: scaled, weight: weight, monospaced: style.monospaced))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Applies a token type style (font + tracking + line height), scaled for
    /// Dynamic Type.
    func dsText(_ style: DSTextStyle) -> some View {
        modifier(DSTextModifier(style: style))
    }

    /// An SF Symbol's point size, scaled for Dynamic Type (2026-08-11).
    ///
    /// **Why this exists.** A glyph is sized with `.font(.system(size:))`, which
    /// is a FROZEN size — while every label around it goes through `dsText` and
    /// grows with the person's text setting. The app had ~150 of these, so at an
    /// accessibility size the words grew and the icons beside them did not:
    /// chevrons shrinking away from their rows, a symbol sitting a third the
    /// height of the label it belongs to. Nothing about it is visible at the
    /// default size, which is why it survived every ramp pass.
    ///
    /// The anchor is derived from the size rather than passed per call site,
    /// and that is deliberate: `relative:` is a real judgement and 150 hand-made
    /// judgements is how a ramp drifts.
    ///
    /// **A glyph stays an SF SYMBOL and therefore stays SF** (prd §532) — the
    /// brand family has no symbol set, so this is the one place two families
    /// deliberately sit side by side. It is also the thing to re-eyeball first
    /// on a device: SF's optical metrics no longer match the text beside them.
    func dsGlyph(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        modifier(DSGlyphModifier(size: size, weight: weight))
    }
}

private struct DSGlyphModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.sizeCategory) private var sizeCategory

    /// The ramp's own rungs, read backwards: which text style does a glyph of
    /// this size sit beside?
    private var anchor: UIFont.TextStyle {
        switch size {
        case ..<12:   return .caption2
        case ..<13:   return .caption1
        case ..<15:   return .footnote
        case ..<17:   return .subheadline
        default:      return .body
        }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: UIFontMetrics(forTextStyle: anchor).scaledValue(for: size),
                             weight: weight))
    }
}

/// Digits that do not reflow, conditionally (2026-08-27, prd §501).
///
/// `monospacedDigit()` takes no argument, so a caller that wants tabular
/// figures only sometimes — a countdown inside its last ten seconds, and
/// proportional for the hours before that — has no way to say so without
/// duplicating the whole `Text`. This is that switch.
///
/// **Why it is conditional at all.** Tabular digits are wider and slightly
/// looser than the proportional set, so applying them for a countdown's whole
/// run changes how every one of those rows has always been set. Applied only
/// where a per-second label would otherwise reflow under the eye, it fixes a
/// defect that exists nowhere else.
///
/// It survives the move to Figtree because Figtree ships `tnum` — verified in
/// the font's own GSUB table before the family was adopted (prd §532).
private struct TabularDigits: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.monospacedDigit() } else { content }
    }
}

extension View {
    /// Tabular figures while `on`, the font's own digits otherwise.
    func dsTabularDigits(_ on: Bool) -> some View { modifier(TabularDigits(on: on)) }
}
