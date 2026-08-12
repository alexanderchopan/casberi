import SwiftUI

/// A purchase drawn as a receipt, and a watched product drawn as a card
/// (2026-08-12, prd §368; user: "less like a database field, more like a
/// receipt… start with shopping").
///
/// `PurchaseStage` decides every word and every verdict; this file only sets
/// them, so the reasoning lives in one Foundation-only place a harness can
/// compile whole. The two anatomies live in one view because they share the
/// eyebrow, the state badge and the provenance sentence, and splitting them
/// would be two files agreeing to say the same three things.
///
/// **What it replaces.** The title block, the link-preview card, and the spec
/// table's `From — from a store you follow`. Every fact drawn below was already
/// in the record: the price nothing rendered, the seller nothing rendered, the
/// Nutri-Score nothing rendered, the barcode sitting inside a `sourceRef`.
struct PurchaseStageView: View {
    let thing: Thing
    let reading: PurchaseStage.Reading
    /// How often you've paid this merchant. Passed in rather than read here so
    /// the view stays free of SwiftData — and nil is the common answer.
    var recurrence: PurchaseStageSource.Recurrence?

    /// Liveness guard (build 188, corollary 5 — `ThingRowKeying.swift`).
    /// SwiftUI re-evaluates a leaf view's body on the model's OWN observation,
    /// independent of the parent that built it, so a guard upstream cannot
    /// protect this. Every stored-property read below sits behind it.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch reading.archetype {
            case .receipt, .alarm: receiptBody
            case .watch:           watchBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Receipt

