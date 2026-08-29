import SwiftUI

/// THIS PHONE'S OWN KEY, IN THE SCOPE ALREADY NAMED FOR KEYS (prd §523,
/// 2026-08-29).
///
/// ## WHY HERE AND NOT ON A CHIP OF ITS OWN
///
/// `VibenetSection` is five scopes and each one answers *what am I looking
/// at* — Home, Activity, Holdings, Accounts, Permissions. Signing answers
/// *what am I doing*, which is a mode and not a reading, so it gets no sixth
/// chip; and a sixth chip would be empty for everybody who has not made a key,
/// which is a scope that is usually a lie. Permissions already holds the key
/// census and the expiry runway, so this row leads the list it belongs to.
///
/// ## THE THREE STATES ARE THE WHOLE ROW
///
/// `VibenetDeviceKey.Presence` splits none / present / destroyed and this row
/// draws all three, because collapsing any two of them is a wrong sentence on
/// a security screen. In particular **destroyed is not absent**: a key erased
/// by a Face ID re-enrollment leaves accounts out there still authorizing a
/// key this phone can never produce again, and telling somebody "no key yet"
/// hides exactly that.
///
/// ## WHAT IT DOES NOT DO YET, AND WHY THERE IS NO BUTTON FOR IT
///
/// Making a key is a real local act that works today, so it is offered. Using
/// the key is not built: authorizing it onto an account is an on-chain write,
/// and `VibenetSigner.decide` refuses everything with `.derivationUnmeasured`
/// until this app knows how a P-256 public key becomes an `actorId`. So this
/// row states where it stands and offers nothing it cannot do — the §83 rule
/// that a control which does nothing is worse than an absent one.
///
/// ## LAYOUT
///
/// One indent. The face owns its column and no text ever enters it; every line
/// — title, standing, the cost sentence — starts at the same x, so the next
/// disc down is the next row (user ruling, 2026-08-29).
struct VibenetThisPhoneRow: View {
    /// Re-read on every appear rather than held: a key can be destroyed by
    /// something that happens entirely outside this app (Face ID re-enrolled
    /// in Settings), so a cached answer goes stale in the one direction that
    /// matters.
    @State private var presence: VibenetDeviceKey.Presence = .none
    @State private var fingerprint: String?
    @State private var busy = false
    @State private var failure: String?

    @Environment(ShellChrome.self) private var chrome

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(standing)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    // THE COST, on the line where it is paid. It is a third
                    // line in the SAME text column rather than a note floating
                    // under the row, so nothing sits beneath the disc.
                    if let cost {
                        Text(cost)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let failure {
                        Text(failure)
                            .dsText(.label11)
                            .foregroundStyle(DS.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DS.Space.s2)
            }
            if let verb {
                Button {
                    DSHaptic.tap()
                    make()
                } label: {
                    HStack(spacing: 5) {
                        Text(verb)
                        if busy {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .dsText(.label12)
                    .fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
                }
                .buttonStyle(PressSpring())
                .disabled(busy)
                .dsHover()
                // The verb sits at the text indent, never under the disc.
                .padding(.leading, DS.Face.rowCircle + DS.Space.s3)
            }
        }
        .onAppear(perform: refresh)
    }

    // MARK: - What the three states say

    private var icon: some View {
        ZStack {
            Circle()
                .fill(presence == .present ? Self.mark : DS.fillFaint)
                .frame(width: DS.Face.rowCircle, height: DS.Face.rowCircle)
            Image(systemName: presence == .destroyed ? "exclamationmark.triangle.fill" : "faceid")
                .dsGlyph(presence == .destroyed ? 11 : 13, weight: .semibold)
                .foregroundStyle(presence == .present ? Color.white
                                 : (presence == .destroyed ? DS.destructive : DS.textTertiary))
        }
        .accessibilityHidden(true)
    }

    private var title: String {
        switch presence {
        case .present:   String(localized: "Secure Enclave key")
        case .destroyed: String(localized: "This phone's key is gone")
        case .none:      String(localized: "No key on this phone")
        }
    }

    private var standing: String {
        switch presence {
        case .present:
            if let fingerprint {
                // The fingerprint is COPY and never an identity — four
                // characters at each end collide easily enough that a join on
                // it would authorize the wrong thing.
                String(localized: "P-256 \u{00B7} \(fingerprint)")
            } else {
                String(localized: "P-256, held in the Secure Enclave")
            }
        case .destroyed:
            String(localized: "Face ID was set up again, which erases the key. Nothing was signed and nothing was lost.")
        case .none:
            if !VibenetDeviceKey.enclaveAvailable {
                String(localized: "This device has no Secure Enclave, so it can't hold one.")
            } else if !VibenetDeviceKey.biometryAvailable() {
                String(localized: "Set up Face ID first \u{2014} the key is locked to it.")
            } else {
                String(localized: "A key here could act for a vibenet account.")
            }
        }
    }

    /// Said once, on the state where the cost is about to be taken on, and not
    /// repeated on every later open. On the destroyed row it would be telling
    /// somebody why the thing that already happened happened.
    private var cost: String? {
        switch presence {
        case .none where VibenetDeviceKey.enclaveAvailable && VibenetDeviceKey.biometryAvailable():
            String(localized: "It never leaves this phone, and re-enrolling Face ID erases it.")
        case .present:
            String(localized: "Not yet authorized on any account.")
        default:
            nil
        }
    }

    /// **No verb where there is nothing this app can do**, which is why the
    /// destroyed state offers none: the repair is an on-chain revoke from
    /// another authenticator, and this build cannot make one. Saying so is
    /// honest; a button that fails is not.
    private var verb: String? {
        switch presence {
        case .none where VibenetDeviceKey.enclaveAvailable && VibenetDeviceKey.biometryAvailable():
            String(localized: "Make a key")
        default:
            nil
        }
    }

    // MARK: - Acts

    private func refresh() {
        presence = VibenetDeviceKey.presence()
        fingerprint = VibenetDeviceKey.fingerprint()
    }

    private func make() {
        busy = true
        failure = nil
        // Off the main actor: key generation talks to the Secure Enclave and
        // can raise a prompt, and this room is drawn while a `@Query` feed is
        // live above it.
        Task {
            defer { busy = false }
            do {
                _ = try VibenetDeviceKey.create()
                refresh()
                DSHaptic.success()
                chrome.flash(String(localized: "Key made on this phone"))
            } catch {
                refresh()
                failure = Self.sentence(for: error)
            }
        }
    }

    /// Every failure gets its own sentence for `SafeSignBlock`'s reason: they
    /// all render as the same nothing-happened, and only one of them is
    /// something the person can act on.
    private static func sentence(for error: Error) -> String {
        guard let f = error as? VibenetDeviceKey.Failure else {
            return String(localized: "Couldn't make a key.")
        }
        switch f {
        case .noEnclave:
            return String(localized: "This device has no Secure Enclave.")
        case .noBiometry:
            return String(localized: "Set up Face ID first \u{2014} the key is locked to it.")
        case .alreadyExists:
            return String(localized: "There's already a key on this phone.")
        case .enclaveRefused:
            return String(localized: "The Secure Enclave refused to make a key.")
        case .keychainRefused(let status):
            return String(localized: "The keychain refused (code \(String(Int(status)))).")
        case .badDigest, .noKey, .signingRefused:
            return String(localized: "Couldn't make a key.")
        }
    }
}
