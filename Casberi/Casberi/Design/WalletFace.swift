import SwiftUI

/// A watched wallet's face (2026-07-15) — the identity mark that ends "three
/// watched wallets, three identical blue icons". An ENS avatar when the
/// address published one (resolved and cached in WalletStore, read here by
/// hex address); otherwise a deterministic identicon seeded from the address,
/// so the SAME wallet always wears the SAME face and two wallets never collide.
/// Read-only public data, like everything the wallet shows.
///
/// The identicon is drawn in the app's own idiom — a soft seeded gradient with
/// two berry blobs floating over it — never a scannable QR-ish grid (that reads
/// as data, not identity). No image is ever hot-linked without a fallback: a
/// slow or broken avatar shows the identicon underneath until (if) it loads.
struct WalletFace: View {
    /// The stored hex address — the stable identity (labels are free text).
    let address: String
    var size: CGFloat = 36
    /// Circle instead of the app-icon squircle (prd §182, 2026-07-22) — the
    /// wallet manager's roster mock showed round faces (the "a person, not an
    /// icon" read a roster of PEOPLE wants), and every other use of this view
    /// — rename rows, the switcher chips, transfer stages — keeps the squircle
    /// it's always had. Same identicon and avatar underneath either way; only
    /// the clip shape changes, so a wallet's face is still recognizably itself
    /// in both places.
    var circular = false

    private var avatarURL: URL? {
        WalletStore.shared.avatarURL(for: address).flatMap(URL.init(string:))
    }

