import SwiftUI

/// The consent step before Casberi pairs with a Logos Observer (2026-10-03).
/// Nothing is sent until Pair: the tray shows which Observer the QR names, where
/// it is, and each read it offers, and the person can untick any of them. The
/// Observer's answer (`granted_scopes`) is what the room then draws.
struct LogosObserverPairTray: View {
    let offer: LogosObserverWire.Offer
    var onPaired: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String>
    @State private var busy = false
    @State private var failure: String?

    init(offer: LogosObserverWire.Offer, onPaired: @escaping () -> Void = {}) {
        self.offer = offer
        self.onPaired = onPaired
        _chosen = State(initialValue: Set(offer.scopes))
    }

    var body: some View {
        DSTray(title: String(localized: "Pair with \(offer.name)"), height: 640,
               detents: [.height(640), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(verbatim: "\(offer.host) · \(offer.port)")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                    Text("It can read")
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.top, DS.Space.s2)
                    ForEach(offer.scopes, id: \.self) { scope in
                        DSToggleRow(title: Text(LogosObserverWire.scopeLabel(scope)),
                                    isOn: Binding(get: { chosen.contains(scope) },
                                                  set: { on in
                                                      if on { chosen.insert(scope) } else { chosen.remove(scope) }
                                                  }))
                    }
                    DSFootnote(prose: String(localized: "Casberi can't control your node. Your network can see that you're reaching it, but not what it reports."))
                        .padding(.top, DS.Space.s2)
                    if let failure {
                        Text(failure)
                            .dsText(.body17)
                            .foregroundStyle(DS.destructiveInk)
                    }
                    DSSlabButton(title: String(localized: "Pair"), busy: busy,
                                 enabled: !chosen.isEmpty && !busy, action: pair)
                        .padding(.top, DS.Space.s2)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func pair() {
        busy = true
        failure = nil
        // Keep the QR's order: the Observer echoes what it grants.
        let scopes = offer.scopes.filter { chosen.contains($0) }
        Task {
            let outcome = await LogosObserver.shared.pair(offer, scopes: scopes)
            busy = false
            switch outcome {
            case .paired:
                DSHaptic.tap()
                onPaired()
                dismiss()
            case .expired:
                failure = String(localized: "That pairing code expired. Make a new one on the Observer.")
            case .wrongObserver:
                failure = String(localized: "The Observer at that address isn't the one in the QR, so nothing was sent.")
            case .unreachable:
                failure = String(localized: "Couldn't reach the Observer. Check that this device is on the same network.")
            case .refused(let words):
                failure = words
            }
        }
    }
}