    @ViewBuilder private var receiptBody: some View {
        if let verb = reading.verb {
            Text(verbatim: verb)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        // The amount is the hero — money moving is the module doctrine's own
        // standing exception, and the wallet's `price40` rung is where it
        // belongs. A refund wears the confirm hue on §302's ruling that a gain
        // wears the colour whole; a purchase stays plain, because spending is
        // not a loss state and colouring it would editorialize.
        if let amount = reading.amount {
            Text(verbatim: amount)
                .dsText(.price40)
                .monospacedDigit()
                .foregroundStyle(reading.state?.tone == .good && reading.archetype == .receipt
                                 ? DS.confirm
                                 : reading.archetype == .alarm ? DS.attention : DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
                .padding(.top, 2)
        }
        Text(verbatim: reading.subject)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.top, DS.Space.s1)
        if let party = reading.seller {
            partyLine(party).padding(.top, DS.Space.s2)
        }
        if let badge = reading.state {
            badgeChip(badge).padding(.top, DS.Space.s3)
        }
        // The product's own artwork — stored by Bitrefill since it shipped and
        // only ever drawn as a 140pt link-card banner, which for an order with
        // no gift link was a banner scraped off a shared account page.
        if let art = thing.previewImageURL, !art.isEmpty {
            RemoteThumb(urlString: art, size: 132, fallback: thing.source)
                .padding(.top, DS.Space.s4)
        }
        if !reading.rungs.isEmpty {
            slab(reading.rungs).padding(.top, DS.Space.s4)
        }
        if let recurrence, let sentence = recurrenceSentence(recurrence) {
            Text(verbatim: sentence)
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s3)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.top, DS.Space.s3)
        }
        provenanceLine
    }

    // MARK: - Watch

    @ViewBuilder private var watchBody: some View {
        // The picture leads, at size. Nothing was bought, so nothing here is a
        // number first — the product IS the row, and its art was rendering as
        // a link-preview banner under a title the preview then re-scraped and
        // printed a second time.
        if let art = thing.previewImageURL, !art.isEmpty {
            RemoteThumb(urlString: art, size: 200, fallback: thing.source)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
        }
        Text(verbatim: reading.subject)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if let party = reading.seller {
            partyLine(party).padding(.top, DS.Space.s2)
        }
        if reading.amount != nil {
            priceBar.padding(.top, DS.Space.s3)
        }
        if let badge = reading.state, reading.history == nil {
            // A recorded move already says "price drop", louder and with the
            // number — so the chip stands down rather than saying it twice.
            badgeChip(badge).padding(.top, DS.Space.s3)
        }
        if let grade = reading.nutriScore {
            nutriScore(grade).padding(.top, DS.Space.s4)
        }
        if !reading.rungs.isEmpty {
            slab(reading.rungs).padding(.top, DS.Space.s4)
        }
        provenanceLine
    }

    /// The price, and what it fell from.
    ///
    /// The old number and the percentage are drawn ONLY from a recorded move
    /// (`PriceHistory`), never computed from the title's `" (was €90.00)"`
    /// parenthetical that used to be the only trace of it — that string is
    /// written in the language of the day the drop landed (§340).
    @ViewBuilder private var priceBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: reading.amount ?? "")
                .dsText(.stat24)
                .monospacedDigit()
                .foregroundStyle(DS.textPrimary)
            if let move = reading.history {
                Text(verbatim: PurchaseStage.money(move.was, move.currency))
                    .dsText(.callout15)
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(DS.textTertiary)
                if let fraction = move.fraction {
                    Text(verbatim: fraction.formatted(.percent.precision(.fractionLength(0))))
                        .dsText(.label12)
                        .monospacedDigit()
                        .foregroundStyle(move.fell ? DS.confirm : DS.textSecondary)
                        .padding(.horizontal, DS.Space.s2)
                        .padding(.vertical, DS.Space.s1)
                        .background(move.fell ? DS.confirm.opacity(0.16) : DS.fillFaint,
                                    in: Capsule())
                }
            }
        }
    }

    // MARK: - Nutri-Score

    /// The A–E scale Open Food Facts published, drawn as the scale it is.
    ///
    /// It has been stored as the tag `"Nutri-Score B"` since the seat shipped
    /// and rendered nowhere — the single reason anyone scans a barcode, sitting
    /// in a string array. **Read, never computed**: this app has no nutrition
    /// model, and a grade we derived would be a health claim invented by a
    /// bookmarking app. The caption says whose judgement it is, for the same
    /// reason.
    private func nutriScore(_ grade: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Nutri-Score")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            HStack(spacing: DS.Space.s1) {
                ForEach(Array("ABCDE"), id: \.self) { letter in
                    let on = String(letter) == grade
                    Text(verbatim: String(letter))
                        .dsText(.heading17)
                        .foregroundStyle(on ? Color.black : DS.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(on ? nutriColor(letter) : DS.fillFaint,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                         style: .continuous))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Nutri-Score \(grade) of A to E"))
            Text("Open Food Facts' grade, not ours.")
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The scale's own published colours. Fixed hex rather than a DS semantic
    /// hue: this is somebody else's five-step scale and re-tinting it to our
    /// green/amber/red would be re-grading the food.
    private func nutriColor(_ letter: Character) -> Color {
        switch letter {
        case "A": Color(hex: "#038141")
        case "B": Color(hex: "#85bb2f")
        case "C": Color(hex: "#fecb02")
        case "D": Color(hex: "#ee8100")
        default:  Color(hex: "#e63e11")
        }
    }

    // MARK: - Shared parts

    /// Who they are, and what they are TO YOU. The role word is the whole
    /// point: "Slickdeals" alone reads as a shop, and reading it as one is the
    /// false sentence this pass started from.
    private func partyLine(_ party: PurchaseStage.Party) -> some View {
        HStack(spacing: DS.Space.s2) {
            BridgeIcon(name: thing.source, size: DS.Face.badge)
            Text(verbatim: party.name)
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(verbatim: party.role)
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func badgeChip(_ badge: PurchaseStage.Badge) -> some View {
        Text(verbatim: badge.word)
            .dsText(.label12)
            .foregroundStyle(tint(badge.tone))
            .padding(.horizontal, DS.Space.s2 + 2)
            .padding(.vertical, DS.Space.s1 + 1)
            .background(tint(badge.tone).opacity(badge.tone == .neutral ? 0.10 : 0.16),
                        in: Capsule())
    }

    private func tint(_ tone: PurchaseStage.Tone) -> Color {
        switch tone {
        case .neutral:   DS.textSecondary
        case .attention: DS.attention
        case .good:      DS.confirm
        }
    }

    private func slab(_ rungs: [PurchaseStage.Rung]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(rungs.enumerated()), id: \.offset) { _, rung in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Text(verbatim: rung.key)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    Spacer(minLength: DS.Space.s3)
                    Text(verbatim: rung.value)
                        .dsText(.callout15)
                        .monospacedDigit()
                        .foregroundStyle(rung.dim ? DS.textSecondary : DS.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    @ViewBuilder private var provenanceLine: some View {
        if let sentence = reading.provenance {
            Text(verbatim: sentence)
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The gap rides the sentence, not the call site: padding an
                // absent line still pays the VStack's spacing, which is a
                // stray gap above the dial on every seat that says nothing.
                .padding(.top, DS.Space.s4)
        }
    }

    /// "The 5th time you've paid Netflix.com — $12.99 every time since March."
    ///
    /// **A COUNT and a COMPARISON, never a total** — see
    /// `PurchaseStageSource.Recurrence` for why a sum here would be silently
    /// wrong rather than merely absent.
    private func recurrenceSentence(_ r: PurchaseStageSource.Recurrence) -> String? {
        let name = reading.subject
        let count = String(localized: "You've paid \(name) \(r.count.formatted(.number)) times.")
        guard let direction = r.direction, let first = r.first, let since = r.since else {
            return count
        }
        let month = since.formatted(.dateTime.month(.wide).year())
        return switch direction {
        case 0:  String(localized: "\(count) \(PurchaseStage.money(r.current, r.currency)) every time since \(month) — the amount hasn't moved.")
        case 1:  String(localized: "\(count) Up from \(PurchaseStage.money(first, r.currency)) in \(month).")
        default: String(localized: "\(count) Down from \(PurchaseStage.money(first, r.currency)) in \(month).")
        }
    }
}