    var body: some View {
        identicon
            .overlay {
                // The demo's bundled faces (2026-08-12). An ENS avatar is a
                // real remote URL, and `AsyncImage` cannot resolve the
                // `sample:` scheme — so a seeded face fell straight through
                // to the identicon and the demo's own people were strangers
                // in the one room that names them. Same branch
                // `RemoteImageLoader` and `LinkPreviewCard` already carry.
                #if DEBUG
                if let ref = WalletStore.shared.avatarURL(for: address),
                   ref.hasPrefix("sample:"),
                   let bundled = UIImage.demoSample(for: ref) {
                    Image(uiImage: bundled).resizable().scaledToFill()
                } else if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .transition(.opacity.combined(with: .scale(scale: 1.06)))
                        }
                    }
                    .animation(DS.Motion.standard, value: avatarURL)
                }
                #else
                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if let image = phase.image {
                            // The hatch (prd §171, 2026-07-22): a resolved ENS
                            // avatar doesn't pop over the identicon, it settles
                            // onto it — a crossfade with a touch of scale, the
                            // wallet introducing itself. The moment is real (a
                            // name resolved just now), which is the only kind
                            // of moment §79 lets us animate.
                            image.resizable().scaledToFill()
                                .transition(.opacity.combined(with: .scale(scale: 1.06)))
                        }   // failure/empty: the identicon shows through
                    }
                    .animation(DS.Motion.standard, value: avatarURL)
                }
                #endif
            }
            .frame(width: size, height: size)
            .clipShape(circular
                       ? AnyShape(Circle())
                       : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size),
                                                   style: .continuous)))
            // Hidden, not labelled (prd §299's split). A face carries no
            // quantity — the datum is the ADDRESS, and every one of this
            // view's ~15 call sites already names it in the text beside the
            // face or in the label on the slot that holds it. Speaking here
            // would announce the same identity twice per row.
            //
            // Declared on the view rather than left to the caller because a
            // face that says nothing and claims nothing is indistinguishable
            // from one whose caller forgot, and the next call site is the one
            // that forgets (`ChartEntrance`'s own reasoning for making its
            // Reduce Motion parameter non-defaulted).
            .accessibilityHidden(true)
    }

    // MARK: - Identicon

    /// A seeded LCG off the address bytes — the same seed→same face rule the
    /// berry rain uses, so a wallet's identicon is stable across launches and
    /// screens without persisting anything.
    private var rng: (base: Double, alt: Double, b1: CGSize, b2: CGSize) {
        var state: UInt64 = 1
        for byte in address.lowercased().utf8 {
            state = state &* 31 &+ UInt64(byte)
        }
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            // >> 32 leaves a full 32-bit value (max UInt32.max), so the ratio
            // spans the whole [0, 1] — >> 33 would halve it, penning every hue
            // into the red→cyan half and both blobs into one quadrant.
            return Double(state >> 32) / Double(UInt32.max)
        }
        let base = next()                 // primary hue 0…1
        let alt = (base + 0.12 + next() * 0.18).truncatingRemainder(dividingBy: 1)
        return (base, alt,
                CGSize(width: next() - 0.5, height: next() - 0.5),
                CGSize(width: next() - 0.5, height: next() - 0.5))
    }

    /// The wallet's signature hue — the identicon's base hue, exposed so the
    /// combined sheet can draw each wallet's value line in the same color as
    /// its face (identity carried across surfaces). Folds and advances the
    /// seed exactly as `rng`'s first draw, so line and face always agree.
    static func tint(for address: String) -> Color {
        var state: UInt64 = 1
        for byte in address.lowercased().utf8 { state = state &* 31 &+ UInt64(byte) }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let hue = Double(state >> 32) / Double(UInt32.max)   // full [0,1] — matches rng
        return Color(hue: hue, saturation: 0.68, brightness: 0.78)
    }

    /// **A PERSON, NOT A PATTERN** (prd §483, 2026-08-26, user: *"these colored
    /// circles end up looking like bullets or buttons and not necessarily
    /// accounts"*, then *"i think silhouette is best"*).
    ///
    /// **What the gradient got wrong, and why it was not tunable.** It was two
    /// hues a short arc apart with two blurred blobs over them, and every one of
    /// those choices removed SILHOUETTE: a gradient has no edges, the blobs
    /// blurred at `size * 0.06` — about 2pt at the 36 the rail draws — so they
    /// smeared into one wash, and the hue was free-range, so two addresses could
    /// land a few degrees apart and read as the same face. What survived was a
    /// filled circle in a colour, which is a bullet.
    ///
    /// **The ruling that settles it is the user's own: these are "just different
    /// accounts of the same thing".** Your four or five wallets are not told
    /// apart by picture, they are told apart by NAME — so the mark's job is to
    /// say *a who lives here*, and identity belongs to the word beside it. An
    /// identicon inverts that: it claims the picture carries identity, and then
    /// five gradients have to be learned. One mark, honestly uniform, is the
    /// smaller promise and the true one.
    ///
    /// So: one person glyph, everywhere, on a ground tinted from the address.
    /// The tint is a WEAK cue by design — enough that a rail of five is not a
    /// row of clones, never enough to be mistaken for the identity itself.
    ///
    /// **A CURATED 12-stop wheel, not a free hue.** The old face could produce
    /// any hue at any moment, including two neighbours a hair apart and the
    /// muddy stretch between olive and brown. Fixed stops make both impossible,
    /// and they are muted rather than vivid because a rail of six saturated
    /// circles reads as a paint chart rather than as a roster.
    ///
    /// **CONSEQUENCE, and it is not optional:** with one uniform mark the rail
    /// MUST caption its faces, or five accounts are five identical glyphs. See
    /// `FaceScopeRail.namesInRoom` — §450 dropped those captions on the strength
    /// of the crown card naming the pick, and that caption is gone too.
    private var identicon: some View {
        // The SAME first draw `signatureHue` takes, so a wallet's face and its
        // value line still agree — the derivation is untouched, only what it
        // selects changed: a stop on a twelve-colour wheel instead of a hue on
        // a continuous one.
        let slot = Int(rng.base * Double(Self.grounds.count)) % Self.grounds.count
        let ground = Self.grounds[slot]
        let ink = Self.inks[slot]
        return ground
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(ink)
                    // The glyph's own optical centre sits low in its box; without
                    // this the head crowds the top of the circle and the mark
                    // reads as cropped rather than as a portrait.
                    .offset(y: size * 0.03)
            }
    }

    /// The twelve grounds. Muted and dark so the mark reads as a roster; fixed
    /// so no address can land on mud or a hair from its neighbour.
    fileprivate static let grounds: [Color] = [
        .fixed("#2E3A46"), .fixed("#3A3340"), .fixed("#243A34"), .fixed("#3E3630"),
        .fixed("#2C3348"), .fixed("#3D2F35"), .fixed("#26383D"), .fixed("#37333C"),
        .fixed("#2F3A2E"), .fixed("#42352C"), .fixed("#2A3140"), .fixed("#383036"),
    ]

    /// The paired inks, one per ground — light enough to hold the glyph at 20pt
    /// against its own ground, never white (a white silhouette on a dark circle
    /// is the system's own "no photo" placeholder, and this is not an absence).
    fileprivate static let inks: [Color] = [
        .fixed("#9FC0D8"), .fixed("#C4A9D6"), .fixed("#8FC9AE"), .fixed("#D8BA96"),
        .fixed("#A8B4E0"), .fixed("#D8A2AE"), .fixed("#93C3CC"), .fixed("#BEB2CE"),
        .fixed("#A7C79B"), .fixed("#DCB88E"), .fixed("#9EAAD4"), .fixed("#CBA6B4"),
    ]
}
